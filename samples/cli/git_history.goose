import std;
import os;
import lab.git.repository;
import lab.git.history;
import lab.json.codec;
import lab.io.console;
extern "exit" fn finish(code: i32);
fn fail(message: const u8[:]) { write_stderr(str(message, "\n")); finish(1); }
fn commit(repo: const u8[:], id: const u8[:]) -> lab_git_history::Commit {
    let page = lab_git_history::page(repo, id, 0, 1); if page.code != 0 { fail(page.error); }
    if page.items.len == 0 { fail("Commit is missing"); } page.items[0]
}
fn main() {
    if !lab_io_console::binary_output() { fail("Unable to configure byte output"); }
    let argv = args();
    if argv.len < 3 { write_stderr("Usage: git_history REPOSITORY list [ANCHOR OFFSET COUNT] | files COMMIT | diff COMMIT PATH | blob COMMIT PATH\n"); finish(2); }
    let repo = lab_git_repository::root(argv[1]); if repo.code != 0 { fail(repo.error); }
    if argv[2] == "list" && (argv.len == 3 || argv.len == 6) {
        var anchor: u8[..64] = []; var offset: i64 = 0; var count: i64 = 32;
        if argv.len == 6 {
            if !lab_git_history::oid(argv[3]) { fail("Expected a full commit object ID"); } anchor = argv[3];
            let n, ok = parse_int(argv[4]); let c, good = parse_int(argv[5]); if !ok || !good { fail("Invalid page numbers"); } offset = n; count = c;
        }
        let page = lab_git_history::page(repo.path, anchor, offset, count); if page.code != 0 { fail(page.error); }
        var w = lab_json_codec::Writer {};
        lab_json_codec::begin_object(w); lab_json_codec::key(w, "anchor"); lab_json_codec::write_string(w, page.anchor);
        lab_json_codec::key(w, "offset"); lab_json_codec::write_integer(w, page.offset); lab_json_codec::key(w, "more"); lab_json_codec::write_bool(w, page.more);
        lab_json_codec::key(w, "commits"); lab_json_codec::begin_array(w);
        for item in page.items {
            lab_json_codec::begin_object(w); lab_json_codec::key(w, "id"); lab_json_codec::write_string(w, item.id);
            lab_json_codec::key(w, "parent"); lab_json_codec::write_string(w, item.parent); lab_json_codec::key(w, "parents"); lab_json_codec::write_integer(w, item.parents);
            lab_json_codec::key(w, "author"); lab_json_codec::write_string(w, item.author); lab_json_codec::key(w, "date"); lab_json_codec::write_string(w, item.date);
            lab_json_codec::key(w, "subject"); lab_json_codec::write_string(w, item.subject); lab_json_codec::end(w);
        }
        lab_json_codec::end(w); lab_json_codec::end(w); let out, ok = lab_json_codec::finish(w); if !ok { fail("JSON output exceeds its limit; use a smaller page"); } write_stdout(str(out, "\n"));
    } else if argv[2] == "files" && argv.len == 4 {
        let selected = commit(repo.path, argv[3]); let files = lab_git_history::files(repo.path, selected); if files.code != 0 { fail(files.error); }
        var w = lab_json_codec::Writer {}; lab_json_codec::begin_array(w);
        for file in files.items {
            lab_json_codec::begin_object(w); lab_json_codec::key(w, "path"); lab_json_codec::write_string(w, file.path);
            let status: u8[1] = [file.status]; lab_json_codec::key(w, "status"); lab_json_codec::write_string(w, status); lab_json_codec::end(w);
        }
        lab_json_codec::end(w); let out, ok = lab_json_codec::finish(w); if !ok { fail("File listing exceeds JSON output limit"); } write_stdout(str(out, "\n"));
    } else if argv[2] == "diff" && argv.len == 5 {
        let selected = commit(repo.path, argv[3]); let diff = lab_git_history::diff(repo.path, selected, argv[4]); if diff.code != 0 { fail(diff.error); } write_stdout(diff.patch.source);
    } else if argv[2] == "blob" && argv.len == 5 {
        let blob = lab_git_history::blob(repo.path, argv[3], argv[4]); if blob.code != 0 { fail(blob.error); } write_stdout(blob.object.bytes);
    } else { write_stderr("Invalid git_history arguments\n"); finish(2); }
}
