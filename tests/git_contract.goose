import std;
import os;
import lab.io.cancel;
import lab.io.process;
import lab.json.codec;
import lab.git.repository;
import lab.git.history;
import lab.git.object;
import lab.text.diff;
import lab.text.line_index;
import lab.fs.files;
import lab.git.tree;
import lab.fs.watch;
import lab.io.event_loop;
import lab.io.timer;
import lab.io.process_stream;
import lab.fs.async_files;
import lab.fs.search;
import lab.document.model;
import lab.document.file;
struct Probe { token: lab_io_cancel::Token, program: u8[], helper: u8[], repo: u8[] }
struct Finished { code: i32 }
thread_fn delayed() {
    let probe = qget<Probe>();
    let arguments: const u8[:][2] = [probe.helper[..], "sleep"];
    let result = lab_io_process::run(probe.program, arguments, probe.repo, lab_io_process::Options { cancel: probe.token });
    qput(Finished { result.code });
}
fn main() {
    let argv = args(); assert(argv.len == 5); document_file_contract(argv[4]); file_search_contract(str(argv[4], "/search")); history_parser_contract(argv[1]); duplex_contract(argv[1], argv[2], argv[3]); write_jobs_contract(argv[4]); file_jobs_contract(argv[4]); io_contract(argv[1], argv[2], argv[3]); watch_contract(argv[1]);
    var controls = lab_git_repository::Files {}; controls.items.push(lab_git_repository::File { path: [97, 0xC2, 0x85, 98], status: 'M' });
    let control_tree = lab_git_tree::build(controls); assert(control_tree.code == 0 && control_tree.nodes[0].label == "a\\u0085b");
    let lines, good = lab_text_line_index::build("a\r\n\n日本語\nlast"); assert(good && lines.rows.len == 4);
    assert(lab_text_line_index::line(lines, "a\r\n\n日本語\nlast", 1) == "");
    assert(lab_text_line_index::row_at(lines, 2) == 0 && lab_text_line_index::row_at(lines, 3) == 1 && lab_text_line_index::row_at(lines, 100) == -1);
    let empty, empty_ok = lab_text_line_index::build(""); assert(empty_ok && empty.rows.len == 0);
    let limited, limit_ok = lab_text_line_index::build("a\nb\n", 1); assert(!limit_ok && limited.rows.len == 0);
    let patch = lab_text_diff::decode("diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1,2 +1,2 @@\n a\n-old\n+new\n\\ No newline at end of file\n");
    assert(patch.code == 0 && patch.added == 1 && patch.removed == 1 && patch.hunks.len == 1);
    assert(patch.rows[4].old == 1 && patch.rows[4].new == 1 && patch.rows[5].old == 2 && patch.rows[6].new == 2);
    assert(lab_text_diff::decode("@@ -1,2 +1 @@\n-x\n+y\n").code == lab_text_diff::INVALID);
    let addition = lab_text_diff::decode("@@ -0,0 +1,2 @@\n+++literal\n+\n"); assert(addition.code == 0 && addition.added == 2 && addition.rows[1].kind == lab_text_diff::ADD);
    let deletion = lab_text_diff::decode("@@ -1 +0,0 @@\n-x\n"); assert(deletion.code == 0 && deletion.removed == 1);
    assert(lab_text_diff::decode("Binary files a/image.bin and b/image.bin differ\n").binary);
    assert(lab_text_diff::decode("diff --cc conflicted.txt\n@@@ -1 -1 +1 @@@\n").code == lab_text_diff::UNSUPPORTED);
    var nul: u8[>..] = []; nul.append("M"); nul.push(0); nul.append("日本語 [1].txt"); nul.push(0);
    let paths = lab_git_repository::parse_files(nul); assert(paths.code == 0 && paths.items.len == 1 && paths.items[0].path == "日本語 [1].txt");
    nul.resize(nul.len - 1); assert(lab_git_repository::parse_files(nul).code == lab_git_repository::INVALID);
    var others: u8[>..] = []; others.append("nested/new [日本語].txt"); others.push(0);
    let untracked_paths = lab_git_repository::parse_untracked(others); assert(untracked_paths.code == 0 && untracked_paths.items[0].status == '?');
    others.resize(others.len - 1); assert(lab_git_repository::parse_untracked(others).code == lab_git_repository::INVALID);
    var too_many: u8[>..] = []; for i in 513 { too_many.append(str("file-", i)); too_many.push(0); }
    assert(lab_git_repository::parse_untracked(too_many).code == lab_git_repository::LIMIT);
    let full = lab_git_repository::parse_untracked(too_many[..too_many.len - 9]);
    assert(full.code == 0 && full.items.len == 512 && lab_git_repository::merge_files(paths, full).code == lab_git_repository::LIMIT);
    let echo_args: const u8[:][6] = [argv[3], "echo", "", "space and 日本語", "quote\"end\\", "& $ ` literal"];
    let result = lab_io_process::run(argv[2], echo_args, argv[1]);
    assert(result.code == lab_io_process::OK && result.exit_code == 0);
    let doc = lab_json_codec::parse(result.out); assert(doc.error.code == 0); let root = lab_json_codec::root(doc);
    let empty_arg, a = lab_json_codec::text(lab_json_codec::at(root, 0)); let spaced, b = lab_json_codec::text(lab_json_codec::at(root, 1));
    let quoted, c = lab_json_codec::text(lab_json_codec::at(root, 2)); let shell, d = lab_json_codec::text(lab_json_codec::at(root, 3));
    assert(a && b && c && d && empty_arg == "" && spaced == "space and 日本語" && quoted == "quote\"end\\" && shell == "& $ ` literal");
    let exit_args: const u8[:][2] = [argv[3], "exit"];
    let exit = lab_io_process::run(argv[2], exit_args, argv[1]); assert(exit.code == 0 && exit.exit_code == 42 && exit.err == "intentional failure");
    let sleep_args: const u8[:][2] = [argv[3], "sleep"];
    let timeout = lab_io_process::run(argv[2], sleep_args, argv[1], lab_io_process::Options { timeout_ms: 150 }); assert(timeout.code == lab_io_process::TIMEOUT);
    let flood_args: const u8[:][2] = [argv[3], "flood"];
    let flood = lab_io_process::run(argv[2], flood_args, argv[1], lab_io_process::Options { max_bytes: 1024 }); assert(flood.code == lab_io_process::LIMIT);
    var token = lab_io_cancel::create(); assert(token.id != 0); let worker = thread_spawn(delayed);
    qput(Probe { token, argv[2], argv[3], argv[1] }); sleep_ms(100); let at = clock_ns(); assert(lab_io_cancel::request(token));
    let cancelled = qget<Finished>(); thread_wait(worker); assert(cancelled.code == lab_io_process::CANCELLED && clock_ns() - at < 2000000000); lab_io_cancel::destroy(token);
    let missing = lab_io_process::run("goose-no-such-program-812437", [], argv[1]); assert(missing.code == lab_io_process::SPAWN);
    let orphan = str(argv[1], "/orphan.txt"); let tree_args: const u8[:][3] = [argv[3], "tree", orphan[..]];
    let tree = lab_io_process::run(argv[2], tree_args, argv[1]); assert(tree.code == lab_io_process::OK && tree.exit_code == 0);
    sleep_ms(1500); assert(!file_exists(orphan));
    let root = lab_git_repository::root(argv[1]); assert(root.code == 0);
    let nested = lab_git_repository::root(str(argv[1], "/nested")); assert(nested.code == 0 && nested.path == root.path);
    let files = lab_git_repository::files(argv[1], false); assert(files.code == 0 && files.items.len == 25);
    assert(files.items[lab_git_repository::index(files, "untracked.txt")].status == '?');
    assert(lab_git_repository::index(files, "ignored.tmp") == -1 && lab_git_repository::index(files, "ignored/content.txt") == -1);
    assert(lab_git_repository::index(files, "info-excluded.txt") == -1 && lab_git_repository::index(files, "global-excluded.txt") == -1);
    let staged_files = lab_git_repository::files(argv[1], true); assert(staged_files.code == 0 && staged_files.items.len == 1 && lab_git_repository::index(staged_files, "untracked.txt") == -1);
    let diff = lab_git_repository::diff(argv[1], "literal[1].txt", false); assert(diff.code == 0 && diff.patch.added == 2 && diff.patch.removed == 1);
    let staged = lab_git_repository::diff(argv[1], "staged.txt", true); assert(staged.code == 0 && staged.patch.added == 1);
    assert(lab_git_repository::diff(argv[1], "binary.bin", false).patch.binary);
    let new_file = lab_git_repository::untracked(argv[1], "untracked.txt"); assert(new_file.code == 0 && new_file.untracked && new_file.patch.added == 2 && new_file.patch.removed == 0);
    assert(ends_with(new_file.patch.source, "\\ No newline at end of file\n") && starts_with(new_file.patch.source, "diff --git a/untracked.txt b/untracked.txt\n"));
    assert(lab_git_repository::untracked(argv[1], "nested/new [日本語].txt").patch.added == 1);
    assert(lab_git_repository::untracked(argv[1], "-new[1].txt").patch.added == 1);
    let new_binary = lab_git_repository::untracked(argv[1], "newbinary.bin"); assert(new_binary.code == 0 && new_binary.patch.binary && new_binary.bytes == 4);
    let new_empty = lab_git_repository::untracked(argv[1], "empty.txt"); assert(new_empty.code == 0 && new_empty.bytes == 0 && new_empty.patch.added == 0 && new_empty.patch.source.len > 0);
    assert(lab_git_repository::untracked(argv[1], "oversized.txt").code == lab_git_repository::LIMIT);
    assert(lab_git_repository::untracked(argv[1], "invalid-encoding.txt").code == lab_git_repository::INVALID);
    assert(lab_git_repository::untracked(argv[1], "absent.txt").code == lab_git_repository::INVALID);
    assert(lab_git_repository::untracked(argv[1], "../outside.txt").code == lab_git_repository::INVALID);
    assert(lab_fs_files::info(argv[1]).code == lab_fs_files::NOT_REGULAR && lab_fs_files::info("").code == lab_fs_files::INVALID_PATH);
    assert(lab_git_repository::files(str(argv[1], "/absent"), false).code == lab_git_repository::COMMAND);
    print("Git/process contract: literal argv, bounded capture, timeout, live cancellation, NUL paths, exact hunk counts and working/staged diffs passed");
}
fn history_parser_contract(repo: const u8[:]) {
    let id: const u8[:] = "0123456789012345678901234567890123456789";
    assert(lab_git_history::oid(id) && !lab_git_history::oid("--help"));
    assert(lab_git_repository::display("日本語日本語", 12) == "日本語…");
    var bytes: u8[>..] = []; bytes.append(id); bytes.push(0); bytes.push(0);
    bytes.append("日本語 author"); bytes.push(0); bytes.append("2026-10-09T12:00:00+09:00"); bytes.push(0); bytes.append("subject\t日本語"); bytes.push(0);
    let parsed = lab_git_history::parse(bytes); assert(parsed.code == 0 && parsed.items.len == 1 && parsed.items[0].id == id && parsed.items[0].parents == 0);
    bytes.resize(bytes.len - 1); assert(lab_git_history::parse(bytes).code != 0); bytes.push(0);
    bytes.append(bytes[..]); assert(lab_git_history::parse(bytes).code != 0);
    assert(lab_git_history::parse("bad\0\0author\0date\0subject\0").code != 0);
    assert(lab_git_history::page(repo, "--help").code != 0 && lab_git_history::page(repo, id, -1).code != 0 && lab_git_history::page(repo, id, 0, 65).code != 0);
    let plain = lab_text_diff::plain("@@ ordinary\r\n+++ literal\nlast");
    assert(plain.code == 0 && plain.hunks.len == 0 && plain.rows.len == 3 && plain.rows[1].new == 2 && plain.rows[1].kind == lab_text_diff::HEADER);
    assert(plain.source == "@@ ordinary\r\n+++ literal\nlast" && lab_text_diff::plain("\0binary").binary);
    assert(lab_text_diff::plain([0xFF]).code == lab_text_diff::ENCODING);
    var token = lab_io_cancel::create(); lab_io_cancel::request(token);
    let cancelled = lab_git_object::read(repo, "HEAD", lab_io_process::Options { cancel: token });
    assert(cancelled.code != 0 && !cancelled.object.ready); lab_io_cancel::destroy(token);
}

struct WatchProbe { handle: lab_fs_watch::Handle }
struct WatchResult { code: i32, closed: bool }
thread_fn watch_other_thread() {
    var job = qget<WatchProbe>(); let batch = lab_fs_watch::poll(job.handle);
    qput(WatchResult { batch.code, lab_fs_watch::close(job.handle) });
}
fn watch_contract(repo: const u8[:]) {
    let invalid = lab_fs_watch::open([0xFF]); assert(invalid.code == lab_fs_watch::INVALID_PATH);
    let file = lab_fs_watch::open(str(repo, "/literal[1].txt")); assert(file.id == 0 && file.code == lab_fs_watch::NOT_DIRECTORY);
    let missing = lab_fs_watch::open(str(repo, "/absent")); assert(missing.id == 0 && missing.code == lab_fs_watch::MISSING);
    let dir = str(repo, "/watch 日本語 temporary"); assert(make_dir(dir));
    var watch = lab_fs_watch::open(dir); assert(watch.id != 0 && watch.code == lab_fs_watch::OK);
    let old = watch;
    let worker = thread_spawn(watch_other_thread); qput(WatchProbe { watch }); thread_wait(worker);
    let other = qget<WatchResult>(); assert(other.code == lab_fs_watch::WRONG_THREAD && !other.closed);
    let path = str(dir, "/日本語.txt"); assert(write_file_atomic(path, "one"));
    let until = clock_ns() + 3000000000; var saw = false;
    while !saw { assert(clock_ns() < until); let batch = lab_fs_watch::poll(watch); assert(batch.code == 0); for event in batch.events { saw = saw || event.path == "日本語.txt"; } saw = saw || batch.rescan; sleep_ms(1); }
    let first = lab_fs_files::revision(path); assert(first.code == lab_fs_files::OK && first.size == 3 && first.digest == lab_fs_files::digest("one"));
    assert(write_file_atomic(path, "two")); let second = lab_fs_files::revision(path); assert(second.size == first.size && second.digest != first.digest);
    assert(lab_fs_watch::close(watch) && !lab_fs_watch::close(watch));
    watch = lab_fs_watch::open(dir); assert(watch.id != old.id && lab_fs_watch::poll(old).code == lab_fs_watch::CLOSED);
    var stale = old; assert(!lab_fs_watch::close(stale));
    let clean = lab_fs_watch::poll(watch); assert(clean.code == 0 && !lab_fs_watch::changed(clean));
    for i in 100 { assert(write_file(str(dir, "/item-", i), "x")); }
    var notified = false; let burst_until = clock_ns() + 3000000000;
    while !notified { assert(clock_ns() < burst_until); let batch = lab_fs_watch::poll(watch); assert(batch.code == 0); notified = lab_fs_watch::changed(batch); if batch.rescan { assert(batch.events.len == 0); } sleep_ms(1); }
    // OS batching varies. Independently enforce the owned batch's loss contract.
    var packet: u8[>..] = []; for i in 65 { packet.push(1); packet.append(str("item-", i)); packet.push(0); }
    let overflow = lab_fs_watch::decode(packet); assert(overflow.rescan && overflow.overflow && overflow.events.len == 0);
    let invalid_name = lab_fs_watch::decode([1, 0xFF, 0]); assert(invalid_name.rescan && invalid_name.events.len == 0);
    assert(lab_fs_watch::close(watch));
    for i in 100 { assert(delete_file(str(dir, "/item-", i))); } assert(delete_file(path)); assert(delete_dir(dir));
    var handles: lab_fs_watch::Handle[..32] = []; for i in 32 { let handle = lab_fs_watch::open(repo); assert(handle.id != 0); handles.push(handle); }
    let full = lab_fs_watch::open(repo); assert(full.id == 0 && full.code == lab_fs_watch::LIMIT);
    for &handle in handles { assert(lab_fs_watch::close(handle)); }
}

struct LoopProbe { context: lab_io_event_loop::Context, timer: lab_io_timer::Handle, watch: lab_fs_watch::Handle, file: lab_fs_async_files::Read, directory: lab_fs_async_files::Listing, writing: lab_fs_async_files::Write }
struct LoopReady { value: bool }
struct LoopChecked { value: bool }
thread_fn loop_other_thread() {
    var probe = qget<LoopProbe>();
    assert(lab_io_event_loop::poll(probe.context) == lab_io_event_loop::WRONG_THREAD && !lab_io_event_loop::close(probe.context));
    assert(lab_io_timer::poll(probe.timer).code == lab_io_event_loop::WRONG_THREAD && !lab_io_timer::close(probe.timer));
    assert(lab_fs_watch::poll(probe.watch).code == lab_io_event_loop::WRONG_THREAD && !lab_fs_watch::close(probe.watch));
    assert(lab_fs_async_files::poll(probe.file).code == lab_io_event_loop::WRONG_THREAD && lab_fs_async_files::cancel(probe.file) == lab_io_event_loop::WRONG_THREAD && !lab_fs_async_files::close(probe.file));
    assert(lab_fs_async_files::poll(probe.directory).code == lab_io_event_loop::WRONG_THREAD && !lab_fs_async_files::close(probe.directory));
    assert(lab_fs_async_files::poll(probe.writing).code == lab_io_event_loop::WRONG_THREAD && lab_fs_async_files::commit(probe.writing) == lab_io_event_loop::WRONG_THREAD && !lab_fs_async_files::close(probe.writing));
    qput(LoopReady { true });
    var context = lab_io_event_loop::create(); var timer = lab_io_timer::start(context, 30); assert(context.code == 0 && timer.code == 0);
    let until = clock_ns() + 2000000000; var fired = false;
    while !fired { assert(clock_ns() < until); assert(lab_io_event_loop::wait(context, 50) == 0); fired = lab_io_timer::poll(timer).count > 0; }
    assert(lab_io_event_loop::close(context)); qput(LoopChecked { true });
}
fn stream_collect(context: const lab_io_event_loop::Context&, program: const u8[:], arguments: const u8[:][:], repo: const u8[:],
    options: lab_io_process_stream::Options = lab_io_process_stream::Options {}) -> lab_io_process::Result {
    var process = lab_io_process_stream::start(context, program, arguments, repo, options); assert(process.code == 0);
    var out: u8[>..] = []; var err: u8[>..] = []; var result: i32 = -1; var exit_code: i64 = -1;
    let until = clock_ns() + 10000000000;
    loop {
        assert(clock_ns() < until && lab_io_event_loop::wait(context, 20) == 0);
        let batch = lab_io_process_stream::poll(process); assert(batch.code == 0);
        for chunk in batch.chunks { if chunk.stream == lab_io_process_stream::STDOUT { out.append(chunk.bytes); } else { err.append(chunk.bytes); } }
        if batch.done { result = batch.result; exit_code = batch.exit_code; break; }
    }
    assert(lab_io_process_stream::close(process)); lab_io_process::Result { result, exit_code, out, err }
}
fn io_contract(repo: const u8[:], program: const u8[:], helper: const u8[:]) {
    var context = lab_io_event_loop::create(); assert(context.code == 0 && lab_io_event_loop::info(context).resources == 0);
    assert(lab_io_event_loop::wait(context, -1) == lab_io_event_loop::INVALID);
    var timer = lab_io_timer::start(context, 86400000); var watch = lab_fs_watch::on(context, repo); assert(timer.code == 0 && watch.code == 0);
    var file = lab_fs_async_files::read(context, str(repo, "/empty.txt")); var directory = lab_fs_async_files::list(context, repo);
    var writing = lab_fs_async_files::prepare(context, str(repo, "/missing-parent/io-not-published.txt"), "never committed");
    let worker = thread_spawn(loop_other_thread); qput(LoopProbe { context, timer, watch, file, directory, writing }); assert(qget<LoopReady>().value);
    assert(lab_fs_async_files::close(file) && lab_fs_async_files::close(directory) && lab_fs_async_files::close(writing)); assert(lab_io_event_loop::poll(context) == 0);
    // An unrelated owner can finish while this loop is waiting, rather than
    // being serialized behind a global registry lock.
    assert(lab_io_event_loop::wait(context, 250) == 0); let other, available = qpoll<LoopChecked>(); assert(available && other.value); thread_wait(worker);
    assert(lab_io_timer::restart(timer, 0) == 0 && lab_io_event_loop::poll(context) == 0 && lab_io_timer::poll(timer).count == 1);
    assert(lab_io_timer::poll(timer).count == 0 && lab_io_timer::stop(timer) == 0);
    sleep_ms(35); assert(lab_io_timer::restart(timer, 30) == 0 && lab_io_event_loop::poll(context) == 0 && lab_io_timer::poll(timer).count == 0);
    let until = clock_ns() + 1000000000; var fired = false;
    while !fired { assert(clock_ns() < until && lab_io_event_loop::wait(context, 50) == 0); fired = lab_io_timer::poll(timer).count == 1; }
    assert(lab_io_timer::close(timer) && lab_fs_watch::close(watch) && lab_io_event_loop::info(context).resources == 0);
    var timers: lab_io_timer::Handle[..64] = [];
    for i in 64 { let t = lab_io_timer::start(context, 86400000); assert(t.code == 0); timers.push(t); }
    assert(lab_io_timer::start(context, 1).code == lab_io_event_loop::LIMIT); for &t in timers { assert(lab_io_timer::close(t)); }
    var stale = timers[0]; var replacement = lab_io_timer::start(context, 0);
    assert(replacement.id != stale.id && lab_io_timer::poll(stale).code == lab_io_event_loop::CLOSED && !lab_io_timer::close(stale)); lab_io_timer::close(replacement);
    timer = lab_io_timer::start(context, 10, 10); watch = lab_fs_watch::on(context, repo);
    var source: u8[..2048] = helper; let stream_args: const u8[:][2] = [source[..], "stream"];
    var process = lab_io_process_stream::start(context, program, stream_args, repo); assert(process.code == 0);
    source = "changed after start"; // The native job must own the original argv bytes.
    let changed_path = str(repo, "/io-contract-temporary.txt"); assert(write_file_atomic(changed_path, "change"));
    var out: u8[>..] = []; var err: u8[>..] = []; var early = false; var ticks: i64 = 0; var saw_watch = false;
    let deadline = clock_ns() + 5000000000;
    loop {
        assert(clock_ns() < deadline && lab_io_event_loop::wait(context, 20) == 0);
        let batch = lab_io_process_stream::poll(process); assert(batch.code == 0);
        early = early || (!batch.done && batch.chunks.len > 0);
        for chunk in batch.chunks { if chunk.stream == 1 { out.append(chunk.bytes); } else { err.append(chunk.bytes); } }
        ticks += lab_io_timer::poll(timer).count;
        let changes = lab_fs_watch::poll(watch); assert(changes.code == 0); saw_watch = saw_watch || changes.rescan;
        for event in changes.events { saw_watch = saw_watch || event.path == "io-contract-temporary.txt"; }
        if batch.done { assert(batch.result == lab_io_process::OK && batch.exit_code == 0); break; }
    }
    var expected_err: u8[>..] = []; expected_err.append("warning:"); expected_err.push(0xFF); expected_err.push('\n');
    assert(early && ticks > 0 && saw_watch && out == "first\n日本語\nlast\n" && err == expected_err);
    assert(lab_io_process_stream::close(process) && lab_io_timer::close(timer) && lab_fs_watch::close(watch)); assert(delete_file(changed_path));
    let literal_args: const u8[:][6] = [helper, "echo", "", "space and 日本語", "quote\"end\\", "& $ ` literal"];
    let echo = stream_collect(context, program, literal_args, repo); assert(echo.code == 0);
    let echo_doc = lab_json_codec::parse(echo.out); let empty, a = lab_json_codec::text(lab_json_codec::at(lab_json_codec::root(echo_doc), 0));
    let literal, b = lab_json_codec::text(lab_json_codec::at(lab_json_codec::root(echo_doc), 3)); assert(a && b && empty == "" && literal == "& $ ` literal");
    let fail_args: const u8[:][2] = [helper, "exit"]; let failed = stream_collect(context, program, fail_args, repo);
    assert(failed.code == 0 && failed.exit_code == 42 && failed.err == "intentional failure");
    let missing = stream_collect(context, "goose-no-such-program-812437", [], repo); assert(missing.code == lab_io_process::SPAWN);
    let sleep_args: const u8[:][2] = [helper, "sleep"];
    let timeout = stream_collect(context, program, sleep_args, repo, lab_io_process_stream::Options { timeout_ms: 100 }); assert(timeout.code == lab_io_process::TIMEOUT);
    let flood_args: const u8[:][2] = [helper, "flood"];
    let flood = stream_collect(context, program, flood_args, repo, lab_io_process_stream::Options { max_bytes: 4096 });
    assert(flood.code == lab_io_process::LIMIT && flood.out.len + flood.err.len <= 4096);
    process = lab_io_process_stream::start(context, program, sleep_args, repo); assert(process.code == 0 && lab_io_process_stream::cancel(process) == 0);
    let cancelled_until = clock_ns() + 2000000000; var done = false;
    while !done { assert(clock_ns() < cancelled_until && lab_io_event_loop::wait(context, 20) == 0); let batch = lab_io_process_stream::poll(process); done = batch.done; if done { assert(batch.result == lab_io_process::CANCELLED); } }
    assert(lab_io_process_stream::close(process));
    var processes: lab_io_process_stream::Handle[..16] = [];
    for i in 16 { let p = lab_io_process_stream::start(context, program, sleep_args, repo); assert(p.code == 0); processes.push(p); }
    assert(lab_io_process_stream::start(context, program, sleep_args, repo).code == lab_io_event_loop::LIMIT);
    for &p in processes { assert(lab_io_process_stream::close(p)); }
    let orphan = str(repo, "/io-orphan-temporary.txt"); let tree_args: const u8[:][3] = [helper, "tree-stall", orphan[..]];
    process = lab_io_process_stream::start(context, program, tree_args, repo, lab_io_process_stream::Options { stdin: true }); timer = lab_io_timer::start(context, 86400000); watch = lab_fs_watch::on(context, repo);
    assert(process.code == 0 && timer.code == 0 && watch.code == 0);
    let started_until = clock_ns() + 2000000000; var spawned = false;
    while !spawned { assert(clock_ns() < started_until && lab_io_event_loop::wait(context, 20) == 0); let batch = lab_io_process_stream::poll(process); spawned = batch.chunks.len > 0; }
    let blocked_input: u8[65536] = ['x'; 65536]; assert(lab_io_process_stream::send(process, blocked_input) == 0); await_blocked_input(context, process);
    var old_context = context; let closing = clock_ns(); assert(lab_io_event_loop::close(context) && clock_ns() - closing < 2000000000);
    assert(lab_io_process_stream::poll(process).code == lab_io_event_loop::CLOSED && lab_io_timer::poll(timer).code == lab_io_event_loop::CLOSED && lab_fs_watch::poll(watch).code == lab_io_event_loop::CLOSED);
    context = lab_io_event_loop::create(); assert(context.id != old_context.id && !lab_io_event_loop::close(old_context) && lab_io_event_loop::info(old_context).code == lab_io_event_loop::CLOSED);
    assert(lab_io_event_loop::info(context).resources == 0 && lab_io_event_loop::close(context));
    sleep_ms(1200); assert(!file_exists(orphan));
    print("I/O core: shared readiness, timers, owned stream bytes, live output, cancellation, limits, stale IDs, thread ownership and process-tree cleanup passed");
}

fn read_contents(context: const lab_io_event_loop::Context&, path: const u8[:], limit: i64 = 2097152) -> lab_fs_async_files::Contents {
    var file = lab_fs_async_files::read(context, path, limit); assert(file.code == 0);
    let until = clock_ns() + 5000000000;
    loop {
        assert(clock_ns() < until && lab_io_event_loop::wait(context, 20) == 0);
        let contents = lab_fs_async_files::poll(file); assert(contents.code == 0);
        if contents.done {
            let repeated = lab_fs_async_files::poll(file); assert(repeated.done && repeated.result == contents.result && repeated.bytes.len == 0);
            assert(lab_fs_async_files::close(file)); return contents;
        }
        assert(contents.result == -1 && contents.bytes.len == 0);
    }
}
fn count_entries(context: const lab_io_event_loop::Context&, path: const u8[:], limit: i64, expected_result: i32) -> i64 {
    var listing = lab_fs_async_files::list(context, path, limit); assert(listing.code == 0);
    var count: i64 = 0; let until = clock_ns() + 5000000000;
    loop {
        assert(clock_ns() < until && lab_io_event_loop::wait(context, 20) == 0);
        let page = lab_fs_async_files::poll(listing); assert(page.code == 0); count += page.entries.len;
        if page.done { assert(page.result == expected_result); break; }
        assert(page.result == -1);
    }
    let repeated = lab_fs_async_files::poll(listing); assert(repeated.done && repeated.result == expected_result && repeated.entries.len == 0);
    assert(lab_fs_async_files::close(listing)); count
}
fn file_jobs_contract(root: const u8[:]) {
    var context = lab_io_event_loop::create(); assert(context.code == 0);
    let path = str(root, "/bytes.bin"); var borrowed: u8[..2048] = path;
    var file = lab_fs_async_files::read(context, borrowed, 6); borrowed = "changed after start";
    var listing = lab_fs_async_files::list(context, str(root, "/many"), 70); var timer = lab_io_timer::start(context, 0, 1);
    assert(file.code == 0 && listing.code == 0 && timer.code == 0);
    let wrong_kind = lab_fs_async_files::Listing { id: file.id }; assert(lab_fs_async_files::poll(wrong_kind).code == lab_io_event_loop::CLOSED);
    var first = lab_fs_async_files::Page {}; var count: i64 = 0; var pages: i64 = 0; var read_done = false; var listed = false; var ticks: i64 = 0;
    var saved: u8[>..] = []; var saved_result: i32 = -1; var seen: bool[70] = [false; 70];
    let until = clock_ns() + 5000000000;
    while !read_done || !listed {
        assert(clock_ns() < until && lab_io_event_loop::wait(context, 20) == 0); ticks += lab_io_timer::poll(timer).count;
        if !read_done { let result = lab_fs_async_files::poll(file); assert(result.code == 0); if result.done { saved.append(result.bytes); saved_result = result.result; read_done = true; } }
        if !listed {
            let page = lab_fs_async_files::poll(listing); assert(page.code == 0);
            if page.entries.len > 0 {
                if pages == 0 { first = page; } pages++; count += page.entries.len;
                for entry in page.entries {
                    assert(entry.kind == lab_fs_async_files::FILE); var found = false;
                    for i in 70 { if entry.name == str("entry-", if i < 10 { "00" } else { "0" }, i, " 日本語.txt") { assert(!seen[i]); seen[i] = true; found = true; break; } }
                    assert(found);
                }
            }
            if page.done { assert(page.result == 0); listed = true; }
        }
    }
    let expected: u8[6] = [0, 13, 10, 10, 26, 255]; assert(saved_result == 0 && saved == expected);
    assert(count == 70 && pages >= 3 && ticks > 0 && first.entries.len > 0);
    let first_name: u8[..1024] = first.entries[0].name;
    let final_page = lab_fs_async_files::poll(listing); assert(final_page.done && final_page.entries.len == 0);
    var stale_file = file; var stale_listing = listing;
    assert(lab_fs_async_files::close(file) && lab_fs_async_files::close(listing) && lab_io_timer::close(timer));
    assert(saved == expected && first.entries[0].name == first_name); // Own results survive native close/page reuse.
    assert(lab_fs_async_files::poll(stale_file).code == lab_io_event_loop::CLOSED && !lab_fs_async_files::close(stale_file));
    assert(lab_fs_async_files::poll(stale_listing).code == lab_io_event_loop::CLOSED && !lab_fs_async_files::close(stale_listing));
    let limited = read_contents(context, path, 5); assert(limited.result == lab_io_event_loop::LIMIT && limited.bytes.len == 0);
    assert(read_contents(context, str(root, "/missing")).result == lab_io_event_loop::MISSING);
    assert(read_contents(context, root).result == lab_io_event_loop::NOT_REGULAR);
    assert(read_contents(context, str(root, "/oversize.bin")).result == lab_io_event_loop::LIMIT);
    let empty = read_contents(context, str(root, "/empty.bin"), 0); assert(empty.result == 0 && empty.bytes.len == 0);
    let large = read_contents(context, str(root, "/large.bin")); assert(large.result == 0 && large.bytes.len == 2097152);
    for i in large.bytes.len { assert(large.bytes[i] == (i & 255) as u8); }
    assert(count_entries(context, str(root, "/many"), 70, 0) == 70);
    assert(count_entries(context, str(root, "/many"), 69, lab_io_event_loop::LIMIT) == 69);
    assert(count_entries(context, str(root, "/many"), 0, lab_io_event_loop::LIMIT) == 0);
    assert(count_entries(context, str(root, "/empty-dir"), 0, 0) == 0);
    assert(count_entries(context, path, 10, lab_io_event_loop::NOT_DIRECTORY) == 0);
    assert(count_entries(context, str(root, "/missing"), 10, lab_io_event_loop::MISSING) == 0);
    assert(lab_fs_async_files::read(context, path, -1).code == lab_io_event_loop::INVALID);
    assert(lab_fs_async_files::list(context, root, 4097).code == lab_io_event_loop::INVALID);
    assert(lab_fs_async_files::read(context, [97, 0, 98]).code == lab_io_event_loop::INVALID);
    assert(lab_fs_async_files::list(context, [255]).code == lab_io_event_loop::INVALID);
    file = lab_fs_async_files::read(context, str(root, "/large.bin")); assert(lab_fs_async_files::cancel(file) == 0);
    let cancel_until = clock_ns() + 5000000000; var cancelled = false;
    while !cancelled {
        assert(clock_ns() < cancel_until && lab_io_event_loop::wait(context, 20) == 0);
        let result = lab_fs_async_files::poll(file); cancelled = result.done;
        if cancelled { assert(result.result == lab_io_event_loop::CANCELLED && result.bytes.len == 0); }
    }
    assert(lab_fs_async_files::close(file));
    listing = lab_fs_async_files::list(context, str(root, "/many")); var got_page = false;
    while !got_page { assert(lab_io_event_loop::wait(context, 20) == 0); got_page = lab_fs_async_files::poll(listing).entries.len > 0; }
    assert(lab_fs_async_files::cancel(listing) == 0);
    cancelled = false;
    while !cancelled { assert(lab_io_event_loop::wait(context, 20) == 0); let result = lab_fs_async_files::poll(listing); cancelled = result.done; if cancelled { assert(result.result == lab_io_event_loop::CANCELLED && result.entries.len == 0); } }
    assert(lab_fs_async_files::close(listing));
    var reads: lab_fs_async_files::Read[..16] = []; var lists: lab_fs_async_files::Listing[..16] = [];
    for i in 16 { let r = lab_fs_async_files::read(context, path); let d = lab_fs_async_files::list(context, root); assert(r.code == 0 && d.code == 0); reads.push(r); lists.push(d); }
    assert(lab_fs_async_files::read(context, path).code == lab_io_event_loop::LIMIT && lab_fs_async_files::list(context, root).code == lab_io_event_loop::LIMIT);
    assert(lab_io_event_loop::close(context));
    for r in reads { assert(lab_fs_async_files::poll(r).code == lab_io_event_loop::CLOSED); }
    for d in lists { assert(lab_fs_async_files::poll(d).code == lab_io_event_loop::CLOSED); }
    context = lab_io_event_loop::create(); assert(lab_io_event_loop::info(context).resources == 0);
    // Also close while the next page is in flight or waiting to be drained.
    listing = lab_fs_async_files::list(context, root); got_page = false;
    let page_until = clock_ns() + 5000000000;
    while !got_page { assert(clock_ns() < page_until && lab_io_event_loop::wait(context, 20) == 0); got_page = lab_fs_async_files::poll(listing).entries.len > 0; }
    assert(lab_fs_async_files::close(listing) && lab_io_event_loop::info(context).resources == 0 && lab_io_event_loop::close(context));
    print("Async files: owned binary reads/pages, exact budgets, cancellation, invalid/type errors, stale IDs and context cleanup passed");
}

fn await_saved(context: const lab_io_event_loop::Context&, handle: const lab_fs_async_files::Write&, ready: bool = false) -> lab_fs_async_files::Saved {
    let until = clock_ns() + 5000000000;
    loop {
        assert(clock_ns() < until && lab_io_event_loop::wait(context, 20) == 0);
        let saved = lab_fs_async_files::poll(handle); assert(saved.code == 0);
        if saved.done || (ready && saved.ready) { return saved; }
        assert(saved.result == -1 && !saved.committed && saved.size == 0 && saved.digest == 0);
    }
}
fn write_jobs_contract(root: const u8[:]) {
    var context = lab_io_event_loop::create(); assert(context.code == 0);
    let target = str(root, "/atomic 日本語.bin"); let old: const u8[:] = "old complete contents";
    let expected: u8[8] = [0, 13, 10, 10, 26, 255, 97, 98];
    assert(write_file_atomic(target, old));
    var path: u8[..2048] = target; var input: u8[..8] = expected;
    var write = lab_fs_async_files::prepare(context, path, input); assert(write.code == 0);
    let wrong_kind = lab_fs_async_files::Read { id: write.id }; assert(lab_fs_async_files::poll(wrong_kind).code == lab_io_event_loop::CLOSED);
    assert(lab_fs_async_files::commit(write) == lab_io_event_loop::NOT_READY);
    path = "changed after start"; input = "changed!";
    let ready = await_saved(context, write, true);
    assert(ready.ready && !ready.done && ready.synced && ready.written == expected.len && !ready.committed);
    assert(read_contents(context, target).bytes == old);
    assert(lab_fs_async_files::commit(write) == 0 && lab_fs_async_files::commit(write) == lab_io_event_loop::NOT_READY);
    let saved = await_saved(context, write);
    assert(saved.done && !saved.ready && saved.result == 0 && saved.committed && saved.synced && saved.cleanup_code == 0);
    assert(saved.size == expected.len && saved.digest == lab_fs_files::digest(expected) && saved.temporary.len == 0);
    assert(read_contents(context, target).bytes == expected);
    assert(lab_fs_async_files::cancel(write) == 0); let late = lab_fs_async_files::poll(write);
    assert(late.done && late.result == 0 && late.committed && late.digest == saved.digest);
    var stale = write; assert(lab_fs_async_files::close(write));
    write = lab_fs_async_files::prepare(context, target, "discarded"); let staged = await_saved(context, write, true);
    assert(staged.ready && read_contents(context, target).bytes == expected && lab_fs_async_files::cancel(write) == 0);
    let cancelled = await_saved(context, write); assert(cancelled.result == lab_io_event_loop::CANCELLED && !cancelled.committed && cancelled.cleanup_code == 0 && cancelled.temporary.len == 0);
    assert(read_contents(context, target).bytes == expected && lab_fs_async_files::close(write));
    // Cancellation during the recheck prevents publication, even when stat finished.
    write = lab_fs_async_files::prepare(context, target, "not published"); assert(await_saved(context, write, true).ready);
    assert(lab_fs_async_files::commit(write) == 0 && lab_fs_async_files::cancel(write) == 0);
    let before_publish = await_saved(context, write); assert(before_publish.result == lab_io_event_loop::CANCELLED && !before_publish.committed);
    assert(read_contents(context, target).bytes == expected && lab_fs_async_files::close(write));
    // Recheck rejects a destination changed to a directory after preparation.
    let raced = str(root, "/atomic-raced"); assert(write_file_atomic(raced, old));
    write = lab_fs_async_files::prepare(context, raced, "new"); assert(await_saved(context, write, true).ready);
    assert(delete_file(raced) && make_dir(raced) && lab_fs_async_files::commit(write) == 0);
    let refused = await_saved(context, write); assert(refused.result == lab_io_event_loop::NOT_REGULAR && !refused.committed && refused.cleanup_code == 0 && refused.temporary.len == 0);
    assert(is_dir(raced) && lab_fs_async_files::close(write) && delete_dir(raced));
    write = lab_fs_async_files::replace(context, target, [], lab_fs_async_files::WriteOptions { sync_file: false });
    let empty = await_saved(context, write); assert(empty.result == 0 && empty.committed && !empty.synced && empty.size == 0 && empty.digest == lab_fs_files::digest([]));
    assert(read_contents(context, target).bytes.len == 0 && lab_fs_async_files::close(write));
    let large = read_contents(context, str(root, "/large.bin"));
    write = lab_fs_async_files::replace(context, target, large.bytes); let full = await_saved(context, write);
    assert(full.result == 0 && full.committed && full.size == 2097152 && full.digest == lab_fs_files::digest(large.bytes));
    assert(read_contents(context, target).bytes == large.bytes && lab_fs_async_files::close(write));
    // Two ordinary saves are concurrent; the final contents must be a whole payload.
    var first = lab_fs_async_files::replace(context, target, "whole first"); var second = lab_fs_async_files::replace(context, target, "whole second");
    assert(await_saved(context, first).committed && await_saved(context, second).committed);
    let last = read_contents(context, target); assert(last.bytes == "whole first" || last.bytes == "whole second");
    assert(lab_fs_async_files::close(first) && lab_fs_async_files::close(second));
    write = lab_fs_async_files::replace(context, str(root, "/no-parent/file"), "missing parent");
    let missing = await_saved(context, write); assert(missing.result == lab_io_event_loop::MISSING && !missing.committed && missing.cleanup_code == 0); lab_fs_async_files::close(write);
    write = lab_fs_async_files::replace(context, str(root, "/empty-dir"), "directory");
    let directory = await_saved(context, write); assert(directory.result == lab_io_event_loop::NOT_REGULAR && !directory.committed); lab_fs_async_files::close(write);
    assert(lab_fs_async_files::prepare(context, [97, 0, 98], "bad path").code == lab_io_event_loop::INVALID);
    var too_large: u8[>..] = []; too_large.resize(2097153, 0);
    assert(lab_fs_async_files::replace(context, target, too_large).code == lab_io_event_loop::LIMIT);
    assert(lab_fs_async_files::poll(stale).code == lab_io_event_loop::CLOSED && !lab_fs_async_files::close(stale));
    // Close a ready replacement without committing, and close an in-flight one.
    assert(write_file_atomic(target, old)); write = lab_fs_async_files::prepare(context, target, "discard on close"); assert(await_saved(context, write, true).ready);
    assert(lab_fs_async_files::close(write) && read_contents(context, target).bytes == old);
    write = lab_fs_async_files::replace(context, target, large.bytes); assert(lab_fs_async_files::close(write));
    assert(read_contents(context, target).bytes == old);
    var writes: lab_fs_async_files::Write[..16] = [];
    for i in 16 { let handle = lab_fs_async_files::prepare(context, target, "never committed"); assert(handle.code == 0); writes.push(handle); }
    assert(lab_fs_async_files::prepare(context, target, "over limit").code == lab_io_event_loop::LIMIT);
    assert(lab_io_event_loop::close(context)); for handle in writes { assert(lab_fs_async_files::poll(handle).code == lab_io_event_loop::CLOSED); }
    context = lab_io_event_loop::create(); assert(read_contents(context, target).bytes == old && lab_io_event_loop::info(context).resources == 0);
    assert(lab_io_event_loop::close(context) && delete_file(target));
    print("Async replacement: copied input, prepare/commit, receipts, cancelled/failed old-file preservation, whole concurrent saves and cleanup passed");
}


struct DuplexProbe { child: lab_io_process_stream::Handle }
thread_fn duplex_other_thread() {
    var probe = qget<DuplexProbe>();
    assert(lab_io_process_stream::send(probe.child, "wrong thread") == lab_io_event_loop::WRONG_THREAD);
    assert(lab_io_process_stream::eof(probe.child) == lab_io_event_loop::WRONG_THREAD && !lab_io_process_stream::close(probe.child));
    qput(LoopReady { true });
}
fn duplex_contract(repo: const u8[:], program: const u8[:], helper: const u8[:]) {
    var context = lab_io_event_loop::create(); let arguments: const u8[:][2] = [helper, "stdin-echo"];
    var child = lab_io_process_stream::start(context, program, arguments, repo, lab_io_process_stream::Options { stdin: true, max_pending_bytes: 4096 });
    assert(child.code == 0 && lab_io_process_stream::send(child, []) == 0);
    var payload: u8[>..] = []; for i in 262144 { payload.push((i % 256) as u8); }

    assert(lab_io_process_stream::send(child, payload) == lab_io_event_loop::LIMIT);
    var at: i64 = 0; var eof = false; var blocked = false; var out: u8[>..] = []; var err: u8[>..] = [];
    let until = clock_ns() + 5000000000;
    loop {
        while at < payload.len {
            let end = min(at + 4096, payload.len);
            let code = lab_io_process_stream::send(child, payload[at..end]);
            if code == lab_io_event_loop::WOULD_BLOCK { blocked = true; break; }
            assert(code == 0); at = end;
        }
        if at == payload.len && !eof {
            assert(lab_io_process_stream::eof(child) == 0 && lab_io_process_stream::eof(child) == 0);
            assert(lab_io_process_stream::send(child, "late") == lab_io_event_loop::INPUT_CLOSED); eof = true;
        }
        assert(clock_ns() < until && lab_io_event_loop::wait(context, 20) == 0);
        let batch = lab_io_process_stream::poll(child); assert(batch.code == 0 && batch.input.enabled);
        assert(batch.input.pending <= 4096 && batch.input.sent <= batch.input.accepted);
        for chunk in batch.chunks { if chunk.stream == 1 { out.append(chunk.bytes); } else { err.append(chunk.bytes); } }
        if batch.done {
            assert(batch.result == 0 && batch.exit_code == 0 && batch.input.closed && batch.input.eof && batch.input.result == 0);
            assert(batch.input.accepted == payload.len && batch.input.sent == payload.len && batch.input.pending == 0); break;
        }
    }
    assert(blocked && out.len == 131072 + payload.len && out[131072..] == payload && err == "EOF\n");
    var stale = child; assert(lab_io_process_stream::close(child) && lab_io_process_stream::send(stale, "stale") == lab_io_event_loop::CLOSED);
    let dialog: const u8[:][2] = [helper, "stdin-dialog"];
    child = lab_io_process_stream::start(context, program, dialog, repo, lab_io_process_stream::Options { stdin: true });
    let worker = thread_spawn(duplex_other_thread); qput(DuplexProbe { child }); assert(qget<LoopReady>().value); thread_wait(worker);
    var mutable: u8[..32] = "first 日本語\n"; assert(lab_io_process_stream::send(child, mutable) == 0); mutable = "changed";
    var replies: u8[>..] = []; var sent_second = false;
    let dialog_until = clock_ns() + 5000000000;
    loop {
        assert(clock_ns() < dialog_until && lab_io_event_loop::wait(context, 20) == 0);
        let batch = lab_io_process_stream::poll(child); for chunk in batch.chunks { if chunk.stream == 1 { replies.append(chunk.bytes); } }
        if !sent_second && replies == "reply:first 日本語\n" {
            assert(!batch.done && lab_io_process_stream::send(child, "second\n") == 0 && lab_io_process_stream::eof(child) == 0); sent_second = true;
        }
        if batch.done { assert(batch.result == 0 && batch.exit_code == 0); break; }
    }
    assert(sent_second && replies == "reply:first 日本語\nreply:second\n" && lab_io_process_stream::close(child));
    let closed: const u8[:][2] = [helper, "stdin-closed"];
    child = lab_io_process_stream::start(context, program, closed, repo, lab_io_process_stream::Options { stdin: true });
    var notified = false; var input_failed = false; var output: u8[>..] = [];
    let closed_until = clock_ns() + 5000000000;
    loop {
        assert(clock_ns() < closed_until && lab_io_event_loop::wait(context, 20) == 0);
        let batch = lab_io_process_stream::poll(child);
        for chunk in batch.chunks { if chunk.stream == 1 { output.append(chunk.bytes); } }
        if !notified && output.len > 0 { assert(lab_io_process_stream::send(child, "closed reader") == 0); notified = true; }
        if batch.input.closed { input_failed = batch.input.result == lab_io_event_loop::IO && batch.input.accepted > batch.input.sent; }
        if batch.done { assert(batch.result == 0 && batch.exit_code == 0); break; }
    }
    assert(input_failed && output == "closed\nstill output\n" && lab_io_process_stream::send(child, "late") == lab_io_event_loop::INPUT_CLOSED);
    assert(lab_io_process_stream::close(child));
    let sleeping: const u8[:][2] = [helper, "sleep"];
    child = lab_io_process_stream::start(context, program, dialog, repo, lab_io_process_stream::Options { stdin: true });
    assert(lab_io_process_stream::eof(child) == 0);
    let empty_until = clock_ns() + 5000000000;
    loop { assert(clock_ns() < empty_until && lab_io_event_loop::wait(context, 20) == 0); let batch = lab_io_process_stream::poll(child); if batch.done { assert(batch.result == 0 && batch.exit_code == 0 && batch.input.closed && batch.input.sent == 0 && batch.input.result == 0); break; } }
    assert(lab_io_process_stream::close(child));
    child = lab_io_process_stream::start(context, program, sleeping, repo, lab_io_process_stream::Options { stdin: true, timeout_ms: 100 });
    assert(lab_io_process_stream::send(child, payload[..65536]) == 0);
    let timeout_until = clock_ns() + 2000000000;
    loop { assert(clock_ns() < timeout_until && lab_io_event_loop::wait(context, 20) == 0); let batch = lab_io_process_stream::poll(child); if batch.done { assert(batch.result == lab_io_process::TIMEOUT && batch.input.closed); break; } }
    assert(lab_io_process_stream::close(child));
    child = lab_io_process_stream::start(context, program, sleeping, repo);
    assert(lab_io_process_stream::send(child, "disabled") == lab_io_event_loop::UNSUPPORTED && lab_io_process_stream::eof(child) == lab_io_event_loop::UNSUPPORTED);
    assert(lab_io_process_stream::close(child));
    child = lab_io_process_stream::start(context, program, sleeping, repo, lab_io_process_stream::Options { stdin: true, max_pending_bytes: 2097152 });
    assert(lab_io_process_stream::send(child, payload) == 0);
    await_blocked_input(context, child);
    let before = clock_ns(); assert(lab_io_process_stream::cancel(child) == 0 && lab_io_process_stream::send(child, "cancelled") == lab_io_event_loop::CANCELLED);
    loop { assert(clock_ns() - before < 2000000000 && lab_io_event_loop::wait(context, 20) == 0); let batch = lab_io_process_stream::poll(child); if batch.done { assert(batch.result == lab_io_process::CANCELLED && batch.input.closed && batch.input.result == lab_io_event_loop::CANCELLED); break; } }
    assert(lab_io_process_stream::close(child));
    child = lab_io_process_stream::start(context, program, sleeping, repo, lab_io_process_stream::Options { stdin: true });
    assert(lab_io_process_stream::send(child, payload[..65536]) == 0);
    await_blocked_input(context, child);
    let closing = clock_ns(); assert(lab_io_event_loop::close(context) && clock_ns() - closing < 2000000000);
    assert(lab_io_process_stream::send(child, "closed") == lab_io_event_loop::CLOSED);
    print("Duplex processes: copied binary input, bounded retry, live request/reply, EOF, reader failure, wrong threads and blocked-write cancellation passed");
}
fn await_blocked_input(context: const lab_io_event_loop::Context&, child: const lab_io_process_stream::Handle&) {
    let until = clock_ns() + 5000000000;
    loop {
        assert(clock_ns() < until && lab_io_event_loop::wait(context, 20) == 0);
        let batch = lab_io_process_stream::poll(child); assert(batch.code == 0 && !batch.done);
        if batch.input.sent > 0 && batch.input.pending > 0 { return; }
    }
}

fn file_search_contract(root: const u8[:]) {
    var state = lab_fs_search::start(root, "needle", lab_fs_search::Options { include: "**/*.txt", parallel: 2 }); assert(state.code == 0);
    var count: i64 = 0; var first = default<lab_fs_search::Hit>(); var got_readme = false; var streamed = false;
    let until = clock_ns() + 10000000000;
    loop {
        assert(clock_ns() < until); let batch = lab_fs_search::poll(state, 20); assert(batch.code == 0 && batch.progress.active <= 2);
        for hit in batch.hits { count++; assert(hit.preview.len > 0); if hit.path == "readme.txt" && hit.line == 1 { first = hit; got_readme = true; } }
        if batch.hits.len > 0 && !batch.done { streamed = true; }
        if batch.done { assert(batch.result == 0 && batch.progress.matches == 75 && batch.progress.searched == 6 && batch.progress.skipped == 0); break; }
    }
    assert(count == 75 && streamed && got_readme && first.column == 5 && first.start == 10 && first.end == 16);
    assert(lab_fs_search::close(state) && !lab_fs_search::close(state) && lab_fs_search::poll(state).code == lab_io_event_loop::CLOSED);
    let opened = lab_fs_search::open_hit(root, first, "needle"); assert(opened.code == 0 && opened.bytes == "日本語 needle\r\nababa needle\nNEEDLE\n");
    let target = str(root, "/readme.txt"); assert(write_file_atomic(target, "prefix 日本語 needle\r\nababa needle\nNEEDLE\n"));
    let stale = lab_fs_search::open_hit(root, first, "needle"); assert(stale.code == lab_fs_search::INVALID && stale.bytes.len == 0 && starts_with(stale.error, "File changed"));
    assert(write_file_atomic(target, opened.bytes));
    var bad = first; bad.path = "../readme.txt"; assert(lab_fs_search::open_hit(root, bad, "needle").code == lab_fs_search::INVALID);
    bad = first; bad.end = 0x7FFFFFFFFFFFFFFF; assert(lab_fs_search::open_hit(root, bad, "needle").code == lab_fs_search::INVALID);
    state = lab_fs_search::start(root, "needle"); assert(lab_fs_search::poll(state).code == 0 && lab_fs_search::cancel(state) == 0);
    let cancelled = lab_fs_search::poll(state); assert(cancelled.done && cancelled.result == lab_fs_search::CANCELLED && cancelled.progress.active == 0 && lab_fs_search::close(state));
    state = lab_fs_search::start(root, "needle"); state.deadline = clock_ns() - 1;
    let timed = lab_fs_search::poll(state); assert(timed.done && timed.result == lab_fs_search::TIMEOUT && lab_fs_search::close(state));
    var token = lab_io_cancel::create(); lab_io_cancel::request(token); state = lab_fs_search::start(root, "needle", lab_fs_search::Options { cancel: token });
    assert(lab_fs_search::poll(state).result == lab_fs_search::CANCELLED && lab_fs_search::close(state)); lab_io_cancel::destroy(token);
    print("File search: streamed pages, bounded active reads, exact selection, changed files, cancellation, deadline and explicit close passed");
}

fn await_document(file: lab_document_file::State&) {
    let until = clock_ns() + 5000000000; while lab_document_file::busy(file) { assert(clock_ns() < until); lab_document_file::poll(file); sleep_ms(1); }
    assert(lab_io_event_loop::info(file.context).resources == 0);
}
fn disk_bytes(path: const u8[:]) -> u8[>..] { var bytes: u8[>..] = []; assert(read_file(path, bytes)); bytes }
fn document_file_contract(root: const u8[:]) {
    let path = str(root, "/document-contract.txt"); let original = "first 日本語\r\nsecond\r\n"; assert(write_file_atomic(path, original));
    var file = lab_document_file::create(); assert(file.code == 0 && lab_document_file::open(file, path)); await_document(file);
    assert(file.code == 0 && file.exists && lab_document_model::contents(file.document) == original);
    let code, changed = lab_document_model::insert(file.document, "saved "); assert(code == 0 && changed && lab_document_file::save(file)); await_document(file);
    assert(file.code == 0 && !lab_document_model::dirty(file.document) && disk_bytes(path) == str("saved ", original));
    assert(lab_document_model::select(file.document, 0, 0)); let code, changed = lab_document_model::insert(file.document, "local "); assert(code == 0 && changed);
    assert(write_file_atomic(path, "external\n") && lab_document_file::save(file)); await_document(file);
    assert(file.code == lab_document_file::CONFLICT && disk_bytes(path) == "external\n" && lab_document_model::dirty(file.document));
    assert(!lab_document_file::open(file, path) && file.code == lab_document_file::DIRTY);
    assert(lab_document_file::open(file, path, true)); await_document(file); assert(file.code == 0 && lab_document_model::contents(file.document) == "external\n");
    let code, changed = lab_document_model::insert(file.document, "cancelled "); assert(code == 0 && changed && lab_document_file::save(file)); lab_document_file::cancel(file);
    assert(!lab_document_file::busy(file) && disk_bytes(path) == "external\n" && lab_document_model::dirty(file.document));
    assert(lab_document_file::open(file, path, true)); await_document(file);
    let code, changed = lab_document_model::insert(file.document, "pending "); assert(code == 0 && changed && lab_document_file::save(file));
    let code, changed = lab_document_model::insert(file.document, "newer "); assert(code == 0 && changed); await_document(file);
    assert(file.code == lab_document_file::DIRTY && disk_bytes(path) == "external\n");
    let missing = str(root, "/document-new.txt"); assert(lab_document_file::open(file, missing, true)); await_document(file); assert(file.code == 0 && !file.exists);
    let code, changed = lab_document_model::insert(file.document, "new file\n"); assert(code == 0 && changed && lab_document_file::save(file)); await_document(file);
    assert(file.code == 0 && file.exists && disk_bytes(missing) == "new file\n" && delete_file(missing));
    assert(lab_document_file::open(file, missing)); await_document(file); assert(!file.exists);
    let code, changed = lab_document_model::insert(file.document, "mine"); assert(code == 0 && changed && write_file_atomic(missing, "someone else") && lab_document_file::save(file)); await_document(file);
    assert(file.code == lab_document_file::CONFLICT && disk_bytes(missing) == "someone else" && delete_file(missing));
    assert(lab_document_file::close(file) && delete_file(path));
    print("Document file: exact-baseline atomic saves, conflict/new-file races, cancellation, edited snapshots and cleanup passed");
}
