// Bounded native jobs under lab.io.event_loop. Drive the loop, then drain owned results.
namespace lab_fs_async_files;
import std;
import lab.io.event_loop;
import lab.text.utf8;
let UNKNOWN: i32 = 0; let FILE: i32 = 1; let DIRECTORY: i32 = 2; let LINK: i32 = 3;
let FIFO: i32 = 4; let SOCKET: i32 = 5; let CHARACTER: i32 = 6; let BLOCK: i32 = 7;
struct Read { id: u64 = 0, code: i32 = lab_io_event_loop::OK }
struct Listing { id: u64 = 0, code: i32 = lab_io_event_loop::OK }
struct Write { id: u64 = 0, code: i32 = lab_io_event_loop::OK }
// Flush temporary file data before publication; does not flush its parent directory.
struct WriteOptions { sync_file: bool = true }
// size/digest acknowledge committed input. written is progress, not publication.
// temporary identifies an owned staging file remaining after failed cleanup.
struct Saved {
    code: i32 = lab_io_event_loop::OK, ready: bool = false, done: bool = false, result: i32 = -1,
    committed: bool = false, synced: bool = false, cleanup_code: i32 = lab_io_event_loop::OK,
    written: i64 = 0, size: i64 = 0, digest: u64 = 0, temporary: u8[..32768] = []
}
struct Contents { code: i32 = lab_io_event_loop::OK, done: bool = false, result: i32 = -1, bytes: u8[] = [] }
// name is a raw basename; type is a hint. It can be UNKNOWN on some filesystems.
struct Entry { kind: i32, name: u8[..1024] }
struct Page { code: i32 = lab_io_event_loop::OK, done: bool = false, result: i32 = -1, entries: Entry[..32] = [] }
extern "glab_goose_loop_read" fn read_raw(context_id: u64, path: const u8[:], limit: i64, id: u64&) -> i32;
extern "glab_goose_loop_directory" fn list_raw(context_id: u64, path: const u8[:], limit: i64, id: u64&) -> i32;
extern "glab_goose_read_poll" fn read_poll_raw(id: u64, done: bool&, result: i32&, bytes: u8[>..]&) -> i32;
extern "glab_goose_directory_poll" fn list_poll_raw(id: u64, bytes: u8[:], length: i64&, done: bool&, result: i32&) -> i32;
extern "glab_file_cancel" fn cancel_raw(id: u64, kind: i32) -> i32;
extern "glab_loop_resource_close" fn close_raw(id: u64, kind: i32) -> bool;
extern "glab_goose_loop_replace" fn write_raw(context_id: u64, path: const u8[:], bytes: const u8[:], automatic: bool, sync_file: bool, id: u64&) -> i32;
extern "glab_write_commit" fn commit_raw(id: u64) -> i32;
extern "glab_goose_write_poll" fn write_poll_raw(id: u64, ready: bool&, done: bool&, result: i32&, committed: bool&, synced: bool&,
    cleanup: i32&, written: i64&, size: i64&, digest: u64&, temporary: u8[:], length: i64&) -> i32;
fn valid_path(path: const u8[:]) -> bool {
    if path.len == 0 || path.len > 32768 || !lab_text_utf8::valid(path) { return false; }
    for byte in path { if byte == 0 { return false; } } true
}
// Follows symlinks, requires a regular file. 0..2 MiB; no partial bytes on failure.
fn read(context: const lab_io_event_loop::Context&, path: const u8[:], max_bytes: i64 = 2097152) -> Read {
    let code = lab_io_event_loop::status(context); if code != 0 { return Read { code: code }; }
    if !valid_path(path) { return Read { code: lab_io_event_loop::INVALID }; }
    var handle = Read {}; handle.code = read_raw(context.id, path, max_bytes, handle.id); handle
}
// Nonrecursive, unsorted pages. 0..4096 entries; one extra is probed for LIMIT.
fn list(context: const lab_io_event_loop::Context&, path: const u8[:], max_entries: i64 = 4096) -> Listing {
    let code = lab_io_event_loop::status(context); if code != 0 { return Listing { code: code }; }
    if !valid_path(path) { return Listing { code: lab_io_event_loop::INVALID }; }
    var handle = Listing {}; handle.code = list_raw(context.id, path, max_entries, handle.id); handle
}
fn start_write(context: const lab_io_event_loop::Context&, path: const u8[:], bytes: const u8[:], automatic: bool, options: WriteOptions) -> Write {
    let code = lab_io_event_loop::status(context); if code != 0 { return Write { code: code }; }
    if !valid_path(path) { return Write { code: lab_io_event_loop::INVALID }; }
    if bytes.len > 2097152 { return Write { code: lab_io_event_loop::LIMIT }; }
    var handle = Write {}; handle.code = write_raw(context.id, path, bytes, automatic, options.sync_file, handle.id); handle
}
// Copy all input, write/flush a sibling temporary, then publish automatically.
fn replace(context: const lab_io_event_loop::Context&, path: const u8[:], bytes: const u8[:], options: WriteOptions = WriteOptions {}) -> Write {
    start_write(context, path, bytes, true, options)
}
// Prepare only; after ready, the owner decides to commit or cancel.
fn prepare(context: const lab_io_event_loop::Context&, path: const u8[:], bytes: const u8[:], options: WriteOptions = WriteOptions {}) -> Write {
    start_write(context, path, bytes, false, options)
}
fn commit(handle: const Write&) -> i32 { if handle.id == 0 { return lab_io_event_loop::CLOSED; } commit_raw(handle.id) }
fn poll(handle: const Write&) -> Saved {
    if handle.id == 0 { return Saved { code: if handle.code != 0 { handle.code } else { lab_io_event_loop::CLOSED } }; }
    var saved = Saved {}; var temporary: u8[32768] = [0; 32768]; var length: i64 = 0;
    saved.code = write_poll_raw(handle.id, saved.ready, saved.done, saved.result, saved.committed, saved.synced,
        saved.cleanup_code, saved.written, saved.size, saved.digest, temporary, length);
    saved.temporary = temporary[..length]; saved
}
fn cancel(handle: const Write&) -> i32 { if handle.id == 0 { return lab_io_event_loop::CLOSED; } cancel_raw(handle.id, 7) }
fn close(handle: Write&) -> bool {
    if handle.id == 0 || !close_raw(handle.id, 7) { return false; } handle.id = 0; handle.code = lab_io_event_loop::CLOSED; true
}
// Bytes are delivered once. Later polls retain completion metadata only.
fn poll(handle: const Read&) -> Contents {
    if handle.id == 0 { return Contents { code: if handle.code != 0 { handle.code } else { lab_io_event_loop::CLOSED } }; }
    var bytes: u8[>..] = []; var done = false; var result: i32 = -1;
    let code = read_poll_raw(handle.id, done, result, bytes); Contents { code, done, result, bytes }
}
fn poll(handle: const Listing&) -> Page {
    if handle.id == 0 { return Page { code: if handle.code != 0 { handle.code } else { lab_io_event_loop::CLOSED } }; }
    var bytes: u8[32864] = [0; 32864]; var length: i64 = 0; var done = false; var result: i32 = -1;
    let code = list_poll_raw(handle.id, bytes, length, done, result);
    var page = Page { code: code, done: done, result: result }; var at: i64 = 0;
    while at < length {
        assert(length - at >= 3); let kind = bytes[at] as i32;
        let size: i64 = bytes[at + 1] | ((bytes[at + 2] as i64) << 8); at += 3;
        assert(size > 0 && size <= 1024 && size <= length - at && kind <= BLOCK);
        page.entries.push(Entry { kind, bytes[at..at + size] }); at += size;
    } page
}
fn cancel(handle: const Read&) -> i32 { if handle.id == 0 { return lab_io_event_loop::CLOSED; } cancel_raw(handle.id, 5) }
fn cancel(handle: const Listing&) -> i32 { if handle.id == 0 { return lab_io_event_loop::CLOSED; } cancel_raw(handle.id, 6) }
fn close(handle: Read&) -> bool {
    if handle.id == 0 || !close_raw(handle.id, 5) { return false; } handle.id = 0; handle.code = lab_io_event_loop::CLOSED; true
}
fn close(handle: Listing&) -> bool {
    if handle.id == 0 || !close_raw(handle.id, 6) { return false; } handle.id = 0; handle.code = lab_io_event_loop::CLOSED; true
}
fn kind_name(kind: i32) -> const u8[:] {
    match kind { 1 => "file", 2 => "directory", 3 => "link", 4 => "fifo", 5 => "socket", 6 => "character", 7 => "block", _ => "unknown" }
}
