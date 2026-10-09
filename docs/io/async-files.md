# Asynchronous file jobs

`lab.fs.async_files` adds bounded file reads, streaming directory listings and saves to
`lab.io.event_loop`. Native requests use libuv's filesystem worker pool; callbacks
stay on the owning loop and retain no Goose references. The CLI consumer is
`samples/cli/files_cli.goose`.

## Try it without graphics

```text
cmake -S . -B build-core -G "Visual Studio 17 2022" -A x64 -DGOOSE_LAB_GUI=OFF
cmake --build build-core --config Release --target files_cli io_runner git_contract --parallel
ctest --test-dir build-core -C Release -R "^git_integration$" --output-on-failure
./build-core/Release/files_cli.exe list lib/lab
./build-core/Release/files_cli.exe read README.md
./build-core/Release/files_cli.exe --limit 10 list lib/lab
./build-core/Release/files_cli.exe --cancel-after 0 read README.md
```

`read` emits exact file bytes to stdout only after success. `list` emits
`type<TAB>escaped-name` lines as pages arrive; its ordering is unspecified.
Diagnostics go to stderr. Exit 0 means a complete result, 1 means an operation
or resource error, and 2 means invalid CLI usage. A limited listing can already
have printed entries before returning 1: treat them as an incomplete listing.
The `read` and `list` commands do not change file or directory contents. The
`copy SOURCE DESTINATION` command uses [atomic replacement](atomic-save.md).

## Owned results under an explicit context

Start with `lab_fs_async_files::read(context, path, max_bytes=2097152)` or
`list(context, path, max_entries=4096)`. Check the returned handle's `code`.
Drive the context with `poll`/`wait`, then call the overloaded
`lab_fs_async_files::poll(handle)` for a typed result. These functions drain results;
they do not drive the event loop themselves. Timers, watchers, process streams
and file jobs can share the same context.

Both result types separate resource errors from operation completion:

| Field | Meaning |
| --- | --- |
| `code` | API/handle validity, such as WRONG_THREAD or CLOSED. |
| `done` | The operation has finished, including descriptor/directory cleanup. |
| `result` | Operation status; -1 until done, then an `lab.io.event_loop` code. |

An accepted handle can later complete with MISSING, NOT_REGULAR, NOT_DIRECTORY,
LIMIT, IO, MEMORY or CANCELLED. A successful start does not guarantee that the
path exists. Use `lab_io_event_loop::message` for both resource and operation codes.

Input paths are copied before start returns. Returned bytes and entry names
belong to Goose and survive another poll, native page reuse and handle closure.
Copies of handles remain aliases. Generation and resource-kind checks reject
stale IDs and a read ID fabricated as a listing ID. Use resources on their
creating thread. Close a child explicitly or close its context to clean up all
children. Finished handles still occupy capacity until closed.

## Reading regular files

A `Read` handle returns `Contents { code, done, result, bytes }`.
While running, bytes is empty. On successful completion, the first terminal
poll receives the entire owned byte buffer. Later polls retain done/result but
return no bytes. Failure returns no partial buffer. Retain the successful result
or copy its bytes into application-owned mutable storage before another poll.

Goose's `u8[]` makes the returned contents frozen at construction. A mutable
application state should hold a builder or rebuild its enclosing container;
overwriting a `Contents` variable containing frozen bytes is rejected by the
language. The CLI simply consumes the result once.

The byte budget is 0..2 MiB. Zero accepts an empty file. Native reads use chunks
of at most 64 KiB and probe one byte beyond the budget, so an exact-budget file
succeeds while growth past the budget reports LIMIT. Metadata can reject an
already oversized file before allocating its content buffer. The opened object
is checked again with fstat before reading, and the result becomes terminal
only after its descriptor has been closed.

Reads follow symlinks and require a regular file. Initial metadata rejects
directories and special objects; POSIX opening also requests nonblocking mode
to reduce the chance of blocking if a path is replaced by a FIFO between checks.
This is not a sandbox or race-proof type restriction. Ancestor links are followed,
and the target or contents can change between metadata, open and read. The
returned bytes are an observation, not a consistent filesystem snapshot or
multi-writer transaction. Reading consumes raw bytes, without UTF-8 validation,
line splitting or newline conversion.

## Listing one directory

A `Listing` handle returns `Page { code, done, result, entries }`. Each page has
at most 32 owned `Entry { kind, name }` values, with names at most 1024 bytes.
Names are basenames without `.` or `..`. Enumeration is nonrecursive, follows
the supplied directory path and does not traverse child links.

The implementation uses opendir/readdir/closedir instead of loading a whole
scandir result. One native page is retained. Consuming that page starts the next
request; not consuming it pauses enumeration. This bounds buffered names even
when the directory is large. Polling while closing a limited/error result drains
its retained entries without scheduling another read.

The total entry budget is 0..4096. An extra entry is probed before reporting a
complete listing, so exactly N entries under budget N succeeds. More entries,
or a name longer than 1024 bytes, produce LIMIT. Already delivered pages and
entries retained in the final page are incomplete observations on error. A
terminal page can contain entries; process the entries before inspecting done.
Later terminal polls contain no entries and retain completion metadata.

Type values are FILE, DIRECTORY, LINK, FIFO, SOCKET, CHARACTER, BLOCK and UNKNOWN.
Treat them as hints: UNKNOWN is valid, and types can change before a later open.
Directory mutation can also affect enumeration; no stable ordering or snapshot
is promised. Sort/accumulate owned entries at the consumer when needed.

Path inputs are currently UTF-8 without NUL and at most 32 KiB, consistent with
the other x native APIs. Entry names preserve raw OS bytes, including invalid
UTF-8 on POSIX. Such names can be displayed but cannot currently be opened through
this UTF-8 path API. `lab_text_strings::display_bytes` preserves valid Unicode and
escapes controls, backslashes and invalid bytes under a supplied output bound.
Keep the original name for identity; never pass its display label to an operation.
This utility also suits logs and does not depend on the UI or native filesystem.

## Cancellation, closing and native lifetime

`cancel(handle)` marks a pending operation cancelled and attempts uv_cancel for
its current request. It does not free request storage. If OS work is already
running, completion must arrive before the callback can close its descriptor
or directory. The chain then stops, drops pending output and finishes CANCELLED.
Cancelling an already terminal operation has no effect on its result. Continue
driving/polling to observe cancellation, or close to wait and discard results.

Close requests themselves are never cancelled. Each request is cleaned after
its callback and before reuse; directory name allocations are copied and cleaned
before the directory closes. The native bridge follows libuv's
[filesystem request lifecycle](https://docs.libuv.org/en/v1.x/fs.html) and
[cancellation rules](https://docs.libuv.org/en/v1.x/request.html).

`close(handle)` and `close(context)` synchronously wait for cleanup. A slow
filesystem, device replacement or network mount can make this wait long; a byte
limit bounds memory, not latency. There is no hard filesystem deadline in this
API. A failed asynchronous close submission uses synchronous cleanup as a final
fallback. Do not claim that cancelling an executing filesystem call forcibly
interrupts the OS.

The common registry invalidates closing IDs before waiting, releases its lock
during native cleanup, and reserves capacity until that cleanup finishes.
Other owning threads can keep operating independent contexts. Native storage
remains allocated until callbacks can no longer use it. Context shutdown marks
all children for cancellation first, then closes them, then frees the loop.

## Limits and remaining work

There are at most 16 read jobs and 16 listing jobs across contexts, in addition
to the [common context/registry bounds](io-core.md). Each read content buffer holds
at most 2 MiB plus a probe byte, and each listing holds one bounded native name page.
Results copied into Goose are owned separately. Link `goose_lab_loop` for these
APIs and `goose_lab_console` if choosing byte-preserving stdout/stderr.

The existing contracts exercise binary contents, a 2-MiB multi-read file,
Unicode names over multiple pages, exact/overflow/zero budgets, missing/type
errors, cancellation, copied paths, wrong-thread operations, repeated terminal
polls, stale IDs and closing contexts with pending jobs. CLI integration uses
disposable files and checks that their contents remain unchanged.

Windows is validated; other backends remain unvalidated. Prepared/automatic
atomic replacement shares the context; its cancellation and durability
contract is in [atomic saves](atomic-save.md). Recursive walking, raw OS path
inputs and network operations are not yet exposed.
