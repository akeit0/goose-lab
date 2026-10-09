// Metadata is an observation, not an open handle or a guarantee about a later read.
namespace lab_fs_files;
import std;
import lab.text.utf8;
let OK: i32 = 0; let MISSING: i32 = 1; let IO: i32 = 2;
let LIMIT: i32 = 3; let INVALID_PATH: i32 = 4; let NOT_REGULAR: i32 = 6;
struct Info { code: i32, size: i64 = 0 }
struct Revision { code: i32, size: i64 = 0, digest: u64 = 0 }
extern "glab_goose_file_info" fn info_raw(path: const u8[:], size: i64&) -> i32;
extern "glab_goose_file_revision" fn revision_raw(path: const u8[:], size: i64&, digest: u64&) -> i32;
fn digest(bytes: const u8[:]) -> u64 {
    var hash: u64 = 14695981039346656037; for byte in bytes { hash = (hash ^ byte) * 1099511628211; } hash
}
fn revision(path: const u8[:]) -> Revision {
    if path.len == 0 || path.len > 32768 || !lab_text_utf8::valid(path) { return Revision { code: INVALID_PATH }; }
    for byte in path { if byte == 0 { return Revision { code: INVALID_PATH }; } }
    var size: i64 = 0; var hash: u64 = 0; let code = revision_raw(path, size, hash);
    if code != OK { return Revision { code: code }; } Revision { code, size, hash }
}
fn info(path: const u8[:]) -> Info {
    if path.len == 0 || path.len > 32768 || !lab_text_utf8::valid(path) { return Info { code: INVALID_PATH }; }
    for c in path { if c == 0 { return Info { code: INVALID_PATH }; } }
    var size: i64 = 0; let code = info_raw(path, size); Info { code, size }
}
fn message(code: i32) -> const u8[:] {
    match code { 0 => "Regular file", 1 => "File no longer exists; refresh the file list", 2 => "Unable to inspect the file",
        3 => "File size exceeds the supported range", 4 => "Invalid file path", _ => "Preview supports regular files only; links and directories are excluded" }
}
