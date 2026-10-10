// Contiguous snapshot baseline, deliberately separate from the production editor.
namespace experiment_pool_document;
import std;
import lab.document.model;
import lab.text.utf8;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2; let STALE: i32 = 3;
struct Id { slot: i64 = -1, generation: u64 = 0 }
struct Limits { documents: i64 = 64, bytes: i64 = 2097152, history: i64 = 256, pool: i64 = 67108864 }
struct Snapshot { text: const u8[:] = storage[..0], offset: i64 = 0, revision: u64 = 1,
    selection: lab_document_model::Selection = lab_document_model::Selection {}, old_selection: lab_document_model::Selection = lab_document_model::Selection {} }
struct Document { generation: u64 = 0, open: bool = false, next_revision: u64 = 1,
    versions: Snapshot[..257] = [], at: i64 = 0, selection: lab_document_model::Selection = lab_document_model::Selection {}, saved: Snapshot = Snapshot {} }
struct Range { start: i64, end: i64 }
struct Stats { documents: i64 = 0, current: i64 = 0, saved: i64 = 0, undo: i64 = 0,
    used: i64 = 0, high_water: i64 = 0, free: i64 = 0, largest_free: i64 = 0,
    copied: i64 = 0, zeroed: i64 = 0, allocations: i64 = 0, preflight_scans: i64 = 0 }
// One registry per worker. Public operations expose owned bytes and generation IDs,
// never a raw pool slice, document reference or pool name.
reusable[] var storage: u8[>..] = [];
var documents: Document[..64] = [];
var limits = Limits {};
var copied: i64 = 0;
var zeroed: i64 = 0;
var allocations: i64 = 0;
var preflight_scans: i64 = 0;
fn valid(id: Id) -> bool { id.slot >= 0 && id.slot < documents.len && documents[id.slot].open && documents[id.slot].generation == id.generation }
fn ranges() -> Range[>..] {
    var result: Range[>..] = [];
    fn add(s: const Snapshot&) { if s.text.len > 0 { result.push(Range { s.offset, s.offset + s.text.len }); } }
    for d in documents { if d.open { for v in d.versions { add(v); } add(d.saved); } }
    fn less(a: const Range&, b: const Range&) -> bool { a.start < b.start }
    sort(result, less); result
}
fn stats() -> Stats {
    var s = Stats { high_water: storage.len, copied: copied, zeroed: zeroed, allocations: allocations, preflight_scans: preflight_scans };
    for d in documents {
        if !d.open { continue; } s.documents++; s.saved += d.saved.text.len;
        s.current += d.versions[d.at].text.len;
        for i in d.versions.len { if i != d.at { s.undo += d.versions[i].text.len; } }
    }
    s.used = s.current + s.saved + s.undo; s.free = s.high_water - s.used;
    var end: i64 = 0; let spans = ranges();
    for r in spans { assert(r.start >= end); s.largest_free = max(s.largest_free, r.start - end); end = r.end; }
    s.largest_free = max(s.largest_free, storage.len - end); s
}
// Predict first-fit placement including a free tail. Check the high-water budget
// before calling the runtime allocator, whose reservation failure is fatal.
fn fits(count: i64, copies: i64 = 1) -> bool {
    if count < 0 || copies < 1 { return false; } if count == 0 { return true; }
    // Appending every requested run fits even if no freed space is usable.
    // Avoid walking/sorting retained versions unless the budget is under pressure.
    // Division keeps this bound safe without multiplying user-sized counts.
    if count <= (limits.pool - storage.len) / copies { return true; }
    preflight_scans++;
    var end: i64 = 0; var remaining = copies; let spans = ranges();
    for r in spans { remaining -= min(remaining, (r.start - end) / count); if remaining == 0 { return true; } end = r.end; }
    count * remaining <= limits.pool - end
}
fn allocate(count: i64) -> u8[:], i64 {
    let text = storage.alloc_slice(count); allocations++; zeroed += count;
    let offset = if count == 0 { 0 } else { storage.index_of(text[0]) };
    return text, offset;
}
fn duplicate(text: const u8[:]) -> Snapshot {
    let bytes, offset = allocate(text.len); for i in text.len { bytes[i] = text[i]; } copied += text.len;
    Snapshot { text: bytes, offset: offset }
}
fn release(s: Snapshot&) { storage.free_slice(s.text); s.text = storage[..0]; }
fn configure(value: Limits) -> bool {
    if stats().documents != 0 || value.documents < 1 || value.documents > 64 || value.bytes < 0 || value.bytes > 2097152 ||
        value.history < 1 || value.history > 256 || value.pool < storage.len || value.pool > 67108864 { return false; }
    limits = value; true
}
fn valid_text(text: const u8[:]) -> bool { if !lab_text_utf8::valid(text) { return false; } for byte in text { if byte == 0 { return false; } } true }
fn open(text: const u8[:]) -> Id, i32 {
    if !valid_text(text) { return Id {}, INVALID; }
    if text.len > limits.bytes || !fits(text.len, 2) { return Id {}, LIMIT; }
    var slot: i64 = -1;
    for i in documents.len { if !documents[i].open && documents[i].generation < 0xFFFFFFFFFFFFFFFF && i < limits.documents { slot = i; break; } }
    if slot < 0 { if documents.len >= limits.documents { return Id {}, LIMIT; } documents.push(Document {}); slot = documents.len - 1; }
    let d .= documents[slot]; d.generation++; d.open = true; d.next_revision = 1; d.at = 0; d.selection = lab_document_model::Selection {};
    d.versions.push(duplicate(text)); d.saved = duplicate(text); return Id { slot, d.generation }, OK;
}
fn close(id: Id) -> i32 {
    if !valid(id) { return STALE; } let d .= documents[id.slot];
    for i in d.versions.len { release(d.versions[i]); } d.versions.resize(0); release(d.saved); d.open = false; OK
}
fn close_all() { for i in documents.len { if documents[i].open { close(Id { i, documents[i].generation }); } } }
fn contents(id: Id) -> u8[>..], i32 {
    if !valid(id) { return [], STALE; } let text = documents[id.slot].versions[documents[id.slot].at].text;
    var out: u8[>..] = []; out.append(text); return out, OK;
}
fn baseline(id: Id) -> u8[>..], i32 {
    if !valid(id) { return [], STALE; } var out: u8[>..] = []; out.append(documents[id.slot].saved.text); return out, OK;
}
fn revision(id: Id) -> u64 { if !valid(id) { 0 } else { documents[id.slot].versions[documents[id.slot].at].revision } }
fn dirty(id: Id) -> bool { valid(id) && revision(id) != documents[id.slot].saved.revision }
fn selection(id: Id) -> lab_document_model::Selection { if !valid(id) { lab_document_model::Selection {} } else { documents[id.slot].selection } }
fn boundary(text: const u8[:], at: i64) -> bool {
    at >= 0 && at <= text.len && (at == text.len || (text[at] & 0xC0) != 0x80) &&
        !(at > 0 && at < text.len && text[at - 1] == '\r' && text[at] == '\n')
}
fn select(id: Id, cursor: i64, anchor: i64) -> i32 {
    if !valid(id) { return STALE; } let d .= documents[id.slot]; let s .= d.versions[d.at];
    if !boundary(s.text, cursor) || !boundary(s.text, anchor) { return INVALID; }
    d.selection = lab_document_model::Selection { cursor, anchor }; OK
}
fn replace(id: Id, start: i64, end: i64, text: const u8[:]) -> i32 {
    if !valid(id) { return STALE; } let d .= documents[id.slot]; let before = d.versions[d.at];
    if !valid_text(text) || !boundary(before.text, start) || !boundary(before.text, end) || end < start { return INVALID; }
    if before.text[start..end] == text { return OK; }
    let length = before.text.len - (end - start) + text.len;
    if length > limits.bytes || d.next_revision == 0xFFFFFFFFFFFFFFFF || !fits(length) { return LIMIT; }
    // Allocate/write before retiring redo or history, so refusal is transactional.
    let bytes, offset = allocate(length); var at: i64 = 0;
    for byte in before.text[..start] { bytes[at] = byte; at++; }
    for byte in text { bytes[at] = byte; at++; }
    for byte in before.text[end..] { bytes[at] = byte; at++; }
    copied += length; d.next_revision++;
    var after = Snapshot { text: bytes, offset: offset, revision: d.next_revision, old_selection: d.selection };
    var cursor = start + text.len; if !boundary(after.text, cursor) { cursor++; }
    after.selection = lab_document_model::Selection { cursor, cursor };
    for i in (d.at + 1)..d.versions.len { release(d.versions[i]); } d.versions.resize(d.at + 1);
    if d.versions.len == limits.history + 1 {
        release(d.versions[0]); for i in (d.versions.len - 1) { d.versions[i] = d.versions[i + 1]; } d.versions.resize(d.versions.len - 1);
    }
    d.versions.push(after); d.at = d.versions.len - 1; d.selection = after.selection; OK
}
fn undo(id: Id) -> bool {
    if !valid(id) || documents[id.slot].at == 0 { return false; } let d .= documents[id.slot]; d.selection = d.versions[d.at].old_selection; d.at--; true
}
fn redo(id: Id) -> bool {
    if !valid(id) || documents[id.slot].at + 1 == documents[id.slot].versions.len { return false; } let d .= documents[id.slot]; d.at++; d.selection = d.versions[d.at].selection; true
}
// Called only after publication. expected_revision prevents an old save completion
// from marking a newer edit clean; Id also rejects completions after slot reuse.
fn mark_saved(id: Id, expected_revision: u64) -> i32 {
    if !valid(id) || revision(id) != expected_revision { return STALE; } let d .= documents[id.slot]; let current = d.versions[d.at];
    if !fits(current.text.len) { return LIMIT; }
    var saved = duplicate(current.text); saved.revision = current.revision; release(d.saved); d.saved = saved; OK
}
