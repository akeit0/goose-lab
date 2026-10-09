// Thread-owned bounded walker + read pool + incremental text search. No GUI/Git.
namespace lab_fs_search;
import std;
import os;
import lab.io.event_loop;
import lab.fs.async_files;
import lab.text.literal_search;
import lab.fs.glob;
import lab.text.utf8;
import lab.text.strings;
import lab.fs.path;
import lab.io.cancel;
let OK: i32 = 0; let INVALID: i32 = 1; let IO: i32 = 2; let LIMIT: i32 = 3; let CANCELLED: i32 = 4; let TIMEOUT: i32 = 5;
let BINARY: i32 = 1; let ENCODING: i32 = 2; let LARGE: i32 = 3; let READ_ERROR: i32 = 4; let UNKNOWN: i32 = 5; let PATH: i32 = 6;
struct Options {
    include: u8[..256] = "**", exclude: u8[..256][..16] = ["**/.git", "**/.git/**", "**/node_modules/**", "**/target/**", "**/build/**", "**/build-*/**", "**/third_party/**"],
    ignore_case: bool = false, parallel: i64 = 4, max_paths: i64 = 4096, max_matches: i64 = 2048, max_bytes: i64 = 2097152,
    max_depth: i64 = 32, timeout_ms: i64 = 30000, cancel: lab_io_cancel::Token = lab_io_cancel::Token {}
}
struct Hit { path: u8[..512], line: i64, column: i64, start: i64, end: i64, preview: u8[..320] }
struct Issue { path: u8[..512], reason: i32, detail: i32 = 0 }
struct Progress { entries: i64 = 0, files: i64 = 0, searched: i64 = 0, skipped: i64 = 0, matches: i64 = 0, active: i64 = 0 }
struct Batch { code: i32 = lab_io_event_loop::OK, done: bool = false, result: i32 = -1, hits: Hit[..32] = [], issues: Issue[..32] = [], progress: Progress = Progress {} }
struct Task { kind: i32, depth: i64, path: u8[..512] }
struct Slot { read: lab_fs_async_files::Read = lab_fs_async_files::Read {}, path: u8[..512] = [] }
struct State {
    code: i32 = OK, result: i32 = -1, context: lab_io_event_loop::Context = lab_io_event_loop::Context {}, root: u8[..512] = [], options: Options = Options {},
    pattern: lab_text_literal_search::Pattern = lab_text_literal_search::Pattern {}, include: lab_fs_glob::Pattern = lab_fs_glob::Pattern {}, excludes: lab_fs_glob::Pattern[..16] = [],
    tasks: Task[..4096] = [], directory_at: i64 = 0, file_at: i64 = 0, listing: lab_fs_async_files::Listing = lab_fs_async_files::Listing {},
    directory: u8[..512] = [], depth: i64 = 0, slots: Slot[8] = [Slot {}; 8], progress: Progress = Progress {}, deadline: i64 = 0,
    scanning: bool = false, path: u8[..512] = [], cursor: lab_text_literal_search::Cursor = lab_text_literal_search::Cursor {},
    position: i64 = 0, line: i64 = 1, column: i64 = 1, line_start: i64 = 0, data: u8[>..<] = []
}
fn start(root: const u8[:], query: const u8[:], options: Options = Options {}) -> State {
    var state = State {}; state.pattern = lab_text_literal_search::compile(query, options.ignore_case); state.include = lab_fs_glob::compile(options.include);
    if root.len < 1 || root.len > 512 || !lab_fs_async_files::valid_path(root) || !state.pattern.valid || !state.include.valid ||
        options.parallel < 1 || options.parallel > 8 || options.max_paths < 1 || options.max_paths > 4096 || options.max_matches < 1 || options.max_matches > 2048 ||
        options.max_bytes < 0 || options.max_bytes > 2097152 || options.max_depth < 0 || options.max_depth > 32 || options.timeout_ms < 1 || options.timeout_ms > 600000 {
        state.code = INVALID; return state;
    }
    for b in query { if b == 0 || b == '\n' || b == '\r' { state.code = INVALID; return state; } }
    for value in options.exclude { let pattern = lab_fs_glob::compile(value); if !pattern.valid { state.code = INVALID; return state; } state.excludes.push(pattern); }
    state.context = lab_io_event_loop::create(); if state.context.code != 0 { state.code = IO; return state; }
    state.root = root; state.options = options; state.deadline = clock_ns() + options.timeout_ms * 1000000;
    state.tasks.push(Task { kind: lab_fs_async_files::DIRECTORY, depth: 0, path: "" }); state
}
fn excluded(state: const State&, path: const u8[:], directory: bool) -> bool {
    for pattern in state.excludes {
        if lab_fs_glob::matches(pattern, path) { return true; }
        if directory && lab_fs_glob::matches(pattern, str(path, "/")) { return true; }
    } false
}
fn issue(state: State&, batch: Batch&, path: const u8[:], reason: i32, detail: i32 = 0) {
    state.progress.skipped++; batch.issues.push(Issue { path: path, reason: reason, detail: detail });
}
fn release(state: State&) {
    if state.listing.id != 0 { lab_fs_async_files::cancel(state.listing); lab_fs_async_files::close(state.listing); }
    for i in state.slots.len { let slot .= state.slots[i]; if slot.read.id != 0 { lab_fs_async_files::cancel(slot.read); lab_fs_async_files::close(slot.read); } }
    state.progress.active = 0; state.scanning = false; let data .= state.data; data.resize(0);
}
fn cancel(state: State&) -> i32 {
    let info = lab_io_event_loop::info(state.context); if info.code != 0 { return info.code; }
    if state.result < 0 { state.result = CANCELLED; release(state); } lab_io_event_loop::OK
}
fn close(state: State&) -> bool {
    if !lab_io_event_loop::close(state.context) { return false; }
    state.listing = lab_fs_async_files::Listing {}; for i in state.slots.len { state.slots[i].read = lab_fs_async_files::Read {}; }
    state.scanning = false; state.progress.active = 0; let data .= state.data; data.resize(0); true
}
fn preview(source: const u8[:], line_start: i64, match_at: i64) -> u8[>..] {
    var first = max(line_start, match_at - 80); while first > line_start && (source[first] & 0xC0) == 0x80 { first--; }
    var end = first; while end < source.len && end - first < 256 && source[end] != '\n' { end++; }
    while end > first && end < source.len && (source[end] & 0xC0) == 0x80 { end--; }
    var last = end; if last > first && source[last - 1] == '\r' { last--; }
    str(if first > line_start { "…" } else { "" }, lab_text_strings::display_bytes(source[first..last], 300), if end < source.len && source[end] != '\n' { "…" } else { "" })
}
fn scan(state: State&, batch: Batch&) {
    let found = lab_text_literal_search::scan(state.pattern, state.data, state.cursor);
    for span in found.matches {
        if state.progress.matches == state.options.max_matches { state.result = LIMIT; return; }
        while state.position < span.start {
            let b = state.data[state.position]; state.position++;
            if b == '\n' { state.line++; state.column = 1; state.line_start = state.position; }
            else if (b & 0xC0) != 0x80 { state.column++; }
        }
        let snippet = preview(state.data, state.line_start, span.start);
        batch.hits.push(Hit { path: state.path, line: state.line, column: state.column, start: span.start, end: span.end,
            preview: snippet }); state.progress.matches++;
    }
    if found.done { state.scanning = false; let data .= state.data; data.resize(0); state.progress.searched++; }
}
fn poll(state: State&, wait_ms: i64 = 0) -> Batch {
    if state.code != OK { return Batch { done: true, result: state.code }; }
    let driven = lab_io_event_loop::wait(state.context, wait_ms); if driven != 0 { return Batch { code: driven }; }
    var batch = Batch {};
    if state.result < 0 && lab_io_cancel::requested(state.options.cancel) { state.result = CANCELLED; }
    if state.result < 0 && clock_ns() >= state.deadline { state.result = TIMEOUT; }
    if state.result >= 0 { release(state); batch.done = true; batch.result = state.result; batch.progress = state.progress; return batch; }
    if state.scanning { scan(state, batch); }
    if state.result < 0 && !state.scanning {
        for i in state.slots.len {
            let slot .= state.slots[i];
            if slot.read.id == 0 { continue; }
            let contents = lab_fs_async_files::poll(slot.read);
            if contents.code != 0 { state.result = IO; break; }
            if !contents.done { continue; }
            lab_fs_async_files::close(slot.read); state.progress.active--;
            if contents.result != 0 { issue(state, batch, slot.path, if contents.result == lab_io_event_loop::LIMIT { LARGE } else { READ_ERROR }, contents.result); }
            else {
                var binary = false; for byte in contents.bytes { if byte == 0 { binary = true; break; } }
                if binary { issue(state, batch, slot.path, BINARY); }
                else if !lab_text_utf8::valid(contents.bytes) { issue(state, batch, slot.path, ENCODING); }
                else {
                    state.path = slot.path; state.data = copy(contents.bytes); state.cursor = lab_text_literal_search::Cursor {}; state.scanning = true;
                    state.position = 0; state.line = 1; state.column = 1; state.line_start = 0; break;
                }
            }
        }
    }
    if state.result < 0 && state.listing.id != 0 && batch.issues.len <= 0 {
        let page = lab_fs_async_files::poll(state.listing);
        if page.code != 0 { state.result = IO; }
        else {
            for entry in page.entries {
                state.progress.entries++;
                if state.progress.entries > state.options.max_paths { state.result = LIMIT; break; }
                let path = str(state.directory, if state.directory.len > 0 { "/" } else { "" }, entry.name);
                if !relative(path) { issue(state, batch, if state.directory.len > 0 { state.directory[..] } else { "." }, PATH); continue; }
                let directory = entry.kind == lab_fs_async_files::DIRECTORY;
                if excluded(state, path, directory) { continue; }
                if entry.kind == lab_fs_async_files::UNKNOWN { issue(state, batch, path, UNKNOWN); continue; }
                if !directory && entry.kind != lab_fs_async_files::FILE { continue; }
                if directory && state.depth >= state.options.max_depth { state.result = LIMIT; break; }
                if !directory && !lab_fs_glob::matches(state.include, path) { continue; }
                // Includes the root; never overflow the bounded task collection.
                if state.tasks.len == 4096 { state.result = LIMIT; break; }
                state.tasks.push(Task { kind: entry.kind, depth: state.depth + 1, path: path });
                if !directory { state.progress.files++; }
            }
            if page.done {
                lab_fs_async_files::close(state.listing);
                if page.result != 0 { state.result = if page.result == lab_io_event_loop::LIMIT { LIMIT } else { IO }; }
            }
        }
    }
    if state.result < 0 {
        if state.listing.id == 0 {
            while state.directory_at < state.tasks.len {
                let task = state.tasks[state.directory_at]; state.directory_at++;
                if task.kind != lab_fs_async_files::DIRECTORY { continue; }
                state.directory = task.path; state.depth = task.depth;
                state.listing = lab_fs_async_files::list(state.context, str(state.root, if task.path.len > 0 { "/" } else { "" }, task.path));
                if state.listing.code != 0 { state.result = IO; } break;
            }
        }
        for i in state.options.parallel {
            if state.result >= 0 { break; }
            if state.slots[i].read.id != 0 { continue; }
            while state.file_at < state.tasks.len {
                let task = state.tasks[state.file_at]; state.file_at++;
                if task.kind != lab_fs_async_files::FILE { continue; }
                state.slots[i].path = task.path;
                state.slots[i].read = lab_fs_async_files::read(state.context, str(state.root, "/", task.path), state.options.max_bytes);
                if state.slots[i].read.code != 0 { state.result = IO; } else { state.progress.active++; } break;
            }
        }
        if state.result < 0 && state.listing.id == 0 && state.directory_at == state.tasks.len && state.file_at == state.tasks.len && state.progress.active == 0 && !state.scanning { state.result = OK; }
    }
    if state.result >= 0 { release(state); batch.done = true; batch.result = state.result; }
    batch.progress = state.progress; batch
}
fn message(code: i32) -> const u8[:] { match code { 0 => "Search completed", 1 => "Invalid search arguments", 2 => "Unable to enumerate/read the search root", 3 => "Search limit reached; results are incomplete", 4 => "Search cancelled; results are incomplete", _ => "Search timed out; results are incomplete" } }
fn reason(code: i32) -> const u8[:] { match code { 1 => "Binary file", 2 => "File is not UTF-8", 3 => "File exceeds byte limit", 4 => "Unable to read file", 5 => "Unknown directory entry type", _ => "Unsupported path" } }
struct Opened { code: i32 = OK, error: u8[..512] = [], bytes: u8[] = [] }
// Compatibility entry point; portable project keys are shared with the explorer.
fn relative(path: const u8[:]) -> bool { lab_fs_path::relative(path) }
// Re-read before opening: stale byte positions must still identify this query.
fn open_hit(root: const u8[:], hit: const Hit&, query: const u8[:], options: Options = Options {}) -> Opened {
    let pattern = lab_text_literal_search::compile(query, options.ignore_case);
    if !relative(hit.path) || !pattern.valid || hit.start < 0 || hit.start > 2097152 || hit.end < hit.start || hit.end > 2097152 || hit.end - hit.start != query.len ||
        root.len < 1 || root.len > 512 || !lab_fs_async_files::valid_path(root) || options.timeout_ms < 1 || options.timeout_ms > 600000 || options.max_bytes < 0 || options.max_bytes > 2097152 { return Opened { code: INVALID, error: "Invalid search result" }; }
    for b in query { if b == 0 || b == '\n' || b == '\r' { return Opened { code: INVALID, error: "Invalid search result" }; } }
    var context = lab_io_event_loop::create(); if context.code != 0 { return Opened { code: IO, error: lab_io_event_loop::message(context.code) }; }
    let result = open_in(context, root, hit, pattern, options); lab_io_event_loop::close(context); result
}
fn open_in(context: const lab_io_event_loop::Context&, root: const u8[:], hit: const Hit&, pattern: const lab_text_literal_search::Pattern&, options: Options) -> Opened {
    let file = lab_fs_async_files::read(context, str(root, "/", hit.path), options.max_bytes);
    if file.code != 0 { return Opened { code: IO, error: lab_io_event_loop::message(file.code) }; }
    let deadline = clock_ns() + options.timeout_ms * 1000000;
    loop {
        if lab_io_cancel::requested(options.cancel) { return Opened { code: CANCELLED, error: "File read cancelled" }; }
        if clock_ns() >= deadline { return Opened { code: TIMEOUT, error: "File read timed out" }; }
        let code = lab_io_event_loop::wait(context, 20); if code != 0 { return Opened { code: IO, error: lab_io_event_loop::message(code) }; }
        let result = lab_fs_async_files::poll(file); if result.code != 0 { return Opened { code: IO, error: lab_io_event_loop::message(result.code) }; } if !result.done { continue; }
        if result.code != 0 || result.result != 0 { return Opened { code: IO, error: lab_io_event_loop::message(if result.code != 0 { result.code } else { result.result }) }; }
        if hit.end > result.bytes.len || !lab_text_utf8::valid(result.bytes) { return Opened { code: INVALID, error: "File changed since search; search again" }; }
        for i in pattern.bytes.len {
            if lab_text_literal_search::folded(pattern, result.bytes[hit.start + i]) != lab_text_literal_search::folded(pattern, pattern.bytes[i]) { return Opened { code: INVALID, error: "File changed since search; search again" }; }
        }
        for b in result.bytes { if b == 0 { return Opened { code: INVALID, error: "File is now binary; search again" }; } }
        return Opened { bytes: copy(result.bytes) };
    }
}
