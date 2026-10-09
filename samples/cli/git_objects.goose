// One child, successive request/response exchanges, explicit stdin EOF.
import std;
import os;
import lab.io.process_stream;
import lab.io.process;
import lab.io.event_loop;
import lab.git.batch;
import lab.json.codec;
import lab.text.strings;
import lab.io.console;
extern "exit" fn finish(code: i32);
fn fail(context: lab_io_event_loop::Context&, message: const u8[:]) { write_stderr(str(message, "\n")); lab_io_event_loop::close(context); finish(1); }
fn request(context: lab_io_event_loop::Context&, child: const lab_io_process_stream::Handle&, name: const u8[:]) {
    var bytes: u8[>..] = []; bytes.append(name); bytes.push(0);
    let code = lab_io_process_stream::send(child, bytes); if code != 0 { fail(context, lab_io_event_loop::message(code)); }
}
fn main() {
    if !lab_io_console::binary_output() { write_stderr("Unable to configure byte output\n"); finish(1); }
    let argv = args();
    if argv.len < 3 || argv.len > 66 { write_stderr("Usage: git_objects REPOSITORY OBJECT [OBJECT ...] (up to 64)\n"); finish(2); }
    for i in argv.len - 2 {
        if argv[i + 2].len < 1 || argv[i + 2].len > 4096 || !lab_io_process::valid(argv[i + 2]) { write_stderr("Object names require 1..4096 UTF-8 bytes without NUL\n"); finish(2); }
    }
    var context = lab_io_event_loop::create(); if context.code != 0 { fail(context, lab_io_event_loop::message(context.code)); }
    let arguments: const u8[:][4] = ["--no-pager", "cat-file", "--batch", "-Z"];
    let child = lab_io_process_stream::start(context, "git", arguments, argv[1], lab_io_process_stream::Options { stdin: true });
    if child.code != 0 { fail(context, lab_io_event_loop::message(child.code)); }
    var decoder = lab_git_batch::Decoder {}; var at: i64 = 2; var missing = false;
    request(context, child, argv[at]);
    loop {
        let driven = lab_io_event_loop::wait(context, 50); if driven != 0 { fail(context, lab_io_event_loop::message(driven)); }
        let batch = lab_io_process_stream::poll(child); if batch.code != 0 { fail(context, lab_io_event_loop::message(batch.code)); }
        for chunk in batch.chunks {
            if chunk.stream == lab_io_process_stream::STDERR { write_stderr(chunk.bytes); }
            else if !lab_git_batch::append(decoder, chunk.bytes) { fail(context, lab_git_batch::message(decoder.code)); }
        }
        loop {
            let object = lab_git_batch::next(decoder); if object.code != 0 { fail(context, lab_git_batch::message(object.code)); }
            if !object.ready { break; }
            if at >= argv.len { fail(context, "Unexpected extra Git response"); }
            var writer = lab_json_codec::Writer {};
            lab_json_codec::begin_object(writer);
            lab_json_codec::key(writer, "request"); lab_json_codec::write_string(writer, argv[at]);
            lab_json_codec::key(writer, "status"); lab_json_codec::write_string(writer, lab_git_batch::status_name(object.status));
            lab_json_codec::key(writer, "name"); lab_json_codec::write_string(writer, object.name);
            lab_json_codec::key(writer, "type"); lab_json_codec::write_string(writer, object.kind);
            lab_json_codec::key(writer, "size"); lab_json_codec::write_integer(writer, object.size);
            lab_json_codec::key(writer, "preview"); lab_json_codec::write_string(writer, lab_text_strings::display_bytes(object.bytes, 256));
            lab_json_codec::end(writer); let line, ok = lab_json_codec::finish(writer); if !ok { fail(context, "Unable to encode Git response"); }
            write_stdout(str(line, "\n")); flush_stdout(); missing = missing || object.status != lab_git_batch::FOUND;
            at++;
            if at < argv.len { request(context, child, argv[at]); }
            else { let eof = lab_io_process_stream::eof(child); if eof != 0 { fail(context, lab_io_event_loop::message(eof)); } }
        }
        if batch.done {
            if batch.result != 0 { fail(context, lab_io_process::message(batch.result)); }
            if batch.exit_code != 0 { fail(context, "Git command failed"); }
            let code = lab_git_batch::finish(decoder); if code != 0 { fail(context, lab_git_batch::message(code)); }
            if at != argv.len { fail(context, "Git ended before all responses"); }
            if batch.input.result != 0 || batch.input.sent != batch.input.accepted { fail(context, "Git input was not completely written"); }
            break;
        }
    }
    lab_io_event_loop::close(context); finish(if missing { 1 } else { 0 });
}
