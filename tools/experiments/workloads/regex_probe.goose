// Compile once per batch; use upstream stdlib engine, own retained capture bytes.
import std;
import os;
import regex;
fn nibble(c: u8) -> i64 { if c >= '0' && c <= '9' { return c - '0'; } if c >= 'a' && c <= 'f' { return c - 'a' + 10; } abort("invalid hex input"); }
fn decode(text: const u8[:]) -> u8[>..] {
    assert(text.len % 2 == 0 && text.len <= 8192); var out: u8[>..] = [];
    for i in text.len / 2 { out.push((nibble(text[i * 2]) * 16 + nibble(text[i * 2 + 1])) as! u8); } out
}
fn hex(text: const u8[:]) -> u8[>..] {
    let digits = "0123456789abcdef"; var out: u8[>..] = [];
    for b in text { out.push(digits[(b / 16) as i64]); out.push(digits[(b % 16) as i64]); } out
}
fn main() {
    var batch: i64 = 0;
    loop {
        var line: u8[>..] = []; if !read_line(line) { break; }
        let fields = split(line, '\t'); assert(fields.len == 2);
        let pattern = decode(fields[0]); let count, ok = parse_int(fields[1]); assert(ok && count >= 1 && count <= 128);
        var err: u8[>..] = []; let re = regex::compile(pattern, err);
        var retained: u8[..4096] = []; var retained_once = false;
        if err.len > 0 { assert(!regex::matches(re, "abc") && regex::count(re, "abc") == 0); print("invalid,", batch); }
        else { assert(re.groups <= 20); print("compiled,", batch, ",", re.groups); }
        for case in count {
            var encoded: u8[>..] = []; assert(read_line(encoded)); var text = decode(encoded);
            let start, end = regex::find(re, text);
            print("case,", batch, ",", case, ",", start, ",", end, ",", regex::count(re, text), ",", if regex::matches(re, text) { 1 } else { 0 });
            var number: i64 = 0;
            regex::each_captures(re, text) { caps =>
                var row: u8[>..] = []; format(row, "capture,", batch, ",", case, ",", number);
                for offset in caps.slots { format(row, ",", offset); }
                for k in re.groups { format(row, ",", hex(regex::group(caps, k))); }
                print(row);
                if !retained_once { retained.append(regex::group(caps, 0)); retained_once = true; }
                number++;
            };
            var replaced: u8[>..] = [];
            regex::format_replaced(replaced, re, text) { caps => str("<", regex::group(caps, 0), ">") };
            print("replaced,", batch, ",", case, ",", hex(replaced));
            // Later input mutation must not alter an earlier owned capture export.
            if text.len > 0 { text[0] = 0xFF; }
            print("retained,", batch, ",", case, ",", hex(retained));
        }
        batch++;
    }
    print("Regex experiment passed,", batch);
}
