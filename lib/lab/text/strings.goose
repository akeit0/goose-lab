namespace lab_text_strings;
import std;
import lab.text.utf8;
// Strict scalar UTF-8. Byte offsets are used throughout the small editor.
fn next(s: const u8[:], at: i64) -> i64 {
    if at >= s.len { return s.len; }
    var n = at + 1; while n < s.len && (s[n] & 0xC0) == 0x80 { n++; } n
}
fn previous(s: const u8[:], at: i64) -> i64 {
    if at <= 0 { return 0; }
    var n = at - 1; while n > 0 && (s[n] & 0xC0) == 0x80 { n--; } n
}
fn single_line(s: const u8[:]) -> bool {
    var i = 0;
    while i < s.len {
        let cp, next, ok = lab_text_utf8::decode(s, i);
        if !ok || cp < 32 ||
           (cp >= 127 && cp <= 159) || cp == 0x2028 || cp == 0x2029 { return false; }
        i = next;
    }
    true
}
fn folded(byte: u8) -> u8 { if byte >= 'A' && byte <= 'Z' { byte + 32 } else { byte } }
// ASCII case-folding; non-ASCII scalars compare byte-for-byte.
fn contains_folded(value: const u8[:], query: const u8[:]) -> bool {
    if query.len > value.len { return false; }
    for i in value.len - query.len + 1 {
        var same = true;
        for j in query.len { if folded(value[i + j]) != folded(query[j]) { same = false; break; } }
        if same { return true; }
    }
    false
}

fn equal_folded(left: const u8[:], right: const u8[:]) -> bool {
    if left.len != right.len { return false; }
    for i in left.len { if folded(left[i]) != folded(right[i]) { return false; } } true
}

// A bounded label for raw OS names/log bytes. Never use it as an operation path.
// Preserve Unicode; escape controls, backslashes and invalid UTF-8 bytes.
fn display_bytes(bytes: const u8[:], limit: i64 = 4096) -> u8[>..] {
    assert(limit >= 3); var output: u8[>..] = []; var at: i64 = 0;
    let digits: const u8[:] = "0123456789abcdef";
    while at < bytes.len {
        let cp, next, ok = lab_text_utf8::decode(bytes, at); var after = next; var piece: u8[>..] = [];
        if !ok {
            let byte = bytes[at]; let escaped: u8[4] = ['\\', 'x', digits[(byte >> 4) as i64], digits[(byte & 15) as i64]];
            piece.append(escaped); after = at + 1;
        } else if cp == 92 { piece.append("\\\\"); }
        else if cp == 9 { piece.append("\\t"); } else if cp == 10 { piece.append("\\n"); } else if cp == 13 { piece.append("\\r"); }
        else if cp < 32 || (cp >= 127 && cp <= 159) || cp == 0x2028 || cp == 0x2029 {
            let escaped: u8[6] = ['\\', 'u', digits[(cp >> 12) & 15], digits[(cp >> 8) & 15], digits[(cp >> 4) & 15], digits[cp & 15]];
            piece.append(escaped);
        } else { piece.append(bytes[at..next]); }
        if output.len + piece.len > limit || (after < bytes.len && output.len + piece.len > limit - 3) {
            output.append("…"); break;
        }
        output.append(piece); at = after;
    } output
}
