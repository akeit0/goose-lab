// Lexical absolute names; preserves case, does not resolve links or prove identity.
namespace lab_fs_path;
import std;
import lab.text.utf8;
let OK: i32 = 0; let INVALID: i32 = 4; let LIMIT: i32 = 3; let IO: i32 = 2;
struct Result { code: i32 = OK, bytes: u8[] = [] }
extern "glab_goose_path_absolute" fn absolute_raw(path: const u8[:], out: u8[:], length: i64&) -> i32;
// Portable project key, not a security boundary (links can leave a project root).
fn relative(path: const u8[:]) -> bool {
    if path.len < 1 || path.len > 512 || !lab_text_utf8::valid(path) || path[0] == '/' { return false; }
    var first: i64 = 0;
    for i in path.len {
        if path[i] == 0 || path[i] == '\\' || path[i] == ':' { return false; }
        if path[i] == '/' { if path[first..i] == ".." || path[first..i] == "." || i == first { return false; } first = i + 1; }
    } path[first..] != ".." && path[first..] != "." && first < path.len
}
fn absolute(path: const u8[:], limit: i64 = 32768) -> Result {
    if path.len == 0 || path.len > 32768 || !lab_text_utf8::valid(path) || limit < 1 || limit > 32768 { return Result { code: INVALID }; }
    for byte in path { if byte == 0 { return Result { code: INVALID }; } }
    var bytes: u8[>..] = []; bytes.resize(limit, 0); var length: i64 = 0;
    let code = absolute_raw(path, bytes, length); Result { code: code, bytes: if code == 0 { bytes[..length] } else { [] } }
}
