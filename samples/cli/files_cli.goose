// A GUI-free consumer of asynchronous, bounded filesystem jobs.
import std;
import os;
import lab.io.event_loop;
import lab.fs.async_files;
import lab.io.timer;
import lab.io.console;
import lab.text.strings;
extern "exit" fn finish(code: i32);
fn fail(context: lab_io_event_loop::Context&, code: i32) {
    write_stderr(str(lab_io_event_loop::message(code), "\n")); lab_io_event_loop::close(context); finish(1);
}
fn main() {
    if !lab_io_console::binary_output() { write_stderr("Unable to configure byte output\n"); finish(1); }
    let argv = args(); var at: i64 = 1; var limit: i64 = -1; var cancel_after: i64 = -1;
    while at + 1 < argv.len && (argv[at] == "--limit" || argv[at] == "--cancel-after") {
        let value, ok = parse_int(argv[at + 1]);
        if !ok || value < 0 { write_stderr("Options require nonnegative integers\n"); finish(2); }
        if argv[at] == "--limit" { limit = value; } else { cancel_after = value; }
        at += 2;
    }
    let copying = at < argv.len && argv[at] == "copy";
    if argv.len - at != (if copying { 3 } else { 2 }) || (argv[at] != "read" && argv[at] != "list" && !copying) {
        write_stderr("Usage: files_cli [--limit N] [--cancel-after MS] read|list PATH\n       files_cli [--limit N] [--cancel-after MS] copy SOURCE DESTINATION\n"); finish(2);
    }
    let reading = argv[at] == "read" || copying;
    if limit < 0 { limit = if reading { 2097152 } else { 4096 }; }
    if limit > (if reading { 2097152 } else { 4096 }) || cancel_after > 86400000 {
        write_stderr("Limit exceeds the supported range\n"); finish(2);
    }
    var context = lab_io_event_loop::create(); if context.code != 0 { fail(context, context.code); }
    var file = lab_fs_async_files::Read {}; var directory = lab_fs_async_files::Listing {}; var writing = lab_fs_async_files::Write {};
    if reading { file = lab_fs_async_files::read(context, argv[at + 1], limit); if file.code != 0 { fail(context, file.code); } }
    else { directory = lab_fs_async_files::list(context, argv[at + 1], limit); if directory.code != 0 { fail(context, directory.code); } }
    var cancellation = lab_io_timer::Handle {};
    if cancel_after >= 0 { cancellation = lab_io_timer::start(context, cancel_after); if cancellation.code != 0 { fail(context, cancellation.code); } }
    var result: i32 = -1; var cancelled_requested = false;
    loop {
        let code = lab_io_event_loop::wait(context, 50); if code != 0 { fail(context, code); }
        if cancellation.id != 0 {
            let fired = lab_io_timer::poll(cancellation); if fired.code != 0 { fail(context, fired.code); }
            if fired.count > 0 {
                cancelled_requested = true;
                let cancelled = if writing.id != 0 { lab_fs_async_files::cancel(writing) }
                    else if reading { lab_fs_async_files::cancel(file) } else { lab_fs_async_files::cancel(directory) };
                if cancelled != 0 { fail(context, cancelled); } lab_io_timer::close(cancellation);
            }
        }
        if writing.id != 0 {
            let saved = lab_fs_async_files::poll(writing); if saved.code != 0 { fail(context, saved.code); }
            if saved.done {
                result = saved.result;
                if saved.cleanup_code != 0 {
                    write_stderr(str("Temporary cleanup: ", lab_io_event_loop::message(saved.cleanup_code), "\n"));
                    if saved.temporary.len > 0 { write_stderr(str("Temporary remains: ", lab_text_strings::display_bytes(saved.temporary, 196608), "\n")); }
                }
                if saved.committed { write_stderr(str("Saved ", saved.size, " bytes · data synced=", saved.synced, "\n")); }
                break;
            }
        } else if reading {
            let contents = lab_fs_async_files::poll(file); if contents.code != 0 { fail(context, contents.code); }
            if contents.done {
                result = contents.result;
                if copying && cancelled_requested { result = lab_io_event_loop::CANCELLED; break; }
                if copying && result == 0 {
                    writing = lab_fs_async_files::replace(context, argv[at + 2], contents.bytes);
                    if writing.code != 0 { fail(context, writing.code); } lab_fs_async_files::close(file);
                } else { if result == 0 { write_stdout(contents.bytes); flush_stdout(); } break; }
            }
        } else {
            let page = lab_fs_async_files::poll(directory); if page.code != 0 { fail(context, page.code); }
            for entry in page.entries { write_stdout(str(lab_fs_async_files::kind_name(entry.kind), "\t", lab_text_strings::display_bytes(entry.name), "\n")); }
            flush_stdout(); if page.done { result = page.result; break; }
        }
    }
    lab_io_event_loop::close(context);
    if result != 0 { write_stderr(str(lab_io_event_loop::message(result), "\n")); finish(1); }
    finish(0);
}
