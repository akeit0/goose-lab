// Owned raw stdout/stderr chunks. Drive the parent lab.io.event_loop; no Goose worker needed.
namespace lab_io_process_stream;
import std;
import lab.io.event_loop;
import lab.io.process;
let STDOUT: i32 = 1; let STDERR: i32 = 2;
struct Options { timeout_ms: i64 = 8000, max_bytes: i64 = 2097152, stdin: bool = false, max_pending_bytes: i64 = 65536 }
struct Handle { id: u64 = 0, code: i32 = lab_io_event_loop::OK }
struct Chunk { stream: i32, bytes: u8[..4096] }
struct Input { enabled: bool = false, eof: bool = false, closed: bool = false, result: i32 = -1, pending: i64 = 0, accepted: i64 = 0, sent: i64 = 0 }
struct Batch { code: i32 = lab_io_event_loop::OK, done: bool = false, result: i32 = -1, exit_code: i64 = -1, chunks: Chunk[..32] = [], input: Input = Input {} }
extern "glab_goose_loop_process" fn start_raw(context_id: u64, program: const u8[:], cwd: const u8[:], args: const u8[:], timeout: i64, limit: i64, input: bool, pending: i64, id: u64&) -> i32;
extern "glab_goose_stream_poll" fn poll_raw(id: u64, bytes: u8[:], length: i64&, done: bool&, result: i32&, exit_code: i64&,
    enabled: bool&, eof: bool&, closed: bool&, input_result: i32&, pending: i64&, accepted: i64&, sent: i64&) -> i32;
extern "glab_goose_stream_send" fn send_raw(id: u64, bytes: const u8[:]) -> i32;
extern "glab_stream_eof" fn eof_raw(id: u64) -> i32;
extern "glab_stream_cancel" fn cancel_raw(id: u64) -> i32;
extern "glab_loop_resource_close" fn close_raw(id: u64, kind: i32) -> bool;
fn start(context: const lab_io_event_loop::Context&, program: const u8[:], arguments: const u8[:][:], cwd: const u8[:] = "", options: Options = Options {}) -> Handle {
    let code = lab_io_event_loop::status(context); if code != lab_io_event_loop::OK { return Handle { code: code }; }
    if program.len == 0 || !lab_io_process::valid(program) || !lab_io_process::valid(cwd) || arguments.len > 64 { return Handle { code: lab_io_event_loop::INVALID }; }
    var argv: u8[>..] = [];
    for argument in arguments {
        if !lab_io_process::valid(argument) || argument.len + 1 > 32768 - argv.len { return Handle { code: lab_io_event_loop::INVALID }; }
        argv.append(argument); argv.push(0);
    }
    var handle = Handle {}; handle.code = start_raw(context.id, program, cwd, argv, options.timeout_ms, options.max_bytes, options.stdin, options.max_pending_bytes, handle.id); handle
}
// All-or-nothing copy. WOULD_BLOCK accepts nothing; retry after driving/draining.
fn send(handle: const Handle&, bytes: const u8[:]) -> i32 { if handle.id == 0 { return lab_io_event_loop::CLOSED; } send_raw(handle.id, bytes) }
// No more sends. Close the pipe after all accepted bytes have been written.
fn eof(handle: const Handle&) -> i32 { if handle.id == 0 { return lab_io_event_loop::CLOSED; } eof_raw(handle.id) }
fn poll(handle: const Handle&) -> Batch {
    if handle.id == 0 { return Batch { code: if handle.code != 0 { handle.code } else { lab_io_event_loop::CLOSED } }; }
    var bytes: u8[131232] = [0; 131232]; var length: i64 = 0; var done = false; var result: i32 = -1; var exit_code: i64 = -1;
    var input = Input {};
    let code = poll_raw(handle.id, bytes, length, done, result, exit_code, input.enabled, input.eof, input.closed, input.result, input.pending, input.accepted, input.sent);
    var batch = Batch { code: code, done: done, result: result, exit_code: exit_code, input: input }; var at: i64 = 0;
    while at < length {
        assert(length - at >= 5); let stream = bytes[at] as i32; var size: i64 = 0;
        for i in 4 { size |= (bytes[at + 1 + i] as i64) << (i * 8); } at += 5;
        assert((stream == STDOUT || stream == STDERR) && size <= 4096 && size <= length - at);
        batch.chunks.push(Chunk { stream, bytes[at..at + size] }); at += size;
    } batch
}
fn cancel(handle: const Handle&) -> i32 { if handle.id == 0 { return lab_io_event_loop::CLOSED; } cancel_raw(handle.id) }
fn close(handle: Handle&) -> bool {
    if handle.id == 0 || !close_raw(handle.id, 4) { return false; } handle.id = 0; handle.code = lab_io_event_loop::CLOSED; true
}
