// Strict Unicode scalar decoding. Offsets and lengths are bytes.
namespace lab_text_utf8;
import std;
fn decode(bytes: const u8[:], at: i64) -> i64, i64, bool {
    if at < 0 || at >= bytes.len { return 0, at, false; }
    let b = bytes[at] as i64; var cp = b; var count: i64 = 1; var minimum: i64 = 0;
    if b >= 0xC2 && b <= 0xDF { cp = b & 31; count = 2; minimum = 0x80; }
    else if b >= 0xE0 && b <= 0xEF { cp = b & 15; count = 3; minimum = 0x800; }
    else if b >= 0xF0 && b <= 0xF4 { cp = b & 7; count = 4; minimum = 0x10000; }
    else if b >= 0x80 { return 0, at, false; }
    if count > bytes.len - at { return 0, at, false; }
    for i in count - 1 {
        let part = bytes[at + i + 1]; if (part & 0xC0) != 0x80 { return 0, at + i + 1, false; }
        cp = (cp << 6) | ((part as i64) & 63);
    }
    if cp < minimum || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) { return 0, at, false; }
    return cp, at + count, true;
}
fn valid(bytes: const u8[:]) -> bool {
    var at: i64 = 0;
    while at < bytes.len { let cp, next, ok = decode(bytes, at); if !ok { return false; } at = next; }
    true
}
fn append(out: u8[>..]&, cp: i64) -> bool {
    if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) { return false; }
    push_utf8(out, cp); true
}
