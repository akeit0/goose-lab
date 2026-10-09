// UI-independent navigation and disk observation. Borrow one owner-thread file session.
namespace lab_document_workspace;
import std;
import os;
import lab.document.model;
import lab.document.file;
import lab.fs.async_files;
import lab.io.event_loop;
import lab.fs.watch;
import lab.io.debounce;
import lab.fs.path;
import lab.text.literal_search;
let SAME: i32 = 0; let CHANGED: i32 = 1; let DELETED: i32 = 2; let UNREADABLE: i32 = 3;
enum Choice { Keep, Save, Discard }
struct Intent { path: u8[..512] = [], start: i64 = -1, end: i64 = -1, query: u8[..512] = [], ignore_case: bool = false, reload: bool = false }
struct State {
    intent: Intent = Intent {}, prompt: bool = false, saving: bool = false, opening: bool = false,
    selection: lab_document_model::Selection = lab_document_model::Selection {},
    generation: u64 = 0, reveal: u64 = 0, stale: bool = false,
    watch: lab_fs_watch::Handle = lab_fs_watch::Handle {}, watched: u8[..512] = [], watch_code: i32 = 0,
    changes: lab_io_debounce::State = lab_io_debounce::State {}, reading: lab_fs_async_files::Read = lab_fs_async_files::Read {},
    deadline: i64 = 0, next_check: i64 = 0, disk: i32 = SAME, disk_code: i32 = 0,
}
fn stop_read(s: State&) { if s.reading.id != 0 { lab_fs_async_files::cancel(s.reading); lab_fs_async_files::close(s.reading); } }
fn close(s: State&) { stop_read(s); lab_fs_watch::close(s.watch); s.watched = []; lab_io_debounce::clear(s.changes); }
fn observe(s: State&, file: const lab_document_file::State&) {
    close(s); s.disk = SAME; s.disk_code = 0; s.generation = file.generation; s.watched = file.path;
    if file.path.len == 0 { return; }
    let parent, name = lab_fs_watch::parent(file.path); s.watch = lab_fs_watch::on(file.context, parent); s.watch_code = s.watch.code;
    // Close the read-before-watch gap, and periodically reconcile even if events are lost.
    lab_io_debounce::push(s.changes, clock_ns()); s.next_check = clock_ns() + 5000000000;
}
fn jump(s: State&, file: lab_document_file::State&) {
    let at = s.intent.start; let end = s.intent.end; s.stale = false;
    if s.intent.reload && at < 0 {
        var cursor = min(s.selection.cursor, lab_document_model::size(file.document)); var anchor = min(s.selection.anchor, lab_document_model::size(file.document));
        while !lab_document_model::boundary(file.document, cursor) { cursor--; } while !lab_document_model::boundary(file.document, anchor) { anchor--; }
        lab_document_model::select(file.document, cursor, anchor);
    }
    if at >= 0 {
        let pattern = lab_text_literal_search::compile(s.intent.query, s.intent.ignore_case);
        var valid = pattern.valid && end >= at && end - at == pattern.bytes.len && end <= lab_document_model::size(file.document) &&
            lab_document_model::boundary(file.document, at) && lab_document_model::boundary(file.document, end);
        if valid { let bytes = lab_document_model::read(file.document, at, end); for i in bytes.len { if lab_text_literal_search::folded(pattern, bytes[i]) != lab_text_literal_search::folded(pattern, pattern.bytes[i]) { valid = false; } } }
        if valid { lab_document_model::select(file.document, end, at); }
        else { s.stale = true; file.notice = "Search position changed · File opened; search again"; }
    }
    s.reveal++; s.intent = Intent {};
}
fn begin_open(s: State&, file: lab_document_file::State&) -> bool {
    stop_read(s);
    s.selection = file.document.selection;
    if !lab_document_file::open(file, s.intent.path, true, true) { s.prompt = false; s.intent = Intent {}; return false; }
    s.opening = true; s.prompt = false; true
}
fn request(s: State&, file: lab_document_file::State&, intent: Intent) -> bool {
    if lab_document_file::busy(file) || s.prompt || s.saving || s.opening { return false; }
    if intent.path.len == 0 || !lab_fs_async_files::valid_path(intent.path) { return false; }
    let absolute = lab_fs_path::absolute(intent.path, 512); if absolute.code != 0 { file.code = absolute.code; return false; }
    s.intent = intent; s.intent.path = absolute.bytes; s.intent.reload = intent.reload && s.intent.path == file.path;
    if s.intent.path == file.path && !intent.reload { jump(s, file); return true; }
    if lab_document_model::dirty(file.document) { s.prompt = true; lab_document_model::break_group(file.document); return true; }
    begin_open(s, file)
}
fn choose(s: State&, file: lab_document_file::State&, choice: Choice) -> bool {
    if !s.prompt || lab_document_file::busy(file) { return false; }
    match choice {
        Keep => { s.prompt = false; s.intent = Intent {}; true },
        Discard => { begin_open(s, file) },
        Save => {
            stop_read(s); if !lab_document_file::save(file) { return false; }
            s.prompt = false; s.saving = true; true
        },
    }
}
fn check(s: State&) { lab_io_debounce::push(s.changes, clock_ns()); s.next_check = 0; }
fn poll(s: State&, file: lab_document_file::State&) {
    let before = file.phase; lab_document_file::poll(file);
    if s.generation != file.generation || s.watched != file.path { observe(s, file); }
    if s.opening && !lab_document_file::busy(file) {
        s.opening = false;
        if file.code == 0 { jump(s, file); } else { s.intent = Intent {}; }
    }
    if s.saving && !lab_document_file::busy(file) {
        s.saving = false;
        if file.code == 0 && !lab_document_model::dirty(file.document) { begin_open(s, file); }
        else { s.intent = Intent {}; }
    }
    if before != lab_document_file::IDLE && !lab_document_file::busy(file) { check(s); }
    if lab_document_file::busy(file) { stop_read(s); return; }
    // Observation never adopts document bytes; editing can continue during this read.
    if file.path.len == 0 { return; }
    let driven = lab_io_event_loop::wait(file.context, 0); if driven != 0 { s.disk_code = driven; s.disk = UNREADABLE; return; }
    if s.watch.id != 0 {
        let batch = lab_fs_watch::poll(s.watch);
        if batch.code != 0 { s.watch_code = batch.code; lab_fs_watch::close(s.watch); }
        else if lab_fs_watch::changed(batch) { lab_io_debounce::push(s.changes, clock_ns()); }
    }
    let now = clock_ns();
    if s.reading.id != 0 {
        let result = lab_fs_async_files::poll(s.reading);
        if result.code != 0 || result.done || now >= s.deadline {
            let code = if result.code != 0 { result.code } else if result.done { result.result } else { lab_io_event_loop::CANCELLED };
            s.disk_code = code;
            if code == lab_io_event_loop::MISSING { s.disk = if file.exists { DELETED } else { SAME }; }
            else if code != 0 { s.disk = if code == lab_io_event_loop::LIMIT { CHANGED } else { UNREADABLE }; }
            else { let baseline = lab_document_model::baseline(file.document); s.disk = if !file.exists || baseline != result.bytes { CHANGED } else { SAME }; }
            stop_read(s); s.next_check = now + 5000000000;
        }
    }
    if s.reading.id == 0 && (now >= s.next_check || lab_io_debounce::ready(s.changes, now)) {
        lab_io_debounce::clear(s.changes); s.reading = lab_fs_async_files::read(file.context, file.path); s.deadline = now + 30000000000;
        s.next_check = now + 5000000000;
        if s.reading.code != 0 { s.disk_code = s.reading.code; s.disk = UNREADABLE; }
    }
}
fn message(s: const State&) -> const u8[:] {
    match s.disk { CHANGED => "Changed on disk · Local text is preserved", DELETED => "Deleted on disk · Local text is preserved", UNREADABLE => "Unable to check disk contents · Local text is preserved", _ => "" }
}
