// Borrow input; own a preorder token tape. No per-node allocation or native ABI.
namespace lab_json_codec;
import std;
import math;
import lab.text.utf8;
let OK: i32 = 0; let SYNTAX: i32 = 1; let UNICODE: i32 = 2;
let BYTE_LIMIT: i32 = 3; let TOKEN_LIMIT: i32 = 4; let DEPTH_LIMIT: i32 = 5;
let MISSING: i32 = -1; let NULL: i32 = 0; let BOOL: i32 = 1; let NUMBER: i32 = 2;
let STRING: i32 = 3; let ARRAY: i32 = 4; let OBJECT: i32 = 5;
struct Limits { bytes: i64 = 1048576, tokens: i64 = 65536, depth: i64 = 128 }
struct Error { code: i32 = OK, offset: i64 = 0 }
struct Token { kind: i32, start: i64, end: i64 = 0, next: i64 = 0, count: i64 = 0 }
struct Document { source: const u8[:], error: Error = Error {}, tokens: Token[>..] = [] }
// Values borrow their document; they cannot outlive it or the input.
struct Value { doc: const Document&, index: i64 = -1 }
struct Frame { node: i64, state: i32 = 0 }
fn fail(doc: Document&, code: i32, at: i64) { if doc.error.code == OK { doc.error = Error { code, at }; } }
fn space(bytes: const u8[:], at: i64) -> i64 {
    var i = at; while i < bytes.len && is_space(bytes[i]) { i++; } i
}
fn digit(c: u8) -> bool { c >= '0' && c <= '9' }
fn hex(c: u8) -> i64 {
    if digit(c) { c as i64 - '0' } else if c >= 'a' && c <= 'f' { c as i64 - 'a' + 10 }
    else if c >= 'A' && c <= 'F' { c as i64 - 'A' + 10 } else { -1 }
}
fn hex4(bytes: const u8[:], at: i64) -> i64, bool {
    if at < 0 || bytes.len - at < 4 { return 0, false; }
    var cp: i64 = 0; for i in 4 { let d = hex(bytes[at + i]); if d < 0 { return 0, false; } cp = cp * 16 + d; }
    return cp, true;
}
// at points just after the backslash. Surrogate pairs become one scalar.
fn escape(bytes: const u8[:], at: i64) -> i64, i64, bool {
    if at >= bytes.len { return 0, at, false; }
    let c = bytes[at];
    if c == '"' || c == '\\' || c == '/' { return c, at + 1, true; }
    if c == 'b' { return 8, at + 1, true; } if c == 'f' { return 12, at + 1, true; }
    if c == 'n' { return 10, at + 1, true; } if c == 'r' { return 13, at + 1, true; }
    if c == 't' { return 9, at + 1, true; } if c != 'u' { return 0, at, false; }
    let cp, ok = hex4(bytes, at + 1); if !ok { return 0, at, false; }
    if cp >= 0xDC00 && cp <= 0xDFFF { return 0, at, false; }
    if cp < 0xD800 || cp > 0xDBFF { return cp, at + 5, true; }
    if bytes.len - at < 11 || bytes[at + 5] != '\\' || bytes[at + 6] != 'u' { return 0, at, false; }
    let low, paired = hex4(bytes, at + 7);
    if !paired || low < 0xDC00 || low > 0xDFFF { return 0, at, false; }
    return 0x10000 + (cp - 0xD800) * 1024 + low - 0xDC00, at + 11, true;
}
fn string_end(doc: Document&, start: i64) -> i64 {
    var i = start + 1;
    while i < doc.source.len {
        let c = doc.source[i]; if c == '"' { return i + 1; }
        if c < 32 { fail(doc, SYNTAX, i); return i; }
        if c == '\\' {
            let cp, next, ok = escape(doc.source, i + 1);
            if !ok { fail(doc, if i + 1 < doc.source.len && doc.source[i + 1] == 'u' { UNICODE } else { SYNTAX }, i); return i; }
            i = next;
        } else {
            let cp, next, ok = lab_text_utf8::decode(doc.source, i);
            if !ok { fail(doc, UNICODE, next); return i; } i = next;
        }
    }
    fail(doc, SYNTAX, i); i
}
fn number_end(bytes: const u8[:], start: i64) -> i64, bool {
    var i = start; if bytes[i] == '-' { i++; }
    if i >= bytes.len { return i, false; }
    if bytes[i] == '0' { i++; }
    else {
        if bytes[i] < '1' || bytes[i] > '9' { return i, false; }
        while i < bytes.len && digit(bytes[i]) { i++; }
    }
    if i < bytes.len && bytes[i] == '.' {
        i++; let first = i; while i < bytes.len && digit(bytes[i]) { i++; }
        if first == i { return i, false; }
    }
    if i < bytes.len && (bytes[i] == 'e' || bytes[i] == 'E') {
        i++; if i < bytes.len && (bytes[i] == '+' || bytes[i] == '-') { i++; }
        let first = i; while i < bytes.len && digit(bytes[i]) { i++; }
        if first == i { return i, false; }
    }
    return i, true;
}
fn value_token(doc: Document&, at: i64, limits: Limits) -> i64 {
    if doc.tokens.len >= limits.tokens { fail(doc, TOKEN_LIMIT, at); return -1; }
    if at >= doc.source.len { fail(doc, SYNTAX, at); return -1; }
    let c = doc.source[at]; var t = Token { kind: NULL, start: at, next: doc.tokens.len + 1 };
    if c == '{' || c == '[' { t.kind = if c == '{' { OBJECT } else { ARRAY }; t.end = at + 1; }
    else if c == '"' { t.kind = STRING; t.end = string_end(doc, at); }
    else if c == '-' || digit(c) {
        t.kind = NUMBER; let end, ok = number_end(doc.source, at); t.end = end;
        if !ok { fail(doc, SYNTAX, end); }
    } else {
        let word: const u8[:] = if c == 't' { "true" } else if c == 'f' { "false" } else { "null" };
        t.kind = if c == 't' || c == 'f' { BOOL } else { NULL };
        if word.len > doc.source.len - at || doc.source[at..at + word.len] != word { fail(doc, SYNTAX, at); }
        t.end = at + word.len;
    }
    if doc.error.code != OK { return -1; }
    let index = doc.tokens.len; doc.tokens.push(t); index
}
// Iterative grammar state machine: container depth never consumes the native stack.
fn parse(source: const u8[:], limits: Limits = Limits {}) -> Document {
    var doc = Document { source: source };
    if source.len > limits.bytes || limits.bytes < 0 { doc.error = Error { BYTE_LIMIT, 0 }; return doc; }
    if limits.tokens < 1 { doc.error = Error { TOKEN_LIMIT, 0 }; return doc; }
    if limits.depth < 0 || limits.depth > 128 { doc.error = Error { DEPTH_LIMIT, 0 }; return doc; }
    var frames: Frame[..128] = []; var at = space(source, 0); var root_seen = false;
    loop {
        at = space(source, at);
        if frames.len == 0 && root_seen {
            if at != source.len { fail(doc, SYNTAX, at); } break;
        }
        var key = false;
        if frames.len > 0 {
            let f = frames[frames.len - 1]; let kind = doc.tokens[f.node].kind;
            let c = if at < source.len { source[at] } else { 0 as u8 };
            let close = if kind == OBJECT { '}' as u8 } else { ']' as u8 };
            // 0 first element/key; 1 value after comma; 2 colon; 3 object value; 4 comma/end.
            if (f.state == 0 || f.state == 4) && c == close {
                doc.tokens[f.node].end = at + 1; doc.tokens[f.node].next = doc.tokens.len;
                frames.resize(frames.len - 1); at++; continue;
            }
            if f.state == 4 {
                if c != ',' { fail(doc, SYNTAX, at); break; }
                frames[frames.len - 1].state = 1; at++; continue;
            }
            if f.state == 2 {
                if c != ':' { fail(doc, SYNTAX, at); break; }
                frames[frames.len - 1].state = 3; at++; continue;
            }
            key = kind == OBJECT && (f.state == 0 || f.state == 1);
            if key && c != '"' { fail(doc, SYNTAX, at); break; }
        }
        let index = value_token(doc, at, limits); if index < 0 { break; }
        let t = doc.tokens[index]; at = t.end;
        if frames.len == 0 { root_seen = true; }
        else {
            let parent = frames[frames.len - 1].node;
            frames[frames.len - 1].state = if key { 2 } else { 4 };
            if !key { doc.tokens[parent].count++; }
        }
        if t.kind == ARRAY || t.kind == OBJECT {
            if frames.len >= limits.depth { fail(doc, DEPTH_LIMIT, t.start); break; }
            frames.push(Frame { node: index });
        }
    }
    // Never expose a partially validated tape.
    if doc.error.code != OK { let tape .= doc.tokens; tape.resize(0); }
    doc
}
fn root(doc: const Document&) -> Value { Value { doc: doc, index: if doc.error.code == OK && doc.tokens.len > 0 { 0 } else { -1 } } }
fn exists(v: Value) -> bool { v.doc.error.code == OK && v.index >= 0 && v.index < v.doc.tokens.len }
fn kind(v: Value) -> i32 { if exists(v) { v.doc.tokens[v.index].kind } else { MISSING } }
fn count(v: Value) -> i64 { if exists(v) { v.doc.tokens[v.index].count } else { 0 } }
fn raw(v: Value) -> const u8[:] {
    if !exists(v) { return ""; } let t = v.doc.tokens[v.index]; v.doc.source[t.start..t.end]
}
fn text(v: Value) -> u8[>..], bool {
    var out: u8[>..] = []; if kind(v) != STRING { return out, false; }
    let t = v.doc.tokens[v.index]; var at = t.start + 1;
    while at < t.end - 1 {
        if v.doc.source[at] == '\\' {
            let cp, next, ok = escape(v.doc.source, at + 1); assert(ok); push_utf8(out, cp); at = next;
        } else { out.push(v.doc.source[at]); at++; }
    }
    return out, true;
}
// Duplicate member names are accepted; lookup selects the first decoded match.
fn get(v: Value, name: const u8[:]) -> Value {
    var missing = Value { doc: v.doc }; if kind(v) != OBJECT { return missing; }
    var i = v.index + 1; let end = v.doc.tokens[v.index].next;
    while i < end {
        let key = Value { doc: v.doc, index: i }; let decoded, ok = text(key);
        let value = i + 1; if decoded == name { return Value { doc: v.doc, index: value }; }
        i = v.doc.tokens[value].next;
    } missing
}
fn at(v: Value, index: i64) -> Value {
    if kind(v) != ARRAY || index < 0 || index >= count(v) { return Value { doc: v.doc }; }
    var i = v.index + 1; for n in index { i = v.doc.tokens[i].next; } Value { doc: v.doc, index: i }
}
fn each<F>(v: Value) {
    if kind(v) == ARRAY {
        var i = v.index + 1; let end = v.doc.tokens[v.index].next;
        while i < end { F(Value { doc: v.doc, index: i }); i = v.doc.tokens[i].next; }
    }
}
fn members<F>(v: Value) {
    if kind(v) == OBJECT {
        var i = v.index + 1; let end = v.doc.tokens[v.index].next;
        while i < end { F(Value { doc: v.doc, index: i }, Value { doc: v.doc, index: i + 1 }); i = v.doc.tokens[i + 1].next; }
    }
}
fn boolean(v: Value) -> bool, bool { return raw(v) == "true", kind(v) == BOOL; }
// Conversion is separate from syntax validation; never silently overflow an i64.
fn integer(v: Value) -> i64, bool {
    if kind(v) != NUMBER { return 0, false; }
    let s = raw(v); let negative = s[0] == '-'; var i: i64 = if negative { 1 } else { 0 };
    let limit: u64 = if negative { 9223372036854775808 } else { 9223372036854775807 }; var n: u64 = 0;
    while i < s.len {
        if !digit(s[i]) { return 0, false; } let d = (s[i] - '0') as u64;
        if n > (limit - d) / 10 { return 0, false; } n = n * 10 + d; i++;
    }
    if negative && n == 9223372036854775808 { return -9223372036854775807 - 1, true; }
    return if negative { -(n as i64) } else { n as i64 }, true;
}
fn number(v: Value) -> f64, bool {
    if kind(v) != NUMBER { return 0.0, false; }
    // Normalize significant digits first: std::parse_flt counts leading zeros
    // towards its 19-digit mantissa, which would lose small decimal fractions.
    let s = raw(v); let negative = s[0] == '-'; var i: i64 = if negative { 1 } else { 0 };
    var mantissa: u64 = 0; var kept: i64 = 0; var dropped: i64 = 0; var fractional: i64 = 0; var decimal = false;
    while i < s.len && s[i] != 'e' && s[i] != 'E' {
        if s[i] == '.' { decimal = true; i++; continue; }
        let d = s[i] - '0'; if decimal { fractional++; }
        if kept > 0 || d != 0 {
            if kept < 19 { mantissa = mantissa * 10 + d; kept++; } else { dropped++; }
        } i++;
    }
    var exponent: i64 = dropped - fractional;
    if i < s.len {
        i++; var eneg = false; if s[i] == '+' || s[i] == '-' { eneg = s[i] == '-'; i++; }
        var e: i64 = 0; let ceiling = s.len + 1000;
        while i < s.len { if e < ceiling { e = min(ceiling, e * 10 + s[i] - '0'); } i++; }
        exponent += if eneg { -e } else { e };
    }
    if mantissa == 0 || exponent < -400 { return if negative { -0.0 } else { 0.0 }, true; }
    if exponent > 400 { return 0.0, false; }
    let n, ok = parse_flt(str(if negative { "-" } else { "" }, mantissa, "e", exponent));
    return n, ok && !is_nan(n) && !is_inf(n);
}
fn location(doc: const Document&) -> i64, i64 {
    var line: i64 = 1; var column: i64 = 1;
    for i in min(doc.error.offset, doc.source.len) { if doc.source[i] == '\n' { line++; column = 1; } else { column++; } }
    return line, column;
}
fn message(error: Error) -> const u8[:] {
    if error.code == OK { "Valid JSON" } else if error.code == SYNTAX { "Invalid JSON syntax" }
    else if error.code == UNICODE { "Invalid Unicode or surrogate escape" }
    else if error.code == BYTE_LIMIT { "JSON input exceeds the byte limit" }
    else if error.code == TOKEN_LIMIT { "JSON input exceeds the token limit" } else { "JSON input exceeds the depth limit" }
}

// Composable output builder. Errors are sticky; finish exposes only a complete document.
struct WriteFrame { kind: i32, count: i64 = 0, needs_value: bool = false }
struct Writer { frames: WriteFrame[..128] = [], roots: i64 = 0, error: i32 = OK, limit: i64 = 1048576, data: u8[>..] = [] }
fn emit(w: Writer&, bytes: const u8[:]) {
    if w.error != OK { return; }
    if w.limit < 0 || w.data.len > w.limit || bytes.len > w.limit - w.data.len { w.error = BYTE_LIMIT; return; } w.data.append(bytes);
}
fn before(w: Writer&) {
    if w.error != OK { return; }
    if w.frames.len == 0 { if w.roots != 0 { w.error = SYNTAX; } else { w.roots = 1; } return; }
    let index = w.frames.len - 1; let f = w.frames[index];
    if f.kind == OBJECT {
        if !f.needs_value { w.error = SYNTAX; return; } w.frames[index].needs_value = false;
    } else if f.count > 0 { emit(w, ","); }
    w.frames[index].count++;
}
fn quoted(w: Writer&, value: const u8[:]) {
    if w.error != OK { return; }
    if !lab_text_utf8::valid(value) { w.error = UNICODE; return; }
    emit(w, "\""); let digits: const u8[:] = "0123456789abcdef";
    for c in value {
        if c == '"' { emit(w, "\\\""); } else if c == '\\' { emit(w, "\\\\"); }
        else if c < 32 {
            emit(w, "\\u00"); let escaped: u8[2] = [digits[(c >> 4) as i64], digits[(c & 15) as i64]]; emit(w, escaped);
        } else { let byte: u8[1] = [c]; emit(w, byte); }
    } emit(w, "\"");
}
fn begin_object(w: Writer&) { before(w); if w.error != OK { return; } if w.frames.len >= 128 { w.error = DEPTH_LIMIT; return; } emit(w, "{"); if w.error == OK { w.frames.push(WriteFrame { kind: OBJECT }); } }
fn begin_array(w: Writer&) { before(w); if w.error != OK { return; } if w.frames.len >= 128 { w.error = DEPTH_LIMIT; return; } emit(w, "["); if w.error == OK { w.frames.push(WriteFrame { kind: ARRAY }); } }
fn end(w: Writer&) {
    if w.error != OK { return; }
    if w.frames.len == 0 || w.frames[w.frames.len - 1].needs_value { w.error = SYNTAX; return; }
    emit(w, if w.frames[w.frames.len - 1].kind == OBJECT { "}" } else { "]" }); w.frames.resize(w.frames.len - 1);
}
fn key(w: Writer&, name: const u8[:]) {
    if w.error != OK { return; }
    if w.frames.len == 0 || w.frames[w.frames.len - 1].kind != OBJECT || w.frames[w.frames.len - 1].needs_value { w.error = SYNTAX; return; }
    let index = w.frames.len - 1; if w.frames[index].count > 0 { emit(w, ","); }
    quoted(w, name); emit(w, ":"); w.frames[index].needs_value = true;
}
fn write_string(w: Writer&, value: const u8[:]) { before(w); if w.error == OK { quoted(w, value); } }
fn write_integer(w: Writer&, value: i64) { before(w); emit(w, str(value)); }
// Decimal/exponent spelling is checked directly; no intermediate float required.
fn write_number(w: Writer&, value: const u8[:]) {
    if w.error != OK { return; }
    if value.len == 0 { w.error = SYNTAX; return; }
    let end, valid = number_end(value, 0);
    if !valid || end != value.len { w.error = SYNTAX; return; }
    before(w); emit(w, value);
}
fn write_bool(w: Writer&, value: bool) { before(w); emit(w, if value { "true" } else { "false" }); }
fn write_null(w: Writer&) { before(w); emit(w, "null"); }
// Preserve a parsed number or subtree exactly; no lossy floating-point round trip.
fn write_value(w: Writer&, value: Value) {
    if w.error != OK { return; } if !exists(value) { w.error = SYNTAX; return; }
    // A copied subtree counts towards the same nesting bound as explicit begins.
    var ends: i64[..128] = []; let end = value.doc.tokens[value.index].next;
    for i in value.index..end {
        while ends.len > 0 && i >= ends[ends.len - 1] { ends.resize(ends.len - 1); }
        let t = value.doc.tokens[i];
        if t.kind == OBJECT || t.kind == ARRAY {
            if w.frames.len + ends.len >= 128 { w.error = DEPTH_LIMIT; return; }
            ends.push(t.next);
        }
    }
    before(w); emit(w, raw(value));
}
fn finish(w: const Writer&) -> u8[>..], bool {
    var out: u8[>..] = [];
    if w.error != OK || w.frames.len != 0 || w.roots != 1 { return out, false; }
    out.append(w.data); return out, true;
}
