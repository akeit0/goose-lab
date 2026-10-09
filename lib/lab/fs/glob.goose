// *, ?, ** and **/ only. Matching uses Unicode scalars, '/' separates paths.
namespace lab_fs_glob;
import std;
import lab.text.utf8;
let LITERAL: i32 = 0; let STAR: i32 = 1; let DEEP: i32 = 2; let FOLDERS: i32 = 3; let ANY: i32 = 4;
struct Token { kind: i32, scalar: i64 = 0 }
struct Pattern { valid: bool = false, tokens: Token[..256] = [] }
fn compile(pattern: const u8[:]) -> Pattern {
    if pattern.len < 1 || pattern.len > 256 || !lab_text_utf8::valid(pattern) { return Pattern {}; }
    var result = Pattern { valid: true }; var at: i64 = 0;
    while at < pattern.len {
        let cp, next, ok = lab_text_utf8::decode(pattern, at); assert(ok);
        if cp == 0 || cp == 92 { return Pattern {}; }
        if cp == '*' {
            if next < pattern.len && pattern[next] == '*' {
                let end = next + 1;
                if (at > 0 && pattern[at - 1] != '/') || (end < pattern.len && pattern[end] != '/') { return Pattern {}; }
                let folders = end < pattern.len; result.tokens.push(Token { if folders { FOLDERS } else { DEEP } });
                at = end + (if folders { 1 } else { 0 }); continue;
            }
            result.tokens.push(Token { STAR });
        } else { result.tokens.push(Token { if cp == '?' { ANY } else { LITERAL }, cp }); }
        at = next;
    } result
}
fn closure(pattern: const Pattern&, active: bool[:]) {
    for i in pattern.tokens.len { let kind = pattern.tokens[i].kind; if active[i] && (kind == STAR || kind == DEEP || kind == FOLDERS) { active[i + 1] = true; } }
}
fn matches(pattern: const Pattern&, path: const u8[:]) -> bool {
    if !pattern.valid || !lab_text_utf8::valid(path) { return false; }
    var active: bool[257] = [false; 257]; active[0] = true; closure(pattern, active); var at: i64 = 0;
    while at < path.len {
        let cp, next, ok = lab_text_utf8::decode(path, at); assert(ok); var after: bool[257] = [false; 257]; var continuing: bool[257] = [false; 257];
        for i in pattern.tokens.len {
            if !active[i] { continue; } let token = pattern.tokens[i];
            if token.kind == LITERAL && token.scalar == cp { after[i + 1] = true; }
            else if token.kind == ANY && cp != '/' { after[i + 1] = true; }
            else if token.kind == STAR && cp != '/' { after[i] = true; }
            else if token.kind == DEEP { after[i] = true; }
            else if token.kind == FOLDERS {
                // A directory prefix may continue arbitrarily, but its successor
                // is reached only after a slash (or through zero-width closure).
                continuing[i] = true; if cp == '/' { after[i + 1] = true; }
            }
        }
        closure(pattern, after);
        for i in pattern.tokens.len { after[i] = after[i] || continuing[i]; }
        active = after; at = next;
    }
    active[pattern.tokens.len]
}
