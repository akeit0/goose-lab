// Surgical top-level object edits. Borrow input while parsing; own output.
namespace lab_json_edit;
import std;
import lab.json.codec;
import lab.text.utf8;
let OK: i32 = 0; let SOURCE: i32 = 1; let VALUE: i32 = 2; let NOT_OBJECT: i32 = 3;
let AMBIGUOUS: i32 = 4; let KEY: i32 = 5; let LIMIT: i32 = 6;
struct Match { code: i32 = OK, index: i64 = -1 }
struct Edited { code: i32 = OK, error: lab_json_codec::Error = lab_json_codec::Error {}, changed: bool = false, bytes: u8[>..] = [] }
// Missing is index -1 with OK; duplicate decoded matches are an error.
fn find(doc: const lab_json_codec::Document&, key: const u8[:]) -> Match {
    if doc.error.code != 0 { return Match { code: SOURCE }; }
    if !lab_text_utf8::valid(key) { return Match { code: KEY }; }
    let root = lab_json_codec::root(doc);
    if lab_json_codec::kind(root) != lab_json_codec::OBJECT { return Match { code: NOT_OBJECT }; }
    var found = Match {}; var at = root.index + 1; let end = doc.tokens[root.index].next;
    while at < end {
        let name, ok = lab_json_codec::text(lab_json_codec::Value { doc, at }); assert(ok);
        if name == key { if found.index >= 0 { return Match { code: AMBIGUOUS }; } found.index = at + 1; }
        at = doc.tokens[at + 1].next;
    } found
}
fn limited(error: lab_json_codec::Error) -> bool {
    error.code == lab_json_codec::BYTE_LIMIT || error.code == lab_json_codec::TOKEN_LIMIT || error.code == lab_json_codec::DEPTH_LIMIT
}
// value is a complete JSON fragment, not an unquoted string. No output on failure.
fn set(source: const u8[:], key: const u8[:], value: const u8[:], limits: lab_json_codec::Limits = lab_json_codec::Limits {}) -> Edited {
    let doc = lab_json_codec::parse(source, limits);
    if doc.error.code != 0 { return Edited { code: if limited(doc.error) { LIMIT } else { SOURCE }, error: doc.error }; }
    let selected = find(doc, key); if selected.code != OK { return Edited { code: selected.code }; }
    let fragment = lab_json_codec::parse(value, limits);
    if fragment.error.code != 0 { return Edited { code: if limited(fragment.error) { LIMIT } else { VALUE }, error: fragment.error }; }
    var insertion: u8[>..] = []; var begin: i64 = 0; var end: i64 = 0;
    if selected.index >= 0 {
        let token = doc.tokens[selected.index]; begin = token.start; end = token.end;
        if source[begin..end] == value { var unchanged: u8[>..] = []; unchanged.append(source); return Edited { bytes: unchanged }; }
        insertion.append(value);
    } else {
        let root = lab_json_codec::root(doc); begin = doc.tokens[root.index].end - 1; end = begin;
        var writer = lab_json_codec::Writer { limit: limits.bytes }; lab_json_codec::write_string(writer, key);
        let encoded, ok = lab_json_codec::finish(writer);
        if !ok { return Edited { code: LIMIT, error: lab_json_codec::Error { writer.error, 0 } }; }
        if lab_json_codec::count(root) > 0 { insertion.push(','); }
        insertion.append(encoded); insertion.push(':');
        if value.len > limits.bytes - insertion.len { return Edited { code: LIMIT, error: lab_json_codec::Error { lab_json_codec::BYTE_LIMIT, 0 } }; }
        insertion.append(value);
    }
    if insertion.len > limits.bytes - (source.len - (end - begin)) {
        return Edited { code: LIMIT, error: lab_json_codec::Error { lab_json_codec::BYTE_LIMIT, begin } };
    }
    var output: u8[>..] = []; output.append(source[..begin]); output.append(insertion); output.append(source[end..]);
    // Combined token/depth limits can fail even when both inputs passed separately.
    let checked = lab_json_codec::parse(output, limits);
    if checked.error.code != 0 { return Edited { code: if limited(checked.error) { LIMIT } else { SOURCE }, error: checked.error }; }
    Edited { changed: true, bytes: output }
}
fn message(code: i32) -> const u8[:] {
    match code { 0 => "JSON edit ready", 1 => "Source is not valid JSON", 2 => "Value is not valid JSON",
        3 => "Settings root must be an object", 4 => "Duplicate matching keys are ambiguous",
        5 => "Key is not valid UTF-8", 6 => "JSON edit exceeds a size or complexity limit", _ => "JSON edit failed" }
}
