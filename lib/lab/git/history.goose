// Owned first-parent history pages anchored to a full object ID. No GUI dependency.
namespace lab_git_history;
import std;
import lab.git.repository;
import lab.git.object;
import lab.git.batch;
import lab.io.process;
import lab.text.utf8;
import lab.text.strings;
import lab.text.diff;
struct Commit { id: u8[..64] = [], parent: u8[..64] = [], parents: i64 = 0, author: u8[..512] = [], date: u8[..64] = [], subject: u8[..1024] = [] }
struct Page { code: i32 = lab_git_repository::OK, error: u8[..512] = [], anchor: u8[..64] = [], offset: i64 = 0, more: bool = false, items: Commit[..65] = [] }
fn oid(bytes: const u8[:]) -> bool {
    if bytes.len != 40 && bytes.len != 64 { return false; }
    for b in bytes { if !((b >= '0' && b <= '9') || (b >= 'a' && b <= 'f')) { return false; } } true
}
fn parse(bytes: const u8[:]) -> Page {
    var page = Page {}; var at: i64 = 0;
    while at < bytes.len {
        var fields: const u8[:][..5] = [];
        for i in 5 {
            let first = at; while at < bytes.len && bytes[at] != 0 { at++; }
            if at == bytes.len { return Page { code: lab_git_repository::INVALID, error: "Incomplete history record" }; }
            fields.push(bytes[first..at]); at++;
        }
        if !oid(fields[0]) || fields[2].len > 512 || fields[3].len > 64 || fields[4].len > 1024 {
            return Page { code: lab_git_repository::INVALID, error: "Invalid or oversized history metadata" };
        }
        if !lab_text_utf8::valid(fields[2]) || !lab_text_strings::single_line(fields[3]) || !lab_text_utf8::valid(fields[4]) { return Page { code: lab_git_repository::INVALID, error: "Invalid history text or date" }; }
        var commit = Commit { id: fields[0], author: fields[2], date: fields[3], subject: fields[4] };
        var start: i64 = 0;
        while start < fields[1].len {
            var end = start; while end < fields[1].len && fields[1][end] != ' ' { end++; }
            if !oid(fields[1][start..end]) || end - start != commit.id.len { return Page { code: lab_git_repository::INVALID, error: "Invalid parent object ID" }; }
            if commit.parents == 0 { commit.parent = fields[1][start..end]; } commit.parents++; start = end + 1;
            if end < fields[1].len && start == fields[1].len { return Page { code: lab_git_repository::INVALID, error: "Incomplete parent list" }; }
        }
        for previous in page.items { if previous.id == commit.id { return Page { code: lab_git_repository::INVALID, error: "Duplicate history object ID" }; } }
        if page.items.len == 65 { return Page { code: lab_git_repository::LIMIT, error: "History page exceeds 65 records" }; }
        page.items.push(commit);
    } page
}
fn page(repo: const u8[:], anchor: const u8[:] = "", offset: i64 = 0, count: i64 = 32, options: lab_io_process::Options = lab_io_process::Options {}) -> Page {
    if (anchor.len > 0 && !oid(anchor)) || offset < 0 || offset > 1000000 || count < 1 || count > 64 { return Page { code: lab_git_repository::INVALID, error: "Invalid history page arguments" }; }
    var head: u8[..64] = anchor;
    if head.len == 0 {
        let result = lab_git_repository::command(["--no-replace-objects", "--no-pager", "rev-parse", "--verify", "--quiet", "HEAD^{commit}"], repo, options);
        if result.code == 0 && result.exit_code == 1 { return Page {}; } // Unborn HEAD.
        if result.code != 0 || result.exit_code != 0 { return Page { code: lab_git_repository::COMMAND, error: lab_git_repository::failure(result) }; }
        let value = trim(result.out); if !oid(value) { return Page { code: lab_git_repository::INVALID, error: "Invalid history anchor" }; } head = value;
    }
    let skip = str("--skip=", offset); let take = str("--max-count=", count + 1);
    let argv: const u8[:][14] = ["--no-replace-objects", "--no-pager", "log", "--first-parent", "--no-show-signature", "--no-notes", "--no-decorate", "--encoding=UTF-8", "-z", "--format=%H%x00%P%x00%an%x00%aI%x00%s", skip, take, head, "--"];
    let result = lab_git_repository::command(argv, repo, options);
    if result.code != 0 || result.exit_code != 0 { return Page { code: lab_git_repository::COMMAND, error: lab_git_repository::failure(result) }; }
    var output = parse(result.out); if output.code != 0 { return output; }
    output.anchor = head; output.offset = offset; output.more = output.items.len > count;
    if output.more { output.items.pop(); } output
}
fn valid(commit: const Commit&) -> bool { oid(commit.id) && (commit.parent.len == 0 || (oid(commit.parent) && commit.parent.len == commit.id.len)) }
fn arguments(commit: const Commit&, patch: bool) -> const u8[:][>..] {
    var argv: const u8[:][>..] = ["--no-replace-objects", "-c", "core.quotePath=false", "--no-pager", "--literal-pathspecs"];
    if commit.parent.len > 0 { argv.push("diff"); } else { argv.append(["diff-tree", "--root", "--no-commit-id", "-r"]); }
    argv.append(["--no-ext-diff", "--no-textconv", "--no-renames", "--no-relative", "--ignore-submodules=none", "--no-color"]);
    if patch { argv.append(["-p", "--submodule=short", "--unified=3", "--word-diff=none", "--line-prefix=", "--src-prefix=a/", "--dst-prefix=b/"]); }
    else { argv.append(["--name-status", "-z"]); }
    if commit.parent.len > 0 { argv.push(commit.parent); } argv.push(commit.id); argv.push("--"); argv
}
fn files(repo: const u8[:], commit: const Commit&, options: lab_io_process::Options = lab_io_process::Options {}) -> lab_git_repository::Files {
    if !valid(commit) { return lab_git_repository::Files { code: lab_git_repository::INVALID, error: "Invalid commit IDs" }; }
    let result = lab_git_repository::command(arguments(commit, false), repo, options);
    if result.code != 0 || result.exit_code != 0 { return lab_git_repository::Files { code: lab_git_repository::COMMAND, error: lab_git_repository::failure(result) }; }
    lab_git_repository::parse_files(result.out)
}
fn diff(repo: const u8[:], commit: const Commit&, path: const u8[:], options: lab_io_process::Options = lab_io_process::Options {}) -> lab_git_repository::Diff {
    if !valid(commit) || path.len < 1 || path.len > 512 || !lab_io_process::valid(path) { return lab_git_repository::Diff { code: lab_git_repository::INVALID, error: "Invalid history diff arguments" }; }
    var argv = arguments(commit, true); argv.push(path);
    let result = lab_git_repository::command(argv, repo, options);
    if result.code != 0 || result.exit_code != 0 { return lab_git_repository::Diff { code: lab_git_repository::COMMAND, error: lab_git_repository::failure(result) }; }
    let patch = lab_text_diff::decode(result.out);
    if patch.code != 0 { return lab_git_repository::Diff { code: lab_git_repository::INVALID, error: lab_text_diff::message(patch.code) }; }
    lab_git_repository::Diff { patch: patch }
}
fn blob(repo: const u8[:], id: const u8[:], path: const u8[:], options: lab_io_process::Options = lab_io_process::Options {}) -> lab_git_object::Result {
    if !oid(id) || path.len < 1 || path.len > 512 || !lab_io_process::valid(path) { return lab_git_object::Result { code: lab_git_repository::INVALID, error: "Invalid commit file arguments" }; }
    let result = lab_git_object::read(repo, str(id, ":", path), options);
    if result.code != 0 { return result; }
    if result.object.status != lab_git_batch::FOUND { return lab_git_object::Result { code: lab_git_repository::INVALID, error: "File is absent at this commit (it may have been deleted)" }; }
    if result.object.kind != "blob" { return lab_git_object::Result { code: lab_git_repository::INVALID, error: "Selected entry is not a file blob" }; } result
}
