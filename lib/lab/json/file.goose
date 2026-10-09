// Bounded reads and validated atomic writes. Returned bytes own their storage;
// JSON documents borrow those bytes only within the caller's scope.
namespace lab_json_file;
import std;
import os;
import lab.json.codec;
let OK: i32 = 0; let MISSING: i32 = 1; let IO: i32 = 2;
let LIMIT: i32 = 3; let INVALID_PATH: i32 = 4; let INVALID_JSON: i32 = 5;
let MAX_BYTES: i64 = 2097152;
struct Loaded { code: i32, data: u8[>..] = [] }
extern "glab_goose_file_read" fn read_raw(path: const u8[:], out: u8[:], count: i64&) -> i32;
fn validate(bytes: const u8[:], limit: i64) -> i32 {
    if limit < 1 || limit > MAX_BYTES || bytes.len > limit { return LIMIT; }
    let doc = lab_json_codec::parse(bytes, lab_json_codec::Limits { bytes: limit });
    if doc.error.code == lab_json_codec::OK { OK }
    else if doc.error.code == lab_json_codec::BYTE_LIMIT || doc.error.code == lab_json_codec::TOKEN_LIMIT || doc.error.code == lab_json_codec::DEPTH_LIMIT { LIMIT }
    else { INVALID_JSON }
}
fn load(path: const u8[:], limit: i64 = 1048576) -> Loaded {
    if limit < 1 || limit > MAX_BYTES { return Loaded { code: LIMIT }; }
    var bytes: u8[>..] = []; bytes.resize(limit, 0); var count: i64 = 0;
    let code = read_raw(path, bytes, count); if code != OK { return Loaded { code: code }; }
    bytes.resize(count); let validated = validate(bytes, limit);
    if validated != OK { return Loaded { code: validated }; }
    Loaded { code: OK, data: bytes }
}
fn save(path: const u8[:], bytes: const u8[:], limit: i64 = 1048576) -> i32 {
    if path.len == 0 || path.len > 32768 { return INVALID_PATH; }
    for c in path { if c == 0 { return INVALID_PATH; } }
    let code = validate(bytes, limit); if code != OK { return code; }
    if write_file_atomic(path, bytes) { OK } else { IO }
}
fn message(code: i32) -> const u8[:] {
    match code { 0 => "File saved", 1 => "No saved file", 2 => "Unable to read or write the JSON file",
        3 => "JSON exceeds a size or complexity limit", 4 => "Invalid file path", 5 => "File is not valid JSON",
        _ => "Invalid JSON file" }
}
