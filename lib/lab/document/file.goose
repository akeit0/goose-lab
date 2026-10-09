// Owner-thread file session. Prepare, re-read the exact baseline, then commit.
namespace lab_document_file;
import std;
import lab.document.model;
import lab.io.event_loop;
import lab.fs.async_files;
import lab.fs.path;
let CONFLICT: i32 = 100; let DOCUMENT: i32 = 101; let DIRTY: i32 = 102;
let IDLE: i32 = 0; let LOADING: i32 = 1; let PREPARING: i32 = 2; let CHECKING: i32 = 3; let COMMITTING: i32 = 4;
struct State { context: lab_io_event_loop::Context = lab_io_event_loop::Context {}, path: u8[..512] = [], opening: u8[..512] = [],
    exists: bool = false, phase: i32 = IDLE, code: i32 = 0, notice: u8[..512] = [], revision: u64 = 0, deadline: i64 = 0,
    generation: u64 = 0, load_revision: u64 = 0, load_next: u64 = 0, require_exists: bool = false,
    reading: lab_fs_async_files::Read = lab_fs_async_files::Read {}, writing: lab_fs_async_files::Write = lab_fs_async_files::Write {},
    document: lab_document_model::Document = lab_document_model::Document {} }
fn create() -> State { let context = lab_io_event_loop::create(); State { context: context, code: context.code } }
fn busy(s: const State&) -> bool { s.phase != IDLE }
fn cleanup(s: State&) {
    if s.reading.id != 0 { lab_fs_async_files::cancel(s.reading); lab_fs_async_files::close(s.reading); }
    if s.writing.id != 0 { lab_fs_async_files::cancel(s.writing); lab_fs_async_files::close(s.writing); } s.phase = IDLE;
}
fn fail(s: State&, code: i32) { s.code = code; cleanup(s); }
fn open(s: State&, path: const u8[:], discard: bool = false, require_exists: bool = false) -> bool {
    if busy(s) || lab_io_event_loop::info(s.context).code != 0 { return false; }
    if lab_document_model::dirty(s.document) && !discard { s.code = DIRTY; s.notice = []; return false; }
    if path.len > 512 || !lab_fs_async_files::valid_path(path) { s.code = lab_io_event_loop::INVALID; return false; }
    let absolute = lab_fs_path::absolute(path, 512); if absolute.code != 0 { s.code = absolute.code; return false; }
    s.reading = lab_fs_async_files::read(s.context, absolute.bytes); if s.reading.code != 0 { s.code = s.reading.code; return false; }
    s.opening = absolute.bytes; s.load_revision = s.document.revision; s.load_next = s.document.next_revision; s.require_exists = require_exists;
    s.phase = LOADING; s.code = 0; s.notice = []; s.deadline = clock_ns() + 30000000000; true
}
fn target(s: State&, path: const u8[:]) -> bool {
    if busy(s) || s.exists || lab_io_event_loop::info(s.context).code != 0 || path.len > 512 || !lab_fs_async_files::valid_path(path) { return false; }
    let absolute = lab_fs_path::absolute(path, 512); if absolute.code != 0 { s.code = absolute.code; return false; }
    s.path = absolute.bytes; s.code = 0; s.notice = "New file target · Save to create"; true
}
fn save(s: State&) -> bool {
    if busy(s) || lab_io_event_loop::info(s.context).code != 0 || s.path.len == 0 || s.document.code != 0 { return false; }
    if !lab_document_model::dirty(s.document) && s.exists { s.code = 0; s.notice = "Unchanged"; return true; }
    let bytes = lab_document_model::contents(s.document); s.writing = lab_fs_async_files::prepare(s.context, s.path, bytes);
    if s.writing.code != 0 { s.code = s.writing.code; return false; }
    lab_document_model::break_group(s.document); s.revision = s.document.revision; s.phase = PREPARING; s.code = 0; s.notice = []; s.deadline = clock_ns() + 30000000000; true
}
fn cancel(s: State&) { if lab_io_event_loop::info(s.context).code != 0 { return; } if busy(s) { fail(s, lab_io_event_loop::CANCELLED); } }
fn poll(s: State&) {
    if !busy(s) { return; }
    let driven = lab_io_event_loop::wait(s.context, 0); if driven != 0 { if driven == lab_io_event_loop::WRONG_THREAD { s.code = driven; } else { fail(s, driven); } return; }
    if clock_ns() >= s.deadline { fail(s, lab_io_event_loop::CANCELLED); s.notice = "File operation timed out"; return; }
    if s.phase == LOADING {
        let loaded = lab_fs_async_files::poll(s.reading); if loaded.code != 0 { fail(s, loaded.code); return; } if !loaded.done { return; }
        if loaded.result != 0 && loaded.result != lab_io_event_loop::MISSING { fail(s, loaded.result); return; }
        if loaded.result == lab_io_event_loop::MISSING && s.require_exists { fail(s, loaded.result); return; }
        if s.document.revision != s.load_revision || s.document.next_revision != s.load_next { fail(s, DIRTY); s.notice = "Document changed during read · Open cancelled"; return; }
        var document = lab_document_model::create(loaded.bytes); if document.code != 0 { fail(s, DOCUMENT); return; }
        s.document = copy(document); s.generation++; s.path = s.opening; s.exists = loaded.result == 0; s.notice = if s.exists { "Opened" } else { "New file · Save to create" }; s.code = 0; cleanup(s); return;
    }
    let saved = lab_fs_async_files::poll(s.writing); if saved.code != 0 { fail(s, saved.code); return; }
    if saved.done {
        if saved.cleanup_code != 0 { s.notice = "Temporary cleanup failed; inspect the save directory"; }
        s.code = saved.result;
        if saved.committed && saved.result == 0 { if s.document.revision == s.revision { lab_document_model::mark_saved(s.document); s.exists = true; s.notice = "Saved · File data synced"; } else { s.code = DIRTY; s.notice = "Saved snapshot; document changed during save"; } }
        cleanup(s); return;
    }
    if s.phase == PREPARING && saved.ready {
        if s.document.revision != s.revision { fail(s, DIRTY); return; }
        s.reading = lab_fs_async_files::read(s.context, s.path); if s.reading.code != 0 { fail(s, s.reading.code); return; } s.phase = CHECKING;
    }
    if s.phase == CHECKING {
        let current = lab_fs_async_files::poll(s.reading); if current.code != 0 { fail(s, current.code); return; } if !current.done { return; }
        if s.document.revision != s.revision { fail(s, DIRTY); return; }
        if s.exists {
            if current.result != 0 { fail(s, if current.result == lab_io_event_loop::MISSING || current.result == lab_io_event_loop::LIMIT { CONFLICT } else { current.result }); return; }
            let original = lab_document_model::baseline(s.document); if current.bytes != original { fail(s, CONFLICT); return; }
        } else if current.result != lab_io_event_loop::MISSING { fail(s, if current.result == 0 || current.result == lab_io_event_loop::LIMIT { CONFLICT } else { current.result }); return; }
        lab_fs_async_files::close(s.reading); let code = lab_fs_async_files::commit(s.writing); if code != 0 { fail(s, code); return; } s.phase = COMMITTING;
    }
}
fn close(s: State&) -> bool { let closed = lab_io_event_loop::close(s.context); if closed { s.phase = IDLE; s.reading = lab_fs_async_files::Read {}; s.writing = lab_fs_async_files::Write {}; } closed }
fn message(s: const State&) -> const u8[:] {
    if s.code == CONFLICT { return "File changed on disk · Save cancelled; reopen to review"; }
    if s.code == DOCUMENT { return "File exceeds text limits, contains NUL, or is not UTF-8"; }
    if s.code == DIRTY { return if s.notice.len > 0 { s.notice[..] } else { "Unsaved changes · Save or explicitly discard first" }; }
    if s.code != 0 { return lab_io_event_loop::message(s.code); } s.notice
}
