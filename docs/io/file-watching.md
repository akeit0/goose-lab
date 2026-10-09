# File watching and reconciliation

`lab.fs.watch` turns native directory events into owned invalidations. `lab.io.debounce`
coalesces them before an application rereads its authoritative data. Git Viewer
uses that flow for external edits and staging; API Browser uses it to notify
about snapshot changes without discarding local edits.

## Small explicit API

```goose
import lab.fs.watch;
import lab.io.debounce;
var watch = lab_fs_watch::open("C:/work/project", true);
var changes = lab_io_debounce::State {};
// In the existing UI loop, on the thread that opened the watch:
let batch = lab_fs_watch::poll(watch);
if lab_fs_watch::changed(batch) { lab_io_debounce::push(changes, clock_ns()); }
if lab_io_debounce::ready(changes, clock_ns()) {
    // Reread the model here, or enqueue an owned request to a worker.
    lab_io_debounce::clear(changes);
}
lab_fs_watch::close(watch);
```

Check `watch.code` after opening and `batch.code` after polling. Missing paths,
non-directory paths, invalid UTF-8/NUL, capacity, IO, unsupported recursion,
closed IDs and wrong-thread polling have distinct codes. Watch the **parent**
of a file, then filter relative names: atomic replacement, deletion and
recreation can replace the file object itself. `lab_fs_watch::parent(path)` returns
owned parent/basename strings and accepts either slash style. On POSIX it
therefore does not support a literal backslash inside a filename.

The library holds at most 32 watches, each with a 64-KiB native packet buffer.
A returned batch owns at most 64 relative UTF-8 names of at most 1,024 bytes.
`Event.kind` contains RENAME/CHANGE flags; RENAME does not pair old/new names or
identify a specific create/delete operation. Unknown names, event errors,
encoding problems or exceeded bounds set `rescan`. Partial names are discarded;
`overflow` specifically reports a bridge/owned-batch bound. An OS may coalesce
or lose detail without setting that more specific flag. Always reread on
`rescan`, including a batch with zero named events.

Events are hints, not a transaction log. Network filesystems and OS queues can
miss events, and a watched directory can be moved or removed. Poll failures
disable automatic observation in the samples; manual Refresh/Reload remains
available. There is no periodic fallback scan or recovery of missing parents.

`lab_io_debounce::ready` defaults to 180 ms of quiet or a maximum wait of 1.2 seconds.
It does not consume pending work: only clear it when the application can act.
Git waits for its current worker/queued request to finish. Changes arriving
during a refresh schedule another refresh. Clock values are caller-supplied
nonnegative monotonic nanoseconds; elapsed comparisons avoid deadline overflow.

## Native ownership and platform support

The C bridge links `goose_lab_watch`; its interface enables `GOOSE_LAB_WATCH` in the
generated-C umbrella header. Add that target explicitly to a consumer. libuv
is a submodule pinned to v1.53.0, commit
`840404ce8ba7cc0204be52389a6cfff9f2c90fb6`, with its license in
`third_party/libuv/LICENSE`. It adds no Goose runtime or native callback API.

`open` owns a separately allocated libuv loop; its `poll` drives that loop
without waiting. `on(context, path, subtree)` attaches to a shared
`lab.io.event_loop` context; drive the context before draining that watch. Both forms
copy notifications into Goose-owned values. No Goose reference escapes into a
callback. Starting, driving, polling and closing belong to one thread;
copied IDs do not transfer ownership. Generation checks prevent a stale ID
from polling or closing a later watch. Close stops observation, drains native
close completion, then frees storage. Goose has no destructor here: close
explicitly before destroying the application and its worker infrastructure.
Closing a shared context also closes its watches. See the [I/O core](io-core.md)
for common timers, process streams and a CLI consumer.

libuv supports recursive filesystem events on Windows/macOS. Other backends
may silently ignore the recursive flag, so this bridge explicitly returns
UNSUPPORTED outside those platforms. Nonrecursive directory watches remain
available there; Git Viewer shows automatic refresh as unavailable and retains
manual Refresh. API Browser only needs a nonrecursive parent watch. Windows
is validated; other platforms are not. See libuv's
[filesystem events](https://docs.libuv.org/en/v1.x/fs_event.html) and
[handle lifecycle](https://docs.libuv.org/en/v1.x/handle.html).

## Reconcile according to the data's owner

Git is authoritative. After an invalidation, the existing worker rereads files
and the selected patch. `lab_git_repository::watch_paths` separately resolves the Git and
common directories, so linked worktrees also observe their external index,
HEAD and shared refs. Metadata lock files/objects/logs are mostly filtered;
worktree changes, including ignored build output, can still cause an extra
refresh. Opening a watch schedules one reconciliation to cover changes between
the initial read and watch setup. Auto pauses by closing all handles; enabling
it opens fresh handles and rereads changes made while paused.

Same-repository refresh keeps the filter, surviving expansion keys, selected
file and tree viewport. Identical patch bytes preserve text selection, find
results and scroll exactly. Changed bytes use `lab_ui_views_text::rebase`: byte
positions are clamped to the new source and UTF-8 boundaries, find results are
rebuilt and scroll is clamped by the existing view. This is positional retention,
not semantic tracking across inserted/deleted lines. A vanished file selects a
surviving visible file; switching repository or comparison mode resets text.

API Browser has two owners: the saved snapshot and the editable UI model. An
external change adds a compact Review notice and disables Save. The dialog
offers Load file (replace records and unsaved edits), Use local (retain records,
allow the next Save to replace the reviewed file), and Later. Invalid snapshots
disable both adoption and overwrite approval; repairing the file updates the
open dialog. Deletion permits Use local followed by Save to recreate it. Input
uses `lab.ui.overlays.modal`, so background shortcuts cannot bypass this decision.

`lab_fs_files::revision` streams at most 2 MiB into a small buffer and returns an
owned `{code, size, digest}` observation. The FNV-1a content digest catches
same-size changes even when timestamps do not change; it is not cryptographic.
Loaded/written snapshot receipts describe the **exact bytes** adopted or
written, rather than a later filesystem probe. Matching receipts suppress
self-write notifications. Save also rechecks disk before writing, even before
debounce reports an event. A version changing since Review requires another
Use local action; a file returning to its accepted version clears the notice.

These synchronous bounded reads suit this small local snapshot. They provide
neither locking nor compare-and-swap: a concurrent writer can still race the
check/atomic replacement, and hash collisions are possible. Applications needing
multi-writer transactions need a stronger storage protocol. No generic reactive
framework, escaping callbacks or implicit native-resource cleanup was added.

See [validation](../validation.md) for contract and integration checks.
