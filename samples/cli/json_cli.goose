// Async configuration editing. JSON/domain decisions stay in Goose.
import std;
import os;
import lab.json.codec;
import lab.json.edit;
import lab.fs.async_files;
import lab.io.event_loop;
import lab.io.timer;
import lab.io.console;
import lab.text.strings;
extern "exit" fn finish(code: i32);
fn fail(context: lab_io_event_loop::Context&, message: const u8[:]) {
    write_stderr(str(message, "\n")); lab_io_event_loop::close(context); finish(1);
}
fn main() {
    if !lab_io_console::binary_output() { write_stderr("Unable to configure byte output\n"); finish(1); }
    let argv = args(); var at: i64 = 1; var limit: i64 = 1048576; var cancel_after: i64 = -1;
    while at + 1 < argv.len && (argv[at] == "--limit" || argv[at] == "--cancel-after") {
        let n, ok = parse_int(argv[at + 1]);
        if !ok || n < 0 { write_stderr("Options require nonnegative integers\n"); finish(2); }
        if argv[at] == "--limit" { limit = n; } else { cancel_after = n; } at += 2;
    }
    let setting = at < argv.len && argv[at] == "set";
    if argv.len - at != (if setting { 4 } else { 3 }) || (!setting && argv[at] != "get") || limit < 1 || limit > 2097152 || cancel_after > 86400000 {
        write_stderr("Usage: json_cli [--limit BYTES] [--cancel-after MS] get PATH KEY\n       json_cli [options] set PATH KEY JSON\n"); finish(2);
    }
    let path = argv[at + 1]; let key = argv[at + 2];
    var context = lab_io_event_loop::create(); if context.code != 0 { fail(context, lab_io_event_loop::message(context.code)); }
    var reading = lab_fs_async_files::read(context, path, limit); if reading.code != 0 { fail(context, lab_io_event_loop::message(reading.code)); }
    var cancellation = lab_io_timer::Handle {};
    if cancel_after >= 0 { cancellation = lab_io_timer::start(context, cancel_after); if cancellation.code != 0 { fail(context, lab_io_event_loop::message(cancellation.code)); } }
    var writing = lab_fs_async_files::Write {}; var checking = lab_fs_async_files::Read {};
    var original: u8[>..] = []; var cancelled = false; var publishing = false;
    loop {
        let driven = lab_io_event_loop::wait(context, 50); if driven != 0 { fail(context, lab_io_event_loop::message(driven)); }
        if cancellation.id != 0 {
            let fired = lab_io_timer::poll(cancellation); if fired.code != 0 { fail(context, lab_io_event_loop::message(fired.code)); }
            if fired.count > 0 {
                cancelled = true;
                if writing.id != 0 { lab_fs_async_files::cancel(writing); }
                if checking.id != 0 { lab_fs_async_files::cancel(checking); }
                if reading.id != 0 { lab_fs_async_files::cancel(reading); }
                lab_io_timer::close(cancellation);
            }
        }
        if reading.id != 0 {
            let loaded = lab_fs_async_files::poll(reading); if loaded.code != 0 { fail(context, lab_io_event_loop::message(loaded.code)); }
            if !loaded.done { continue; }
            if cancelled { fail(context, lab_io_event_loop::message(lab_io_event_loop::CANCELLED)); }
            if loaded.result != 0 { fail(context, lab_io_event_loop::message(loaded.result)); }
            if !setting {
                let doc = lab_json_codec::parse(loaded.bytes, lab_json_codec::Limits { bytes: limit });
                if doc.error.code != 0 { fail(context, str(lab_json_codec::message(doc.error), " at byte ", doc.error.offset)); }
                let selected = lab_json_edit::find(doc, key);
                if selected.code != 0 { fail(context, lab_json_edit::message(selected.code)); }
                if selected.index < 0 { fail(context, "Setting key is missing"); }
                write_stdout(str(lab_json_codec::raw(lab_json_codec::Value { doc, selected.index }), "\n")); flush_stdout(); break;
            }
            let edited = lab_json_edit::set(loaded.bytes, key, argv[at + 3], lab_json_codec::Limits { bytes: limit });
            if edited.code != 0 {
                if edited.error.code != 0 { fail(context, str(lab_json_edit::message(edited.code), " at byte ", edited.error.offset)); }
                fail(context, lab_json_edit::message(edited.code));
            }
            if !edited.changed { write_stderr("Unchanged\n"); break; }
            original.append(loaded.bytes);
            writing = lab_fs_async_files::prepare(context, path, edited.bytes);
            if writing.code != 0 { fail(context, lab_io_event_loop::message(writing.code)); } lab_fs_async_files::close(reading);
        }
        if writing.id != 0 {
            let saved = lab_fs_async_files::poll(writing); if saved.code != 0 { fail(context, lab_io_event_loop::message(saved.code)); }
            if saved.done {
                if saved.cleanup_code != 0 {
                    write_stderr(str("Temporary cleanup failed: ", lab_io_event_loop::message(saved.cleanup_code), "\n"));
                    if saved.temporary.len > 0 { write_stderr(str("Temporary remains: ", lab_text_strings::display_bytes(saved.temporary, 196608), "\n")); }
                }
                if saved.result != 0 { fail(context, lab_io_event_loop::message(saved.result)); }
                write_stderr(str("Saved ", saved.size, " bytes · data synced=", saved.synced, "\n")); break;
            }
            if saved.ready && checking.id == 0 && !publishing {
                checking = lab_fs_async_files::read(context, path, limit);
                if checking.code != 0 { fail(context, lab_io_event_loop::message(checking.code)); }
            }
        }
        if checking.id != 0 {
            let current = lab_fs_async_files::poll(checking); if current.code != 0 { fail(context, lab_io_event_loop::message(current.code)); }
            if !current.done { continue; }
            if current.result != 0 { fail(context, lab_io_event_loop::message(current.result)); }
            if current.bytes != original { fail(context, "File changed while editing; save cancelled"); }
            let committed = lab_fs_async_files::commit(writing); if committed != 0 { fail(context, lab_io_event_loop::message(committed)); }
            publishing = true; lab_fs_async_files::close(checking);
        }
    }
    lab_io_event_loop::close(context); finish(0);
}
