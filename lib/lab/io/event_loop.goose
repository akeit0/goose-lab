// Explicit, thread-owned I/O context. UI-independent; callbacks stay in C.
namespace lab_io_event_loop;
import std;
let OK: i32 = 0; let MISSING: i32 = 1; let IO: i32 = 2; let LIMIT: i32 = 3;
let INVALID: i32 = 4; let NOT_DIRECTORY: i32 = 5; let UNSUPPORTED: i32 = 6;
let CLOSED: i32 = 7; let WRONG_THREAD: i32 = 8; let MEMORY: i32 = 9;
let CANCELLED: i32 = 10; let NOT_REGULAR: i32 = 11;
let NOT_READY: i32 = 12;
let WOULD_BLOCK: i32 = 13; let INPUT_CLOSED: i32 = 14;
struct Context { id: u64 = 0, code: i32 = OK }
struct Info { code: i32, resources: i64 = 0 }
extern "glab_loop_open" fn open_raw(id: u64&) -> i32;
extern "glab_loop_step" fn step_raw(id: u64, wait_ms: i64) -> i32;
extern "glab_loop_info" fn info_raw(id: u64, resources: i64&) -> i32;
extern "glab_loop_close" fn close_raw(id: u64) -> bool;
fn create() -> Context { var context = Context {}; context.code = open_raw(context.id); context }
fn status(context: const Context&) -> i32 { if context.id == 0 { if context.code == OK { CLOSED } else { context.code } } else { OK } }
// Drive readiness once. Resource-specific poll functions return owned data.
fn poll(context: const Context&) -> i32 { let code = status(context); if code != OK { return code; } step_raw(context.id, 0) }
fn wait(context: const Context&, maximum_ms: i64 = 50) -> i32 {
    let code = status(context); if code != OK { return code; } step_raw(context.id, maximum_ms)
}
fn info(context: const Context&) -> Info {
    let code = status(context); if code != OK { return Info { code: code }; }
    var resources: i64 = 0; let result = info_raw(context.id, resources); Info { result, resources }
}
// Cancels/joins native processes and closes all children before freeing the loop.
fn close(context: Context&) -> bool {
    if context.id == 0 || !close_raw(context.id) { return false; }
    context.id = 0; context.code = CLOSED; true
}
fn message(code: i32) -> const u8[:] {
    match code { 0 => "Ready", 1 => "Path is missing", 2 => "I/O operation failed", 3 => "I/O capacity exceeded",
        4 => "Invalid I/O arguments", 5 => "Path is not a directory", 6 => "Operation is unavailable on this platform",
        7 => "I/O resource is closed", 8 => "Use the I/O resource on its owning thread", 9 => "Unable to allocate I/O resources",
        10 => "I/O operation cancelled", 11 => "Operation requires a regular file", 12 => "File replacement is not ready to commit",
        13 => "Input queue is full; drain and retry", 14 => "Process input is closed",
        _ => "I/O operation failed" }
}
