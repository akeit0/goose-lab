// A real CLI consumer before introducing UI policy.
import std;
import os;
import lab.io.event_loop;
import lab.io.timer;
import lab.fs.watch;
import lab.io.process;
import lab.io.process_stream;
import lab.io.console;
extern "exit" fn finish(code: i32);
fn main() {
    if !lab_io_console::binary_output() { write_stderr("Unable to configure byte output\n"); finish(1); }
    let argv = args(); var at: i64 = 1; var cancel_after: i64 = -1; var watch_path: u8[..2048] = [];
    var options = lab_io_process_stream::Options {};
    while at < argv.len {
        if argv[at] == "--" { at++; break; }
        if at + 1 < argv.len && argv[at] == "--watch" {
            if argv[at + 1].len == 0 || argv[at + 1].len > 2048 { write_stderr("Invalid watch path\n"); finish(2); }
            watch_path = argv[at + 1]; at += 2;
        }
        else if at + 1 < argv.len && (argv[at] == "--timeout" || argv[at] == "--max-bytes" || argv[at] == "--cancel-after") {
            let value, ok = parse_int(argv[at + 1]); if !ok { write_stderr("Invalid numeric option\n"); finish(2); }
            if argv[at] == "--timeout" { options.timeout_ms = value; }
            else if argv[at] == "--max-bytes" { options.max_bytes = value; }
            else {
                if value < 0 || value > 86400000 { write_stderr("Cancellation delay must be 0..86400000 ms\n"); finish(2); }
                cancel_after = value;
            }
            at += 2;
        } else { break; }
    }
    if at == argv.len { write_stderr("Usage: io_runner [--timeout MS] [--max-bytes N] [--cancel-after MS] [--watch DIR] -- PROGRAM [ARGS...]\n"); finish(2); }
    if options.timeout_ms < 1 || options.timeout_ms > 60000 || options.max_bytes < 1 || options.max_bytes > 2097152 {
        write_stderr("Timeout must be 1..60000 ms; capture budget must be 1..2097152 bytes\n"); finish(2);
    }
    if argv.len - at - 1 > 64 { write_stderr("At most 64 arguments are supported\n"); finish(2); }
    var arguments: const u8[:][..64] = []; for i in argv.len - at - 1 { arguments.push(argv[at + 1 + i]); }
    var context = lab_io_event_loop::create(); if context.code != 0 { write_stderr(str(lab_io_event_loop::message(context.code), "\n")); finish(1); }
    var process = lab_io_process_stream::start(context, argv[at], arguments, "", options);
    if process.code != 0 { write_stderr(str(lab_io_event_loop::message(process.code), "\n")); lab_io_event_loop::close(context); finish(1); }
    var heartbeat = lab_io_timer::start(context, 1000, 1000); var cancellation = lab_io_timer::Handle {}; var watch = lab_fs_watch::Handle {};
    if cancel_after >= 0 { cancellation = lab_io_timer::start(context, cancel_after); }
    if watch_path.len > 0 { watch = lab_fs_watch::on(context, watch_path); }
    if heartbeat.code != 0 || cancellation.code != 0 || watch.code != 0 {
        let code = if heartbeat.code != 0 { heartbeat.code } else if cancellation.code != 0 { cancellation.code } else { watch.code };
        write_stderr(str(lab_io_event_loop::message(code), "\n")); lab_io_event_loop::close(context); finish(1);
    }
    var outcome: i32 = -1; var exit_code: i64 = -1;
    loop {
        let code = lab_io_event_loop::wait(context, 100);
        if code != 0 { write_stderr(str(lab_io_event_loop::message(code), "\n")); lab_io_event_loop::close(context); finish(1); }
        let batch = lab_io_process_stream::poll(process);
        if batch.code != 0 { write_stderr(str(lab_io_event_loop::message(batch.code), "\n")); lab_io_event_loop::close(context); finish(1); }
        for chunk in batch.chunks {
            if chunk.stream == lab_io_process_stream::STDOUT { write_stdout(chunk.bytes); flush_stdout(); }
            else { write_stderr(chunk.bytes); }
        }
        if batch.done { outcome = batch.result; exit_code = batch.exit_code; break; }
        let beat = lab_io_timer::poll(heartbeat); assert(beat.code == 0); if beat.count > 0 { write_stderr("[runner] running\n"); }
        if cancellation.id != 0 {
            let fired = lab_io_timer::poll(cancellation); assert(fired.code == 0);
            if fired.count > 0 { assert(lab_io_process_stream::cancel(process) == 0); lab_io_timer::close(cancellation); }
        }
        if watch.id != 0 {
            let changes = lab_fs_watch::poll(watch);
            if changes.code != 0 { write_stderr(str(lab_fs_watch::message(changes.code), "\n")); lab_io_event_loop::close(context); finish(1); }
            if changes.rescan { write_stderr("[watch] rescan required\n"); }
            for event in changes.events { write_stderr(str("[watch] ", event.path, "\n")); }
        }
    }
    // Closing the owner also cleans up every remaining child resource.
    lab_io_event_loop::close(context);
    write_stderr(str("\n[runner] ", lab_io_process::message(outcome), " · exit=", exit_code, "\n"));
    finish(if outcome != lab_io_process::OK { 1 } else if exit_code < 0 || exit_code > 255 { 1 } else { exit_code as i32 });
}
