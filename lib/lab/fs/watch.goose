// Owned invalidations, not a filesystem transaction log. Poll on the opening thread.
namespace lab_fs_watch;
import std;
import lab.text.utf8;
import lab.io.event_loop;
let OK: i32 = 0; let MISSING: i32 = 1; let IO: i32 = 2; let LIMIT: i32 = 3;
let INVALID_PATH: i32 = 4; let NOT_DIRECTORY: i32 = 5; let UNSUPPORTED: i32 = 6; let CLOSED: i32 = 7; let WRONG_THREAD: i32 = 8; let MEMORY: i32 = 9;
let RENAME: i32 = 1; let CHANGE: i32 = 2;
struct Handle { id: u64 = 0, code: i32 = OK }
struct Event { kind: i32, path: u8[..1024] }
struct Batch { code: i32 = OK, rescan: bool = false, overflow: bool = false, events: Event[..64] = [] }
extern "glab_goose_watch_open" fn open_raw(path: const u8[:], subtree: bool, id: u64&) -> i32;
extern "glab_goose_watch_poll" fn poll_raw(id: u64, out: u8[:], count: i64&, flags: i32&) -> i32;
extern "glab_watch_close" fn close_raw(id: u64) -> bool;
extern "glab_goose_loop_watch" fn on_raw(context_id: u64, path: const u8[:], subtree: bool, id: u64&) -> i32;
// Attach to a caller-owned loop; poll drains only after lab_io_event_loop::poll/wait.
fn on(context: const lab_io_event_loop::Context&, path: const u8[:], subtree: bool = false) -> Handle {
    let code = lab_io_event_loop::status(context); if code != lab_io_event_loop::OK { return Handle { code: code }; }
    if path.len == 0 || path.len > 32768 || !lab_text_utf8::valid(path) { return Handle { code: INVALID_PATH }; }
    for byte in path { if byte == 0 { return Handle { code: INVALID_PATH }; } }
    var handle = Handle {}; handle.code = on_raw(context.id, path, subtree, handle.id); handle
}
fn open(path: const u8[:], subtree: bool = false) -> Handle {
    if path.len == 0 || path.len > 32768 || !lab_text_utf8::valid(path) { return Handle { code: INVALID_PATH }; }
    for byte in path { if byte == 0 { return Handle { code: INVALID_PATH }; } }
    var handle = Handle {}; handle.code = open_raw(path, subtree, handle.id); handle
}
fn close(handle: Handle&) -> bool {
    if handle.id == 0 { return false; }
    if !close_raw(handle.id) { return false; }
    handle.id = 0; handle.code = CLOSED; true
}
fn poll(handle: const Handle&) -> Batch {
    if handle.id == 0 { return Batch { code: if handle.code != OK { handle.code } else { CLOSED } }; }
    var bytes: u8[65536] = [0; 65536]; var count: i64 = 0; var flags: i32 = 0;
    let code = poll_raw(handle.id, bytes, count, flags);
    decode(bytes[..count], code, flags)
}
// Decode the native packet into owned names; discard partial detail on loss.
fn decode(bytes: const u8[:], code: i32 = OK, flags: i32 = 0) -> Batch {
    var batch = Batch { code: code, rescan: (flags & 1) != 0, overflow: (flags & 2) != 0 }; var at: i64 = 0;
    let count = bytes.len;
    if batch.rescan { return batch; }
    while at < count {
        let kind = bytes[at] as i32; at++; let first = at;
        while at < count && bytes[at] != 0 { at++; }
        if at == count || at - first > 1024 || !lab_text_utf8::valid(bytes[first..at]) || batch.events.len == 64 {
            batch.events.resize(0); batch.rescan = true; batch.overflow = true; return batch;
        }
        batch.events.push(Event { kind, bytes[first..at] }); at++;
    } batch
}
fn changed(batch: const Batch&) -> bool { batch.rescan || batch.events.len > 0 }
fn message(code: i32) -> const u8[:] {
    match code { 0 => "Watching", 1 => "Watch directory is missing", 2 => "Unable to watch this directory", 3 => "Watch capacity exceeded",
        4 => "Invalid watch path", 5 => "Watch path is not a directory", 6 => "Recursive watching is unavailable on this platform",
        7 => "Watch is closed", 8 => "Poll and close on the thread that opened the watch", _ => "Unable to allocate watch resources" }
}
// Watch the parent directory so atomic replacement/deletion/recreation is visible.
fn parent(path: const u8[:]) -> u8[>..], u8[>..] {
    var at: i64 = -1; for i in path.len { if path[i] == '/' || path[i] == '\\' { at = i; } }
    let root: u8[>..] = if at < 0 { "." } else if at == 0 { path[..1] } else if at == 2 && path[1] == ':' { path[..3] } else { path[..at] };
    let name: u8[>..] = path[at + 1..]; return root, name;
}
