import std;
import os;
import lab.fs.search;
import lab.json.codec;
import lab.io.console;
import lab.text.strings;
extern "exit" fn finish(code: i32);
fn main() {
    if !lab_io_console::binary_output() { write_stderr("Unable to configure byte output\n"); finish(1); }
    let argv = args(); var options = lab_fs_search::Options {}; var at: i64 = 1; var cancel_after: i64 = -1;
    while at < argv.len && starts_with(argv[at], "--") {
        if argv[at] == "--" { at++; break; }
        if argv[at] == "--ignore-case" { options.ignore_case = true; at++; continue; }
        if at + 1 >= argv.len { write_stderr("Missing option value\n"); finish(2); }
        let name = argv[at]; let value = argv[at + 1];
        if name == "--include" || name == "--exclude" {
            if value.len > 256 { write_stderr("Glob exceeds 256 bytes\n"); finish(2); }
            if name == "--include" { options.include = value; }
            else { if options.exclude.len == 16 { write_stderr("Too many exclusions\n"); finish(2); } options.exclude.push(value); }
        } else {
            let n, ok = parse_int(value); if !ok || n < 0 { write_stderr("Options require nonnegative integers\n"); finish(2); }
            if name == "--parallel" { options.parallel = n; } else if name == "--max-matches" { options.max_matches = n; }
            else if name == "--max-bytes" { options.max_bytes = n; } else if name == "--max-paths" { options.max_paths = n; }
            else if name == "--max-depth" { options.max_depth = n; }
            else if name == "--timeout" { options.timeout_ms = n; } else if name == "--cancel-after" { cancel_after = n; }
            else { write_stderr("Unknown search option\n"); finish(2); }
        } at += 2;
    }
    if argv.len - at != 2 { write_stderr("Usage: find_files [--ignore-case] [--include GLOB] [--exclude GLOB] [--parallel N] [--max-matches N] [--max-bytes N] [--max-paths N] [--max-depth N] [--timeout MS] [--cancel-after MS] -- ROOT QUERY\n"); finish(2); }
    var search = lab_fs_search::start(argv[at], argv[at + 1], options);
    if search.code != 0 { write_stderr(str(lab_fs_search::message(search.code), "\n")); finish(2); }
    let begun = clock_ns();
    loop {
        if cancel_after >= 0 && (clock_ns() - begun) / 1000000 >= cancel_after { lab_fs_search::cancel(search); }
        let batch = lab_fs_search::poll(search, 20);
        if batch.code != 0 { lab_fs_search::close(search); write_stderr("Search loop failed\n"); finish(1); }
        for hit in batch.hits {
            var w = lab_json_codec::Writer {}; lab_json_codec::begin_object(w);
            lab_json_codec::key(w, "path"); lab_json_codec::write_string(w, hit.path); lab_json_codec::key(w, "line"); lab_json_codec::write_integer(w, hit.line);
            lab_json_codec::key(w, "column"); lab_json_codec::write_integer(w, hit.column); lab_json_codec::key(w, "start"); lab_json_codec::write_integer(w, hit.start);
            lab_json_codec::key(w, "end"); lab_json_codec::write_integer(w, hit.end); lab_json_codec::key(w, "preview"); lab_json_codec::write_string(w, hit.preview);
            lab_json_codec::end(w); let line, ok = lab_json_codec::finish(w); assert(ok); write_stdout(str(line, "\n"));
        }
        for issue in batch.issues { write_stderr(str(lab_fs_search::reason(issue.reason), ": ", lab_text_strings::display_bytes(issue.path), "\n")); }
        flush_stdout();
        if batch.done {
            lab_fs_search::close(search);
            write_stderr(str(lab_fs_search::message(batch.result), " · ", batch.progress.matches, " matches · ", batch.progress.searched, " searched · ", batch.progress.skipped, " skipped\n"));
            finish(if batch.result == lab_fs_search::OK && batch.progress.skipped == 0 { 0 } else { 1 });
        }
    }
}
