// Incremental KMP over bytes; UTF-8 patterns and ASCII-only case folding.
namespace lab_text_literal_search;
import std;
import lab.text.utf8;
import lab.text.strings;
import lab.text.line_index;
struct Pattern { valid: bool = false, ignore_case: bool = false, bytes: u8[..512] = [], prefix: i64[..512] = [] }
struct Cursor { at: i64 = 0, matched: i64 = 0 }
struct Batch { done: bool = false, matches: lab_text_line_index::Span[..32] = [] }
fn folded(pattern: const Pattern&, byte: u8) -> u8 { if pattern.ignore_case { lab_text_strings::folded(byte) } else { byte } }
fn compile(query: const u8[:], ignore_case: bool = false) -> Pattern {
    if query.len < 1 || query.len > 512 || !lab_text_utf8::valid(query) { return Pattern {}; }
    var pattern = Pattern { valid: true, ignore_case: ignore_case, bytes: query }; pattern.prefix.resize(query.len, 0);
    var j: i64 = 0;
    for i in query.len - 1 {
        let at = i + 1;
        while j > 0 && folded(pattern, query[at]) != folded(pattern, query[j]) { j = pattern.prefix[j - 1]; }
        if folded(pattern, query[at]) == folded(pattern, query[j]) { j++; } pattern.prefix[at] = j;
    } pattern
}
fn scan(pattern: const Pattern&, source: const u8[:], cursor: Cursor&, budget: i64 = 65536) -> Batch {
    assert(pattern.valid && cursor.at >= 0 && cursor.at <= source.len && cursor.matched >= 0 && cursor.matched < pattern.bytes.len && budget > 0);
    var batch = Batch {}; let end = cursor.at + min(budget, source.len - cursor.at);
    while cursor.at < end && batch.matches.len < 32 {
        let byte = folded(pattern, source[cursor.at]);
        while cursor.matched > 0 && byte != folded(pattern, pattern.bytes[cursor.matched]) { cursor.matched = pattern.prefix[cursor.matched - 1]; }
        if byte == folded(pattern, pattern.bytes[cursor.matched]) { cursor.matched++; } cursor.at++;
        if cursor.matched == pattern.bytes.len {
            batch.matches.push(lab_text_line_index::Span { cursor.at - pattern.bytes.len, cursor.at });
            cursor.matched = pattern.prefix[cursor.matched - 1];
        }
    }
    batch.done = cursor.at == source.len; batch
}
