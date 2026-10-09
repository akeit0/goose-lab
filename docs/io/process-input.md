# Duplex processes and Git object requests

`lab.io.process_stream` can send bytes to stdin while capturing stdout/stderr under
the existing `lab.io.event_loop`. The GUI-free `git_objects` CLI sends successive
requests through one Git child and closes stdin after the last response.

## Try it

```text
cmake --build build-core --config Release --target git_objects git_contract utils_contract --parallel
./build-core/Release/git_objects.exe . HEAD HEAD:README.md
./build-core/Release/git_objects.exe . HEAD:README.md missing-object HEAD
```

Arguments are the repository and 1..64 object names, each 1..4096 UTF-8 bytes
without NUL. Stdout contains one JSON object per response in request order:
request, status, name, type, size and an escaped preview of at most 256 bytes.
The preview is a display label, not original content. Native stderr and
diagnostics go to stderr. Exit 0 means every object was found, 1 means an
unavailable object or transport/protocol failure, and 2 means invalid usage.
An unavailable object does not stop subsequent requests.

Git must support `cat-file --batch -Z`. The CLI
uses default output without filters/textconv/symlink following. It reads objects
without modifying the index/worktree. Each next request follows a complete
response from the still-running child, demonstrating interaction rather than
supplying one initial input blob to a one-shot command.

## Send, retry and EOF

Start with `Options { stdin: true }`. The default false preserves existing
null-input capture behavior. The synchronous `lab_io_process::run` API and the
`io_runner` CLI remain unchanged.

```goose
let arguments: const u8[:][4] = ["--no-pager", "cat-file", "--batch", "-Z"];
let child = lab_io_process_stream::start(context, "git", arguments, repository,
    lab_io_process_stream::Options { stdin: true });
let code = lab_io_process_stream::send(child, "HEAD\0");
// Drive/drain until the response arrives. Send another request, or:
let ending = lab_io_process_stream::eof(child);
```

`send` copies all bytes before returning OK. Caller storage can then change.
Input is raw bytes, with no newline conversion or UTF-8 requirement. WOULD_BLOCK
accepts nothing: drive/drain, then retry. It is recoverable backpressure, not
partial acceptance or cancellation. A send larger than the entire budget
returns LIMIT and must be split. Disabled stdin returns UNSUPPORTED, closed or
EOF-requested stdin returns INPUT_CLOSED, and cancellation refuses new sends.
Resources retain the normal owner-thread, kind and generation checks.

`max_pending_bytes` defaults to 65536, with a range of 1..2097152. At most 512
send allocations bound metadata even for one-byte sends. Pending bytes include
native write-buffer copies until the OS confirms the write. OS buffers are at
most 4096 bytes. Empty sends allocate nothing. Total input may exceed the queue
budget as bytes drain; existing total output budgets/deadlines still apply.

`eof` rejects new sends immediately, then closes the pipe after accepted bytes
are written. Repeated EOF returns OK. It does not terminate the child or wait
for a reply. Drive/drain to completion, then close the stream or its context.

## Independent progress and outcomes

Every `Batch` includes an owned scalar `Input` snapshot:

| Field | Meaning |
| --- | --- |
| enabled | Writable stdin was requested at start. |
| eof | The owner requested no more input. |
| closed | The parent's input pipe is closed. |
| result | -1 while open, then an lab.io.event_loop status. |
| pending | Accepted bytes awaiting confirmed OS write; zero after closure. |
| accepted | Total bytes accepted by send. |
| sent | Total bytes confirmed written to the OS pipe. |

Sent does not mean consumed, parsed or acknowledged by the child; only a
protocol response establishes that. After failure/cancellation, accepted minus
sent identifies bytes not confirmed written. Unsent buffers are freed. Disabled
input reports enabled false, closed true and result OK. Progress/closure wakes
the loop; polling drains that notification, so batches can contain progress
without output. Later polls retain counters.

Keep batch.code (resource validity), batch.result (lab.io.process capture), and
batch.input.result (lab.io.event_loop stdin transport) separate. A child can close
stdin and still produce useful output. Input failure drops that channel while
output capture continues. The consumer decides whether its protocol can continue.
Process done still requires worker completion and draining captured output.

## Blocked writers and lifetime

The implementation extends existing Windows Job Object/POSIX process-group
cleanup. Native callbacks retain native storage only. The stream mutex protects
input/output queues and counters, and libuv's async handle wakes the owner.

On Windows each writable stream adds one native writer thread. Blocking
anonymous-pipe writes cannot stop the independent output worker from draining
pipes or checking deadlines/cancellation. Shutdown sets the writer stop flag,
closes the Job Object to end readers, requests
[CancelSynchronousIo](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelsynchronousio),
and joins the writer before freeing queues/context storage. Writes can race
cancellation and complete; actual sent counts remain authoritative. The
16-stream limit bounds additional writers to 16 threads.

POSIX uses nonblocking stdin and one bounded write per capture iteration,
handling partial writes. SIGPIPE is blocked around that thread's write and
a newly generated EPIPE signal consumed without changing the application's
process-wide disposition. See [write semantics](https://man7.org/linux/man-pages/man2/write.2.html).
Windows is validated; POSIX remains unvalidated.

## Framing utilities

`lab.collections.byte_buffer` is a pure Goose queue with a cursor and byte budget. Append is
all-or-nothing, consume checks its range, and take returns an owned builder.
Consumed prefixes are compacted before growth. The builder is the final struct
field as Goose requires; length changes use an explicit field reference.
Owned copies survive compaction/reuse. Take/first assert caller preconditions;
untrusted input goes through availability checks before either is called.

`lab.git.batch` appends chunks and emits owned Object results through next. Drain
next until ready is false, then finish after stdout/process completion. A body
is exposed only after its full advertised size and trailing NUL arrive. Errors
are sticky and retained objects survive decoder reuse. Headers are limited to
8192 bytes, bodies default to 2 MiB, and the buffer to 2 MiB plus 12 KiB. Drain
between batches to respect that bound.

The decoder accepts canonical 40/64-digit OIDs, blob/commit/tree/tag types and
missing/ambiguous/excluded/submodule responses. It follows Git's
[batch output specification](https://git-scm.com/docs/git-cat-file#_batch_output).
NUL frames headers/requests/trailers; body size frames raw binary content.
Chunk boundaries have no protocol meaning. EOF with a partial header/body is
TRUNCATED. The process's total 2-MiB output budget independently includes
headers and stderr, so the CLI may hit that limit before the per-object budget.

Existing contracts cover all splits of a binary frame, retained/multiple/empty
objects, malformed/truncated framing and bounds. Process integration covers
output-before-input, binary echo, retry, copied input, live dialogue, zero/data
EOF, closed readers, wrong threads, blocked-write cancellation/deadline/context
close and descendant cleanup. The CLI uses a disposable real repository.
See [validation](../validation.md) for running these checks.

This remains a bounded command session: deadlines 1..60000 ms (default 8000),
and a total output limit. Indefinite sessions, general IPC endpoints and language
server protocols require further APIs driven by actual consumers.
