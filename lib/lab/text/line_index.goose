// Own offsets, borrow text only at access time. Offsets survive moving owned text.
namespace lab_text_line_index;
import std;
struct Span { start: i64, end: i64 }
struct Index { bytes: i64 = 0, rows: Span[] = [] }
fn build(text: const u8[:], max_lines: i64 = 32768) -> Index, bool {
    if max_lines < 0 { return Index {}, false; }
    var rows: Span[>..] = []; var start: i64 = 0;
    for at in text.len {
        if text[at] == '\n' {
            if rows.len >= max_lines { return Index {}, false; }
            let end = if at > start && text[at - 1] == '\r' { at - 1 } else { at };
            rows.push(Span { start, end }); start = at + 1;
        }
    }
    // A final terminator ends a line; it does not create a phantom display row.
    if start < text.len {
        if rows.len >= max_lines { return Index {}, false; }
        rows.push(Span { start, text.len });
    }
    return Index { bytes: text.len, rows: rows }, true;
}
fn line(index: const Index&, text: const u8[:], row: i64) -> const u8[:] {
    assert(text.len == index.bytes && row >= 0 && row < index.rows.len);
    let span = index.rows[row]; text[span.start..span.end]
}
// A byte offset maps to its containing row, or -1 outside the indexed text.
fn row_at(index: const Index&, byte: i64) -> i64 {
    if byte < 0 || byte >= index.bytes || index.rows.len == 0 { return -1; }
    var first: i64 = 0; var end = index.rows.len;
    while first < end { let mid = first + (end - first) / 2; if index.rows[mid].start <= byte { first = mid + 1; } else { end = mid; } }
    first - 1
}
