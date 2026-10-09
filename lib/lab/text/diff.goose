// Unified diff metadata owns offsets, never copied line text or escaped refs.
namespace lab_text_diff;
import std;
import lab.text.line_index;
import lab.text.utf8;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2; let ENCODING: i32 = 3; let UNSUPPORTED: i32 = 4;
let HEADER: i32 = 0; let HUNK: i32 = 1; let CONTEXT: i32 = 2; let ADD: i32 = 3; let REMOVE: i32 = 4; let META: i32 = 5;
struct Row { kind: i32 = HEADER, old: i64 = -1, new: i64 = -1, start: i64 = 0, end: i64 = 0 }
struct Patch {
    code: i32 = OK, rows: Row[..32768] = [], hunks: i64[..4096] = [],
    added: i64 = 0, removed: i64 = 0, binary: bool = false, source: u8[>..<] = [],
}
fn number(text: const u8[:], at: i64) -> i64, i64, bool {
    var end = at; var n: i64 = 0;
    while end < text.len && text[end] >= '0' && text[end] <= '9' {
        if n > 100000000 { return 0, end, false; } n = n * 10 + text[end] - '0'; end++;
    } return n, end, end > at;
}
fn range(text: const u8[:], at: i64) -> i64, i64, i64, bool {
    let start, end, ok = number(text, at); if !ok { return 0, 0, end, false; }
    if end < text.len && text[end] == ',' {
        let count, next, count_ok = number(text, end + 1); return start, count, next, count_ok && (start > 0 || count == 0);
    } return start, 1, end, start > 0;
}
fn header(text: const u8[:]) -> i64, i64, i64, i64, bool {
    if !starts_with(text, "@@ -") { return 0, 0, 0, 0, false; }
    let old, old_count, end, ok = range(text, 4);
    if !ok || end + 2 > text.len || text[end..end + 2] != " +" { return 0, 0, 0, 0, false; }
    let newer, new_count, next, good = range(text, end + 2);
    if !good || next + 3 > text.len || text[next..next + 3] != " @@" { return 0, 0, 0, 0, false; }
    return old, old_count, newer, new_count, true;
}
fn decode(bytes: const u8[:]) -> Patch {
    if bytes.len > 2097152 { return Patch { code: LIMIT }; }
    if !lab_text_utf8::valid(bytes) { return Patch { code: ENCODING }; }
    let lines, indexed = lab_text_line_index::build(bytes); if !indexed { return Patch { code: LIMIT }; }
    var rows: Row[>..] = []; var hunks: i64[>..] = []; var added: i64 = 0; var removed: i64 = 0; var binary = false;
    var old: i64 = 0; var newer: i64 = 0;
    var old_left: i64 = 0; var new_left: i64 = 0;
    for i in lines.rows.len {
        let text = lab_text_line_index::line(lines, bytes, i); var row = Row {};
        if starts_with(text, "diff --cc ") || starts_with(text, "diff --combined ") || starts_with(text, "@@@") { return Patch { code: UNSUPPORTED }; }
        if starts_with(text, "@@ ") {
            if old_left != 0 || new_left != 0 { return Patch { code: INVALID }; }
            let start, count, ns, nc, ok = header(text); if !ok { return Patch { code: INVALID }; }
            old = start; newer = ns; old_left = count; new_left = nc;
            row.kind = HUNK; if hunks.len == 4096 { return Patch { code: LIMIT }; } hunks.push(i);
        } else if starts_with(text, "\\ No newline at end of file") { row.kind = META; }
        else if old_left > 0 || new_left > 0 {
            if text.len == 0 { return Patch { code: INVALID }; }
            if text[0] == ' ' && old_left > 0 && new_left > 0 {
                row = Row { CONTEXT, old, newer }; old++; newer++; old_left--; new_left--;
            } else if text[0] == '+' && new_left > 0 { row = Row { ADD, -1, newer }; newer++; new_left--; added++; }
            else if text[0] == '-' && old_left > 0 { row = Row { REMOVE, old, -1 }; old++; old_left--; removed++; }
            else { return Patch { code: INVALID }; }
        } else {
            if starts_with(text, "Binary files ") || starts_with(text, "GIT binary patch") { binary = true; }
        }
        row.start = lines.rows[i].start; row.end = lines.rows[i].end; rows.push(row);
    }
    if old_left != 0 || new_left != 0 { return Patch { code: INVALID }; }
    Patch { rows: rows, hunks: hunks, added: added, removed: removed, binary: binary, source: bytes }
}
// Plain file contents use the same owned rows without interpreting patch syntax.
fn plain(bytes: const u8[:]) -> Patch {
    if bytes.len > 2097152 { return Patch { code: LIMIT }; }
    for b in bytes { if b == 0 { return Patch { binary: true }; } }
    if !lab_text_utf8::valid(bytes) { return Patch { code: ENCODING }; }
    let index, ok = lab_text_line_index::build(bytes); if !ok { return Patch { code: LIMIT }; }
    var patch = Patch {};
    for i in index.rows.len { patch.rows.push(Row { new: i + 1, start: index.rows[i].start, end: index.rows[i].end }); }
    patch.source = bytes; patch
}
fn text(patch: const Patch&, row: i64) -> const u8[:] { let r = patch.rows[row]; patch.source[r.start..r.end] }
// Locate the next/previous hunk from a displayed row; no scan through line bytes.
fn next_hunk(patch: const Patch&, row: i64, direction: i64) -> i64 {
    if direction > 0 { for hunk in patch.hunks { if hunk > row { return hunk; } } }
    else { var i = patch.hunks.len; while i > 0 { i--; if patch.hunks[i] < row { return patch.hunks[i]; } } } -1
}
fn message(code: i32) -> const u8[:] {
    match code { 0 => "Diff ready", 1 => "Invalid unified diff", 2 => "Diff exceeds the size, line or hunk limit",
        3 => "Diff is not UTF-8 text", _ => "Combined merge diffs are not supported yet" }
}
