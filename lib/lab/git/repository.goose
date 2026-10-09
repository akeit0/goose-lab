namespace lab_git_repository;
import std;
import lab.io.process;
import lab.text.diff;
import lab.text.utf8;
import lab.text.strings;
import lab.fs.files;
let OK: i32 = 0; let COMMAND: i32 = 1; let INVALID: i32 = 2; let LIMIT: i32 = 3;
struct File { path: u8[..512], status: u8 }
struct Files { code: i32 = OK, error: u8[..512] = [], items: File[..512] = [] }
struct Diff { code: i32 = OK, error: u8[..512] = [], untracked: bool = false, bytes: i64 = -1, patch: lab_text_diff::Patch = lab_text_diff::Patch {} }
struct Root { code: i32 = OK, error: u8[..512] = [], path: u8[..512] = [] }
fn root(repo: const u8[:], options: lab_io_process::Options = lab_io_process::Options {}) -> Root {
    let result = command(["--no-pager", "rev-parse", "--show-toplevel"], repo, options);
    if result.code != lab_io_process::OK || result.exit_code != 0 { return Root { code: COMMAND, error: failure(result) }; }
    var end = result.out.len;
    if end > 0 && result.out[end - 1] == '\n' { end--; }
    if end > 0 && result.out[end - 1] == '\r' { end--; }
    if end < 1 || end > 512 || !lab_text_strings::single_line(result.out[..end]) { return Root { code: INVALID, error: "Repository root must be a single-line UTF-8 path of at most 512 bytes" }; }
    Root { path: result.out[..end] }
}
// Resolved separately from the worktree: linked worktrees keep their index and
// shared HEAD/refs outside the directory being displayed.
struct WatchPaths { code: i32 = OK, git_dir: u8[..512] = [], common_dir: u8[..512] = [] }
fn watch_paths(repo: const u8[:], options: lab_io_process::Options = lab_io_process::Options {}) -> WatchPaths {
    let result = command(["--no-pager", "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir"], repo, options);
    if result.code != lab_io_process::OK || result.exit_code != 0 { return WatchPaths { code: COMMAND }; }
    var at: i64 = 0; var paths: u8[..512][..2] = [];
    while at < result.out.len {
        let first = at; while at < result.out.len && result.out[at] != '\n' { at++; }
        var end = at; if end > first && result.out[end - 1] == '\r' { end--; }
        if end == first || end - first > 512 || paths.len == 2 || !lab_text_strings::single_line(result.out[first..end]) { return WatchPaths { code: INVALID }; }
        paths.push(result.out[first..end]); at++;
    }
    if paths.len != 2 { return WatchPaths { code: INVALID }; }
    WatchPaths { git_dir: paths[0], common_dir: paths[1] }
}
fn index(files: const Files&, path: const u8[:]) -> i64 { for i in files.items.len { if files.items[i].path == path { return i; } } -1 }
fn parse_files(bytes: const u8[:]) -> Files {
    var files = Files {}; var at: i64 = 0;
    while at < bytes.len {
        let status = bytes[at];
        if at + 2 > bytes.len || bytes[at + 1] != 0 || (status != 'A' && status != 'M' && status != 'D' && status != 'T' && status != 'U') {
            return Files { code: INVALID, error: "Unsupported Git file status" };
        }
        at += 2; let start = at; while at < bytes.len && bytes[at] != 0 { at++; }
        if at == bytes.len || at == start || at - start > 512 || !lab_text_utf8::valid(bytes[start..at]) {
            return Files { code: INVALID, error: "Invalid Git path (expected UTF-8, at most 512 bytes)" };
        }
        if files.items.len == 512 { return Files { code: LIMIT, error: "This viewer accepts at most 512 changed files" }; }
        let path = bytes[start..at]; if index(files, path) >= 0 { return Files { code: INVALID, error: "Duplicate Git path" }; }
        files.items.push(File { path: path, status: status }); at++;
    } files
}
fn parse_untracked(bytes: const u8[:]) -> Files {
    var files = Files {}; var at: i64 = 0;
    while at < bytes.len {
        let start = at; while at < bytes.len && bytes[at] != 0 { at++; }
        if at == bytes.len || at == start || at - start > 512 || !lab_text_utf8::valid(bytes[start..at]) {
            return Files { code: INVALID, error: "Invalid untracked Git path (expected NUL-terminated UTF-8, at most 512 bytes)" };
        }
        if files.items.len == 512 { return Files { code: LIMIT, error: "This viewer accepts at most 512 changed files" }; }
        let path = bytes[start..at]; if index(files, path) >= 0 { return Files { code: INVALID, error: "Duplicate Git path" }; }
        files.items.push(File { path: path, status: '?' }); at++;
    } files
}
fn merge_files(tracked: const Files&, untracked: const Files&) -> Files {
    if tracked.code != OK { return tracked; } if untracked.code != OK { return untracked; }
    if tracked.items.len + untracked.items.len > 512 { return Files { code: LIMIT, error: "This viewer accepts at most 512 changed files" }; }
    var files = copy(tracked);
    for file in untracked.items {
        if index(files, file.path) >= 0 { return Files { code: INVALID, error: "Git file status changed during refresh; try Refresh again" }; }
        files.items.push(file);
    } files
}
fn command(arguments: const u8[:][:], repo: const u8[:], options: lab_io_process::Options) -> lab_io_process::Result {
    // argv is literal: no shell, pager, external diff, text conversion or pathspec magic.
    lab_io_process::run("git", arguments, repo, options)
}
fn failure(result: const lab_io_process::Result&) -> u8[>..] {
    if result.code != lab_io_process::OK { return str(lab_io_process::message(result.code)); }
    if !lab_text_utf8::valid(result.err) { return str("Git exited with ", result.exit_code, " (stderr is not UTF-8)"); }
    var end = min(result.err.len, 384);
    while end > 0 && end < result.err.len && (result.err[end] & 0xC0) == 0x80 { end--; }
    str("Git exited with ", result.exit_code, if result.err.len > 0 { ": " } else { "" }, result.err[..end])
}
fn files(repo: const u8[:], staged: bool, options: lab_io_process::Options = lab_io_process::Options {}) -> Files {
    var argv: const u8[:][..32] = ["-c", "core.quotePath=false", "--no-pager", "--literal-pathspecs", "diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--no-relative", "--ignore-submodules=none", "--no-color", "--name-status", "-z"];
    if staged { argv.push("--cached"); } argv.push("--");
    let result = command(argv, repo, options);
    if result.code != lab_io_process::OK || result.exit_code != 0 { return Files { code: COMMAND, error: failure(result) }; }
    let tracked = parse_files(result.out); if staged || tracked.code != OK { return tracked; }
    let other = command(["--no-pager", "ls-files", "--others", "--exclude-standard", "--full-name", "-z", "--"], repo, options);
    if other.code != lab_io_process::OK || other.exit_code != 0 { return Files { code: COMMAND, error: failure(other) }; }
    let untracked = parse_untracked(other.out); merge_files(tracked, untracked)
}
// no-index compares a regular worktree file to /dev/null without changing Git's index.
// Metadata bounds the observed input size; subprocess output/time remain bounded
// even if a writer changes that file between the observation and Git's read.
fn untracked(repo: const u8[:], path: const u8[:], options: lab_io_process::Options = lab_io_process::Options {}) -> Diff {
    if path.len == 0 || path.len > 512 || !lab_io_process::valid(path) || path[0] == '/' || path[0] == '\\' { return Diff { code: INVALID, error: "Expected a repository-relative file path" }; }
    var part: i64 = 0;
    for i in path.len {
        if path[i] == ':' { return Diff { code: INVALID, error: "Expected a portable repository-relative file path" }; }
        if path[i] == '/' || path[i] == '\\' {
            if path[part..i] == ".." { return Diff { code: INVALID, error: "File path must stay within the repository" }; } part = i + 1;
        }
    }
    if path[part..] == ".." { return Diff { code: INVALID, error: "File path must stay within the repository" }; }
    let info = lab_fs_files::info(str(repo, "/", path));
    if info.code != lab_fs_files::OK { return Diff { code: if info.code == lab_fs_files::LIMIT { LIMIT } else { INVALID }, error: lab_fs_files::message(info.code), untracked: true }; }
    if info.size > 2097152 { return Diff { code: LIMIT, error: "Untracked file exceeds the 2 MiB preview limit", untracked: true, bytes: info.size }; }
    let argv: const u8[:][18] = ["-c", "core.quotePath=false", "--no-pager", "diff", "--no-index", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames", "--no-relative", "--unified=3", "--word-diff=none", "--line-prefix=", "--src-prefix=a/", "--dst-prefix=b/", "--", "/dev/null", path];
    let result = command(argv, repo, options);
    // --no-index implies --exit-code: 1 means differences, not a process failure.
    if result.code != lab_io_process::OK || (result.exit_code != 0 && result.exit_code != 1) { return Diff { code: COMMAND, error: failure(result), untracked: true, bytes: info.size }; }
    let patch = lab_text_diff::decode(result.out);
    if patch.code != lab_text_diff::OK { return Diff { code: INVALID, error: lab_text_diff::message(patch.code), untracked: true, bytes: info.size }; }
    Diff { untracked: true, bytes: info.size, patch: patch }
}
fn diff(repo: const u8[:], path: const u8[:], staged: bool, options: lab_io_process::Options = lab_io_process::Options {}) -> Diff {
    if path.len == 0 || path.len > 512 || !lab_io_process::valid(path) { return Diff { code: INVALID, error: "Invalid Git path" }; }
    var argv: const u8[:][..32] = ["-c", "core.quotePath=false", "--no-pager", "--literal-pathspecs", "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames", "--no-relative", "--submodule=short", "--ignore-submodules=none", "--unified=3", "--word-diff=none", "--line-prefix="];
    if staged { argv.push("--cached"); } argv.push("--"); argv.push(path);
    let result = command(argv, repo, options);
    if result.code != lab_io_process::OK || result.exit_code != 0 { return Diff { code: COMMAND, error: failure(result) }; }
    let patch = lab_text_diff::decode(result.out);
    if patch.code != lab_text_diff::OK { return Diff { code: INVALID, error: lab_text_diff::message(patch.code) }; }
    Diff { patch: patch }
}
// Escape display controls, preserving the actual byte-exact path for Git calls.
fn display(path: const u8[:], limit: i64 = 507) -> u8[>..] {
    assert(limit >= 3);
    var output: u8[>..] = []; var at: i64 = 0;
    while at < path.len {
        let cp, next, ok = lab_text_utf8::decode(path, at); assert(ok);
        let piece: u8[>..] = if cp == 9 { "\\t" } else if cp == 10 { "\\n" } else if cp == 13 { "\\r" }
            else if cp < 32 || (cp >= 127 && cp <= 159) || cp == 0x2028 || cp == 0x2029 {
                let hex: const u8[:] = "0123456789abcdef";
                let escaped: u8[6] = ['\\', 'u', hex[(cp >> 12) & 15], hex[(cp >> 8) & 15], hex[(cp >> 4) & 15], hex[cp & 15]];
                escaped[..]
            } else { path[at..next] };
        if output.len + piece.len > limit - 3 { output.append("…"); break; } output.append(piece); at = next;
    } output
}
