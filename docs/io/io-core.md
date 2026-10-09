# I/O core without a UI

`lab.io.event_loop`, `lab.io.timer`, `lab.fs.watch`, `lab.io.process_stream` and `lab.fs.async_files` provide a common
explicit owner for background work. They import no UI modules. The CLI sample
`samples/cli/io_runner.goose` consumes stdout/stderr while a command is running,
handles a cancellation timer and can observe a directory in the same loop.
Application/UI adapters consume owned results without changing the core lifecycle.
The [async file guide](async-files.md) extends it with bounded whole-file reads,
streaming directory pages and the `files_cli` consumer.
The [atomic save guide](atomic-save.md) adds prepared/automatic replacement,
commit receipts and cleanup without UI dependencies.
The [JSON field editor](../data/json-edit.md) composes these mechanisms with pure Goose
edits and a pre-commit re-read before publishing a configuration change.

## Build and try

From the repository root on Windows:

```text
cmake -S . -B build-core -G "Visual Studio 17 2022" -A x64 -DGOOSE_LAB_GUI=OFF
cmake --build build-core --config Release --target io_runner files_cli git_contract --parallel
ctest --test-dir build-core -C Release -R "^git_integration$" --output-on-failure
./build-core/Release/io_runner.exe -- python tests/process_fixture.py stream
./build-core/Release/io_runner.exe --cancel-after 100 -- python tests/process_fixture.py sleep
./build-core/Release/io_runner.exe --watch . --timeout 5000 -- python -c "import time; time.sleep(3)"
```

The last command prints a heartbeat and reports directory invalidations if
another process changes a file. The runner forwards stdout/stderr as raw bytes,
including split UTF-8 and binary output. Its diagnostic messages go to stderr.
`lab_io_console::binary_output()` selects byte-preserving stdout/stderr before the
runner writes anything. Windows' default C stdio text mode otherwise turns LF
into CRLF, including LF inside binary data. This explicit process-wide policy
flushes both streams, lasts until process exit and must be selected before
concurrent writers start. Link `goose_lab_console` for this independent utility.
Successful capture forwards child exit codes 0..255; timeout, cancellation,
capture failure and unsupported exit values return 1; invalid CLI usage returns 2.
It does not interpret a shell command, feed stdin or implement a terminal.
Writable child stdin is available in the library and separate
[Git object CLI](process-input.md).

## API and ownership

Create a context with `lab_io_event_loop::create()`. Check its `code`, then start
resources with that context. `lab_io_event_loop::poll(context)` drives native
readiness without waiting. `wait(context, maximum_ms)` drives it once with a
bounded wait (0..60000 ms). It can return early and does not identify a particular
resource: drain the resources you own after each call. Pending unconsumed results
prevent a needless wait. `info(context)` reports open child resources, including
finished processes and fired one-shot timers that have not been closed.

The pattern for a one-shot timer is:

```goose
import std;
import lab.io.event_loop;
import lab.io.timer;

fn main() {
    var context = lab_io_event_loop::create();
    if context.code != lab_io_event_loop::OK { return; }
    let timer = lab_io_timer::start(context, 100);
    if timer.code != lab_io_event_loop::OK { lab_io_event_loop::close(context); return; }
    loop {
        if lab_io_event_loop::wait(context, 50) != lab_io_event_loop::OK { break; }
        let fired = lab_io_timer::poll(timer);
        if fired.code != lab_io_event_loop::OK { break; }
        if fired.count > 0 { print("timer fired"); break; }
    }
    lab_io_event_loop::close(context);
}
```

The context belongs to the thread that created it. Starting, driving, polling,
cancelling and closing resources all belong to that thread. Operations on another
thread return WRONG_THREAD; close returns false. Independent threads can own and
drive independent contexts. This is not a cross-thread task submission API.

Handles contain generation-tagged IDs, not libuv storage or Goose references.
Copying a handle creates a non-owning alias; decide explicitly which variable
owns cleanup. Closing an alias invalidates the resource for every copy. Native
operations reject stale generations and the wrong resource kind. `status` only
checks the local context value; use `info` or an operation for a live validity
check. Failed construction has ID zero and carries its error in `code`.

`close(context)` cancels all process children, joins their workers, drains native
handle close callbacks and frees the context. It invalidates all child IDs.
Alternatively, close each child explicitly when its use ends, keeping the
context for other work. A stopped/fired timer or finished process still occupies
a slot until closed. Closing is synchronous; no destructor or implicit runtime
cleanup is assumed. Retained output is discarded when its process handle closes.

## Timers and directory observation

`lab_io_timer::start(context, delay_ms, repeat_ms=0)` returns a timer handle.
Zero repeat means one shot; zero delay fires when the loop is next driven.
`poll(handle)` returns an owned `Fired { code, count }` and clears the count.
`restart` and `stop` discard unconsumed firings from the old schedule. Delays and
repeat intervals are 0..86400000 ms. Repeat counts represent callbacks actually
delivered, not every interval missed while the caller was busy. The bridge
refreshes libuv's cached clock before scheduling. See libuv's
[timer semantics](https://docs.libuv.org/en/v1.x/timer.html).

`lab_fs_watch::on(context, directory, subtree=false)` attaches to this shared context.
Its `poll` only drains notifications after the context is driven. Existing
`lab_fs_watch::open` retains a private context and drives it inside `poll`, preserving
the earlier application API. Directory events are invalidations: on rescan or
overflow, reread the authoritative data. Recursive observation is supported on
Windows/macOS; the bridge rejects it elsewhere. See [file watching](file-watching.md).

## Process output and completion

`lab_io_process_stream::start(context, program, arguments, cwd="", options=Options {})`
copies program, cwd and literal argv into native-owned memory before returning.
Caller buffers can then change or disappear. Defaults are an 8000-ms deadline
and a 2-MiB combined stdout/stderr budget. Supported deadlines are 1..60000 ms
and budgets 1..2097152 bytes. There are at most 64 arguments and 32 KiB of packed
argument bytes, including NUL terminators. Program and cwd must be valid UTF-8
without embedded NUL, each at most 32 KiB.

`poll(handle)` returns an owned batch of up to 32 chunks, each at most 4096 bytes.
Each chunk has a STDOUT or STDERR tag. Preserve order within each stream; the
relative ordering of the two separate OS pipes is not a child-write ordering
guarantee. Chunks can split lines and UTF-8 code points. A text consumer must
keep incremental decoding state or aggregate bytes before decoding. Poll can
also return an empty batch while the process is running.

There are three separate results:

| Field | Meaning |
| --- | --- |
| `handle.code` / `batch.code` | Construction or resource API status; use `lab_io_event_loop::message`. |
| `batch.done` / `batch.result` | Completion of capture, using `lab.io.process` outcomes; use `lab_io_process::message`. |
| `batch.exit_code` | The child's exit status, meaningful according to the capture outcome. |

A missing executable can be accepted as a stream resource and later finish
with `lab_io_process::SPAWN`. Child exit 42 is a successful capture with exit_code 42.
Timeout/cancellation/output overflow are capture failures even if partial bytes
were delivered. Result and exit_code are -1 until done. Done becomes true only
after the worker finishes and all retained chunks have been drained; the last
batch can contain chunks and completion together. Later polls retain completion
metadata. `cancel(handle)` signals cancellation; continue driving/draining to
receive the terminal result, or close to cancel, join and discard retained output.
Set `Options { stdin: true }` to enable copied asynchronous send/retry and
explicit EOF. Each batch includes independent input progress/closure;
see [process input](process-input.md).

Process streaming reuses the existing native `glab_process_run` implementation on
a bounded set of dedicated native threads. It preserves Windows Job Object and
POSIX process-group cleanup rather than replacing them with `uv_spawn` in this
stage. It does not spawn Goose workers or retain Goose buffers. Queued output is
protected by a native mutex; `uv_async_send` wakes the owning loop. Wakeups can
coalesce, so the queue carries the data, not the notification count. See libuv's
[async handle](https://docs.libuv.org/en/v1.x/async.html).

Dedicated process threads also keep long-running commands out of libuv's shared
[filesystem/DNS worker pool](https://docs.libuv.org/en/v1.x/threadpool.html).
Each stream holds at most 512 queued chunks. Queue exhaustion cancels capture
with LIMIT, allocation failure with MEMORY; partial data is diagnostic, not
a valid complete capture. The byte budget bounds total output even when a fast
consumer keeps the queue short.

## Bounds and integration

Native bounds are 64 contexts, 64 child resources per context, 32 watches,
128 timers, 16 process streams, 16 reads, 16 listings, 16 writes and 256 registry slots in total. These are
implementation limits, reported as LIMIT rather than unbounded allocation.
Generation exhaustion retires a slot instead of permitting an old ID to match.

Link `goose_lab_loop` for the common core; it enables GOOSE_LAB_LOOP in the generated-C
glue. Consumers that import `lab.fs.watch` link the compatibility target
`goose_lab_watch`, which also enables its watch glue. The io_runner sample links
neither HTTP nor graphics; configure GOOSE_LAB_GUI=OFF to omit the graphics build.
libuv is pinned as a submodule; its license and version are documented in the
[third-party notices](../../THIRD_PARTY.md).

Windows is validated. Other native backends remain unvalidated. The current
core does not expose DNS, TCP, general IPC endpoints or a general executor.
Bounded reads, directory pages and atomic replacement share the same
owner/drain/close contract and have a CLI consumer. File-data sync is explicit;
parent-directory persistence is not guaranteed. Network framing/backpressure
still needs its own API.
