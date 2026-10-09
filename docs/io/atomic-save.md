# Asynchronous atomic saves

`lab.fs.async_files` writes a complete sibling temporary file and renames it onto
the destination. The destination is never opened for truncation. This supports
configuration, snapshot and document saving under the existing explicit
`lab.io.event_loop` owner.

## Try the CLI

Build `files_cli` as described in [async files](async-files.md), then:

```text
./build-core/Release/files_cli.exe copy source.bin saved.bin
./build-core/Release/files_cli.exe --limit 4096 copy settings.json backup.json
./build-core/Release/files_cli.exe --cancel-after 0 copy source.bin saved.bin
```

Copy reads the source completely before beginning a replacement, so copying a
file onto itself is supported. The source is limited to 2 MiB by default.
Successful copy prints the committed byte count and file-data sync flag to
stderr and emits no payload to stdout. Exit codes remain 0 for success, 1 for
operation/resource failure, and 2 for invalid usage. Failed reads and saves
before publication leave the destination unchanged by this operation.

## Automatic replacement or explicit publication

`replace(context, path, bytes, options=WriteOptions {})` starts an automatic
save. `prepare` takes the same arguments but pauses before publication. Both
return a `Write { id, code }`; path and payload are copied before returning.
Drive the context, then poll the write handle for an owned `Saved` result.

```goose
import std;
import lab.io.event_loop;
import lab.fs.async_files;

fn main() {
    var context = lab_io_event_loop::create();
    if context.code != 0 { return; }
    var save = lab_fs_async_files::prepare(context, "settings.json", "{\"theme\":\"dark\"}\n");
    if save.code != 0 { lab_io_event_loop::close(context); return; }
    var requested = false;
    loop {
        if lab_io_event_loop::wait(context, 50) != 0 { break; }
        let state = lab_fs_async_files::poll(save);
        if state.code != 0 { break; }
        if state.ready && !requested {
            // A consumer can revalidate its model/revision here, or cancel.
            if lab_fs_async_files::commit(save) != 0 { break; }
            requested = true;
        }
        if state.done {
            print(str("committed=", state.committed, " result=", state.result));
            break;
        }
    }
    lab_fs_async_files::close(save);
    lab_io_event_loop::close(context);
}
```

The native sequence is: inspect destination, create a unique temporary in its
parent, write bounded chunks, optionally sync file data, close the descriptor,
recheck the destination type, then rename. A prepared job reports `ready` after
its descriptor is closed. `commit` queues the recheck/publication sequence;
calling it before ready or twice returns NOT_READY. Preparing does not reserve
or lock the destination. Revalidating a revision then committing is still an
observation followed by an operation, not compare-and-swap.

The result fields separate API status, progress and the publication receipt:

| Field | Meaning |
| --- | --- |
| `code` | Resource/API validity, such as CLOSED or WRONG_THREAD. |
| `ready` | Prepared file is complete and awaits commit or cancel. |
| `done`, `result` | Operation and cleanup finished; result is -1 while pending. |
| `committed` | Rename succeeded. The replacement became visible. |
| `synced` | File-data flush succeeded before publication. |
| `written` | Bytes confirmed written to the temporary; not bytes saved to the destination. |
| `size`, `digest` | Committed input length and FNV-1a digest; zero until committed. |
| `cleanup_code` | Separate error closing/removing temporary resources, normally OK. |
| `temporary` | Owned path of a staging file still present after cleanup, otherwise empty. |

Repeated polls retain the receipt. A successful zero-byte save has size zero
and the FNV empty-input digest. A receipt acknowledges the submitted bytes,
rather than probing the destination afterward and potentially acknowledging
another writer's contents. FNV is a bounded revision aid, not cryptographic
identity. Concurrent saves each publish a whole file; the last rename wins.

## Cancellation and cleanup

Cancelling before publication stops further stages, closes the descriptor and
removes the owned temporary. Poll until done to observe CANCELLED and inspect
cleanup status. Cleanup close/unlink requests are never cancelled. Request
storage remains alive through callbacks; see libuv's
[filesystem lifecycle](https://docs.libuv.org/en/v1.x/fs.html) and
[cancellation rules](https://docs.libuv.org/en/v1.x/request.html).

If rename is already executing, cancellation may arrive too late. A successful
rename returns OK with `committed=true` even if cancellation was requested.
Reporting CANCELLED at that point would incorrectly claim the save did not
happen. Cancelling a terminal save preserves its receipt.

Explicit `close(write)` cancels pending work, waits for cleanup and discards
the result. It can still publish if rename was already executing; close is not
rollback. Cancel and drain before close when the application needs the outcome.
Context close applies the same cleanup to all children. Cleanup failures are
reported separately when polled; a remaining temporary path lets a consumer
offer recovery. After process termination or a crash, staging files may remain;
the library does not remove arbitrary files matching its naming pattern.

## What replacement and sync guarantee

The temporary uses `.goose-lab-save-XXXXXX` in the destination's parent, ensuring
the same filesystem for ordinary paths. No delete-first or copy fallback is
used if rename fails. Existing readers can retain the old file; subsequent
opens see the replacement. Filesystem-specific rename semantics still apply.
On Windows, libuv uses
[MoveFileExW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw)
with replacement enabled. Read-only destinations or open handles without
delete sharing can prevent replacement; that failure preserves the old file.

`WriteOptions { sync_file: true }` is the default. It flushes the temporary's
file data before rename; false skips that flush and leaves `synced=false`.
The parent directory is not flushed, and the Windows rename does not request
write-through. `committed` means publication succeeded, not that it will survive
power loss. This API does not claim a durable multi-file transaction.

An existing final symlink, directory or special object is rejected with
NOT_REGULAR. The final path is checked both before preparation and before
publication. Ancestor links are followed and a competing change can race the
checks; these checks are not a filesystem sandbox. Relative paths are not
anchored to a directory handle; do not change the process working directory
while jobs are active. Parent directories are not created automatically.

Replacement creates a new file object. On POSIX, an existing destination's
ordinary permission bits (0777) are copied from the initial observation; a new
file starts with 0600. Special mode bits, ownership, ACLs, timestamps and extended
attributes are not preserved. Windows uses the new temporary's metadata and
inherited permissions; it does not preserve the replaced object's ACLs or
attributes. Hard-linked aliases continue to reference the old object.

## Ownership, bounds and validation

All operations use the creating thread and the common generation/kind registry.
Copied handles alias one native resource. Finished and ready writes occupy a
slot until closed. There are at most 16 writes across contexts, each with at
most 2 MiB copied input and write requests of at most 64 KiB. Input paths must
be UTF-8 without NUL, at most 32 KiB; constructing the sibling name can also
exceed the path budget and return INVALID. Link `goose_lab_loop`.

Filesystem work uses libuv's worker pool. Byte/job bounds control memory, not
filesystem latency; cancellation cannot force interruption of executing OS
work and synchronous close can wait. The existing contracts exercise
prepare/commit/cancel, copied input, receipts, binary/empty/2-MiB saves, stale
IDs, wrong threads, destination type changes, capacity and context cleanup.
The CLI harness checks old contents on cancellation/read/rename failures and
checks for leaked staging files in disposable directories. Windows is validated;
other backends remain unvalidated.
