// Basic horizontal Japanese kinsoku. Byte offsets; no shaping or ownership IDs.
namespace lab_text_line_break;
import std;
import lab.text.utf8;
fn listed(cp: i64, set: const u8[:]) -> bool {
    var at = 0;
    while at < set.len { let value, next, ok = lab_text_utf8::decode(set, at); assert(ok); if value == cp { return true; } at = next; }
    false
}
fn can_end(cp: i64) -> bool {
    if cp < 128 { return cp != '(' && cp != '[' && cp != '{'; }
    !listed(cp, "（［｛〔〈《「『【〖〘〚‘“«‹")
}
fn can_start(cp: i64) -> bool {
    if cp < 128 { return cp != ')' && cp != ']' && cp != '}' && cp != ',' && cp != '.' && cp != '!' && cp != '?' && cp != ':' && cp != ';'; }
    if cp >= 0x31F0 && cp <= 0x31FF { return false; } // Small katakana extensions.
    !listed(cp, "）］｝〕〉》」』】〗〙〛’”»›、。，．・：；？！ー々〻ゝゞヽヾぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶ゙゚")
}
fn allows(left: i64, right: i64) -> bool { can_end(left) && can_start(right) }
// Candidates for emergency wrapping, not a full Unicode line-break algorithm.
// Returns owned, increasing scalar-boundary offsets including the hard end.
// lab.ui.render.font intersects these with shaped clusters, retaining combining sequences.
fn japanese(value: const u8[:], limit: i64 = 262144) -> u32[>..], bool {
    var out: u32[>..] = [];
    if limit < 0 || limit > 0x7FFFFFFF || value.len > limit { return out, false; }
    var at = 0; var previous: i64 = 0;
    while at < value.len {
        let cp, next, ok = lab_text_utf8::decode(value, at); if !ok { out.resize(0); return out, false; }
        if at > 0 && allows(previous, cp) { out.push(at as u32); }
        previous = cp; at = next;
    }
    if value.len > 0 { out.push(value.len as u32); }
    return out, true;
}
