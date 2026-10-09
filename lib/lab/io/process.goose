// Synchronous mechanism; call on a Goose worker for interactive applications.
namespace lab_io_process;
import std;
import lab.io.cancel;
import lab.text.utf8;
let OK: i32 = 0; let INVALID: i32 = 1; let SPAWN: i32 = 2; let IO: i32 = 3;
let LIMIT: i32 = 4; let TIMEOUT: i32 = 5; let CANCELLED: i32 = 6; let MEMORY: i32 = 7;
struct Options { timeout_ms: i64 = 8000, max_bytes: i64 = 2097152, cancel: lab_io_cancel::Token = lab_io_cancel::Token {} }
struct Result { code: i32, exit_code: i64, out: u8[] = [], err: u8[] = [] }
extern "glab_goose_process_run" fn run_raw(program: const u8[:], cwd: const u8[:], argv: const u8[:],
    timeout: i64, limit: i64, cancel: u64, out: u8[>..]&, err: u8[>..]&, exit_code: i64&) -> i32;
fn valid(value: const u8[:]) -> bool { if !lab_text_utf8::valid(value) { return false; } for c in value { if c == 0 { return false; } } true }
fn run(program: const u8[:], arguments: const u8[:][:], cwd: const u8[:] = "", options: Options = Options {}) -> Result {
    var result = Result { code: INVALID, exit_code: -1 };
    if !valid(program) || !valid(cwd) || arguments.len > 64 { return result; }
    var argv: u8[>..] = [];
    for argument in arguments {
        if !valid(argument) || argument.len + 1 > 32768 - argv.len { return result; }
        argv.append(argument); argv.push(0);
    }
    var out: u8[>..] = []; var err: u8[>..] = []; var exit_code: i64 = -1;
    let code = run_raw(program, cwd, argv, options.timeout_ms, options.max_bytes, options.cancel.id, out, err, exit_code);
    Result { code, exit_code, out, err }
}
fn message(code: i32) -> const u8[:] {
    match code { 0 => "Process finished", 1 => "Invalid process arguments", 2 => "Unable to start process",
        3 => "Unable to capture process output", 4 => "Process output exceeds the limit",
        5 => "Process timed out", 6 => "Process cancelled", _ => "Unable to allocate process resources" }
}
