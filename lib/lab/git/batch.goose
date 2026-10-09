// Decoder for unmodified `git cat-file --batch -Z`. Raw, size-framed bodies.
namespace lab_git_batch;
import std;
import lab.collections.byte_buffer;
let OK: i32 = 0; let PROTOCOL: i32 = 1; let LIMIT: i32 = 2; let TRUNCATED: i32 = 3;
let FOUND: i32 = 0; let MISSING: i32 = 1; let AMBIGUOUS: i32 = 2; let EXCLUDED: i32 = 3; let SUBMODULE: i32 = 4;
struct Object {
    ready: bool = false, code: i32 = OK, status: i32 = FOUND, name: u8[..8192] = [],
    kind: u8[..8] = [], size: i64 = 0, bytes: u8[] = []
}
struct Decoder {
    max_bytes: i64 = 2097152, code: i32 = OK, ended: bool = false,
    expected: i64 = -1, name: u8[..64] = [], kind: u8[..8] = [],
    buffer: lab_collections_byte_buffer::Buffer = lab_collections_byte_buffer::Buffer { limit: 2109440 }
}
fn append(decoder: Decoder&, bytes: const u8[:]) -> bool {
    if decoder.code != OK || decoder.ended { return false; }
    if !lab_collections_byte_buffer::append(decoder.buffer, bytes) { decoder.code = LIMIT; return false; } true
}
fn next(decoder: Decoder&) -> Object {
    if decoder.code != OK { return Object { code: decoder.code }; }
    if decoder.expected < 0 {
        let end = lab_collections_byte_buffer::delimiter(decoder.buffer, 0);
        if end < 0 { if lab_collections_byte_buffer::available(decoder.buffer) > 8192 { decoder.code = LIMIT; } return Object { code: decoder.code }; }
        if end > 8192 { decoder.code = LIMIT; return Object { code: LIMIT }; }
        let header = lab_collections_byte_buffer::take(decoder.buffer, end); assert(lab_collections_byte_buffer::consume(decoder.buffer, 1));
        let suffixes: const u8[:][4] = [" missing", " ambiguous", " excluded", " submodule"];
        for i in 4 {
            let suffix = suffixes[i];
            if header.len > suffix.len && header[header.len - suffix.len..] == suffix {
                return Object { ready: true, status: i as i32 + 1, name: header[..header.len - suffix.len] };
            }
        }
        var space: i64 = 0; while space < header.len && header[space] != ' ' { space++; }
        if (space != 40 && space != 64) || space >= header.len { decoder.code = PROTOCOL; return Object { code: PROTOCOL }; }
        for byte in header[..space] {
            if !((byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f')) { decoder.code = PROTOCOL; return Object { code: PROTOCOL }; }
        }
        let begin = space + 1; space = begin; while space < header.len && header[space] != ' ' { space++; }
        let kind = header[begin..space];
        if (kind != "blob" && kind != "commit" && kind != "tree" && kind != "tag") || space + 1 >= header.len { decoder.code = PROTOCOL; return Object { code: PROTOCOL }; }
        let number = header[space + 1..]; for byte in number { if byte < '0' || byte > '9' { decoder.code = PROTOCOL; return Object { code: PROTOCOL }; } }
        let count, ok = parse_int(number);
        if !ok || count < 0 || decoder.max_bytes < 0 || count > decoder.max_bytes { decoder.code = LIMIT; return Object { code: LIMIT }; }
        decoder.name = header[..begin - 1]; decoder.kind = kind; decoder.expected = count;
    }
    if decoder.expected >= lab_collections_byte_buffer::available(decoder.buffer) { return Object {}; }
    let bytes = lab_collections_byte_buffer::take(decoder.buffer, decoder.expected);
    if lab_collections_byte_buffer::first(decoder.buffer) != 0 { decoder.code = PROTOCOL; return Object { code: PROTOCOL }; }
    assert(lab_collections_byte_buffer::consume(decoder.buffer, 1));
    let object = Object { ready: true, name: decoder.name, kind: decoder.kind, size: decoder.expected, bytes: copy(bytes) };
    decoder.expected = -1; decoder.name.resize(0); decoder.kind.resize(0); object
}
// Call after draining next() and stdout EOF/process completion. Sticky failure.
fn finish(decoder: Decoder&) -> i32 {
    decoder.ended = true;
    if decoder.code == OK && (decoder.expected >= 0 || lab_collections_byte_buffer::available(decoder.buffer) > 0) { decoder.code = TRUNCATED; }
    decoder.code
}
fn message(code: i32) -> const u8[:] { match code { 0 => "Git batch ready", 1 => "Invalid Git batch framing", 2 => "Git batch exceeds a limit", _ => "Incomplete Git batch response" } }
fn status_name(status: i32) -> const u8[:] { match status { 0 => "found", 1 => "missing", 2 => "ambiguous", 3 => "excluded", _ => "submodule" } }
