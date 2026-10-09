// Bounded worker-side batch read. The loop and all native children stay here.
namespace lab_git_object;
import std;
import lab.git.repository;
import lab.git.batch;
import lab.io.process;
import lab.io.process_stream;
import lab.io.event_loop;
import lab.io.cancel;
struct Result { code: i32 = lab_git_repository::OK, error: u8[..512] = [], object: lab_git_batch::Object = lab_git_batch::Object {} }
fn read(repo: const u8[:], name: const u8[:], options: lab_io_process::Options = lab_io_process::Options {}) -> Result {
    if name.len < 1 || name.len > 4096 || !lab_io_process::valid(name) { return Result { code: lab_git_repository::INVALID, error: "Invalid Git object name" }; }
    if lab_io_cancel::requested(options.cancel) { return Result { code: lab_git_repository::COMMAND, error: "Process cancelled" }; }
    var context = lab_io_event_loop::create();
    if context.code != 0 { return Result { code: lab_git_repository::COMMAND, error: lab_io_event_loop::message(context.code) }; }
    let result = read_in(context, repo, name, options);
    lab_io_event_loop::close(context); result
}
fn read_in(context: const lab_io_event_loop::Context&, repo: const u8[:], name: const u8[:], options: lab_io_process::Options) -> Result {
    let argv: const u8[:][5] = ["--no-replace-objects", "--no-pager", "cat-file", "--batch", "-Z"];
    let child = lab_io_process_stream::start(context, "git", argv, repo, lab_io_process_stream::Options { stdin: true, timeout_ms: options.timeout_ms, max_bytes: options.max_bytes });
    if child.code != 0 { return Result { code: lab_git_repository::COMMAND, error: lab_io_event_loop::message(child.code) }; }
    var request: u8[>..] = []; request.append(name); request.push(0);
    let sent = lab_io_process_stream::send(child, request);
    if sent != 0 { return Result { code: lab_git_repository::COMMAND, error: lab_io_event_loop::message(sent) }; }
    let eof = lab_io_process_stream::eof(child);
    if eof != 0 { return Result { code: lab_git_repository::COMMAND, error: lab_io_event_loop::message(eof) }; }
    var decoder = lab_git_batch::Decoder {}; var received = false;
    var status: i32 = 0; var object_name: u8[..8192] = []; var kind: u8[..8] = []; var size: i64 = 0; var body: u8[>..] = [];
    loop {
        if lab_io_cancel::requested(options.cancel) { lab_io_process_stream::cancel(child); }
        let driven = lab_io_event_loop::wait(context, 20);
        if driven != 0 { return Result { code: lab_git_repository::COMMAND, error: lab_io_event_loop::message(driven) }; }
        let batch = lab_io_process_stream::poll(child);
        if batch.code != 0 { return Result { code: lab_git_repository::COMMAND, error: lab_io_event_loop::message(batch.code) }; }
        for chunk in batch.chunks {
            if chunk.stream == lab_io_process_stream::STDOUT && !lab_git_batch::append(decoder, chunk.bytes) {
                return Result { code: lab_git_repository::INVALID, error: lab_git_batch::message(decoder.code) };
            }
        }
        loop {
            let next = lab_git_batch::next(decoder);
            if next.code != 0 { return Result { code: lab_git_repository::INVALID, error: lab_git_batch::message(next.code) }; }
            if !next.ready { break; }
            if received { return Result { code: lab_git_repository::INVALID, error: "Unexpected extra Git object" }; }
            status = next.status; object_name = next.name; kind = next.kind; size = next.size; body.append(next.bytes); received = true;
        }
        if batch.done {
            if batch.result != 0 { return Result { code: lab_git_repository::COMMAND, error: lab_io_process::message(batch.result) }; }
            if batch.exit_code != 0 { return Result { code: lab_git_repository::COMMAND, error: "Git object command failed" }; }
            if lab_git_batch::finish(decoder) != 0 || !received { return Result { code: lab_git_repository::INVALID, error: "Incomplete Git object response" }; }
            if batch.input.result != 0 || batch.input.sent != batch.input.accepted { return Result { code: lab_git_repository::COMMAND, error: "Incomplete Git object request" }; }
            return Result { object: lab_git_batch::Object { ready: true, status: status, name: object_name, kind: kind, size: size, bytes: body } };
        }
    }
}
