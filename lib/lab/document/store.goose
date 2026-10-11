// Multiple persistent documents in an explicitly owned, single-tail arena.
namespace lab_document_store;
import std;
import lab.document.piece_tree;
import lab.document.model;
import lab.text.utf8;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2; let STALE: i32 = 3;
struct Id { slot: i64 = -1, generation: u64 = 0 }
struct Limits { documents: i64 = 64, bytes: i64 = 2097152, history: i64 = 256,
    text: i64 = 67108864, nodes: i64 = 131072, arena: i64 = 100663296 }
struct Edit { before: i64, after: i64, old_selection: lab_document_model::Selection,
    selection: lab_document_model::Selection, old_revision: u64, revision: u64 }
struct Document { generation: u64 = 0, open: bool = false, root: i64 = -1, saved_root: i64 = -1,
    revision: u64 = 1, saved_revision: u64 = 1, next_revision: u64 = 1,
    selection: lab_document_model::Selection = lab_document_model::Selection {}, history: Edit[..256] = [], at: i64 = 0 }
struct Stats { documents: i64 = 0, current: i64 = 0, saved: i64 = 0, history_roots: i64 = 0,
    nodes: i64 = 0, text: i64 = 0, used: i64 = 0, arena: i64 = 0, high_water: i64 = 0,
    inserted: i64 = 0, collected_bytes: i64 = 0, growth_moved: i64 = 0,
    node_writes: i64 = 0, collections: i64 = 0, scanned_nodes: i64 = 0 }
struct Store { code: i32 = OK, limits: Limits = Limits {}, documents: Document[..64] = [], high_water: i64 = 0,
    tree: lab_document_piece_tree::Buffer = lab_document_piece_tree::Buffer {} }
fn create(limits: Limits = Limits {}) -> Store {
    if limits.documents < 1 || limits.documents > 64 || limits.bytes < 0 || limits.bytes > 2097152 ||
        limits.history < 1 || limits.history > 256 || limits.text < 0 || limits.text > 67108864 ||
        limits.nodes < 1 || limits.nodes > 1048576 || limits.arena < 0 || limits.arena > 134217728 {
        return Store { code: INVALID };
    }
    Store { limits: limits, tree: lab_document_piece_tree::Buffer {
        limits: lab_document_piece_tree::Limits { bytes: limits.bytes, store: limits.text, nodes: limits.nodes } } }
}
fn valid(s: const Store&, id: Id) -> bool {
    s.code == OK && id.slot >= 0 && id.slot < s.documents.len && s.documents[id.slot].open && s.documents[id.slot].generation == id.generation
}
fn size(s: const Store&, id: Id) -> i64 { if valid(s, id) { lab_document_piece_tree::size(s.tree, s.documents[id.slot].root) } else { -1 } }
fn revision(s: const Store&, id: Id) -> u64 { if valid(s, id) { s.documents[id.slot].revision } else { 0 } }
fn dirty(s: const Store&, id: Id) -> bool { valid(s, id) && s.documents[id.slot].revision != s.documents[id.slot].saved_revision }
fn selection(s: const Store&, id: Id) -> lab_document_model::Selection {
    if valid(s, id) { s.documents[id.slot].selection } else { lab_document_model::Selection {} }
}
fn observe(s: Store&) { s.high_water = max(s.high_water, s.tree.arena.len * 8); }
fn stats(s: const Store&) -> Stats {
    let m = s.tree.metrics;
    var result = Stats { nodes: s.tree.nodes, text: s.tree.stored, used: s.tree.nodes * 56 + s.tree.stored,
        arena: s.tree.arena.len * 8, high_water: s.high_water, inserted: m.inserted, collected_bytes: m.collected_bytes,
        growth_moved: m.growth_moved, node_writes: m.node_writes, collections: m.collections, scanned_nodes: m.scanned_nodes };
    for d in s.documents { if d.open {
        result.documents++; result.current += lab_document_piece_tree::size(s.tree, d.root);
        result.saved += lab_document_piece_tree::size(s.tree, d.saved_root); result.history_roots += d.history.len * 2;
    } }
    result
}
// Remap every live current/saved/undo/redo root together. No root escapes the API.
fn collect(s: Store&) {
    var roots: i64[>..] = [];
    for d in s.documents { if d.open {
        roots.push(d.root); roots.push(d.saved_root);
        for edit in d.history { roots.push(edit.before); roots.push(edit.after); }
    } }
    s.tree.root = -1; lab_document_piece_tree::collect(s.tree, roots); lab_document_piece_tree::collect_bytes(s.tree);
    var at: i64 = 0;
    for i in s.documents.len { if s.documents[i].open {
        s.documents[i].root = roots[at]; s.documents[i].saved_root = roots[at + 1]; at += 2;
        for j in s.documents[i].history.len {
            s.documents[i].history[j].before = roots[at]; s.documents[i].history[j].after = roots[at + 1]; at += 2;
        }
    } }
    assert(at == roots.len); observe(s);
}
fn fits(s: const Store&, bytes: i64, nodes: i64) -> bool {
    if bytes < 0 || nodes < 0 || bytes > s.limits.text - s.tree.stored || nodes > s.limits.nodes - s.tree.nodes { return false; }
    var capacity = s.tree.capacity; let needed = s.tree.nodes + nodes;
    while capacity < needed { capacity = min(s.limits.nodes, max(8, capacity * 2)); }
    let text = ((s.tree.stored + bytes + 7) / 8) * 8;
    capacity * 56 <= s.limits.arena && text <= s.limits.arena - capacity * 56
}
fn reserve(s: Store&, bytes: i64, nodes: i64) -> bool {
    if fits(s, bytes, nodes) { return true; }
    collect(s); fits(s, bytes, nodes)
}
fn valid_text(bytes: const u8[:]) -> bool {
    if !lab_text_utf8::valid(bytes) { return false; } for byte in bytes { if byte == 0 { return false; } } true
}
fn open(s: Store&, bytes: const u8[:]) -> Id, i32 {
    if s.code != OK || !valid_text(bytes) { return Id {}, INVALID; }
    if bytes.len > s.limits.bytes { return Id {}, LIMIT; }
    var slot: i64 = -1;
    for i in s.documents.len { if !s.documents[i].open && s.documents[i].generation < 0xFFFFFFFFFFFFFFFF { slot = i; break; } }
    if slot < 0 && s.documents.len == s.limits.documents { return Id {}, LIMIT; }
    let nodes = max(0, 2 * ((bytes.len + 4092) / 4093) - 1);
    if !reserve(s, bytes.len, nodes) { return Id {}, LIMIT; }
    let start = s.tree.stored; lab_document_piece_tree::append_text(s.tree, bytes);
    let root = lab_document_piece_tree::pieces(s.tree, start, s.tree.stored);
    if slot < 0 { s.documents.push(Document {}); slot = s.documents.len - 1; }
    let generation = s.documents[slot].generation + 1;
    s.documents[slot] = Document { generation: generation, open: true, root: root, saved_root: root };
    s.tree.root = -1; observe(s); return Id { slot, generation }, OK;
}
fn contents(s: const Store&, id: Id) -> u8[>..], i32 {
    if !valid(s, id) { return [], STALE; }
    let root = s.documents[id.slot].root; return lab_document_piece_tree::read_at(s.tree, root, 0, lab_document_piece_tree::size(s.tree, root)), OK;
}
fn baseline(s: const Store&, id: Id) -> u8[>..], i32 {
    if !valid(s, id) { return [], STALE; }
    let root = s.documents[id.slot].saved_root; return lab_document_piece_tree::read_at(s.tree, root, 0, lab_document_piece_tree::size(s.tree, root)), OK;
}
fn boundary(s: const Store&, root: i64, at: i64) -> bool {
    let length = lab_document_piece_tree::size(s.tree, root);
    at >= 0 && at <= length && (at == length || (lab_document_piece_tree::byte_at(s.tree, root, at) & 0xC0) != 0x80) &&
        !(at > 0 && at < length && lab_document_piece_tree::byte_at(s.tree, root, at - 1) == '\r' && lab_document_piece_tree::byte_at(s.tree, root, at) == '\n')
}
fn select(s: Store&, id: Id, cursor: i64, anchor: i64) -> i32 {
    if !valid(s, id) { return STALE; }
    let root = s.documents[id.slot].root; if !boundary(s, root, cursor) || !boundary(s, root, anchor) { return INVALID; }
    s.documents[id.slot].selection = lab_document_model::Selection { cursor, anchor }; OK
}
fn replace(s: Store&, id: Id, start: i64, end: i64, bytes: const u8[:]) -> i32 {
    if !valid(s, id) { return STALE; }
    let root = s.documents[id.slot].root;
    if !valid_text(bytes) || !boundary(s, root, start) || !boundary(s, root, end) || end < start { return INVALID; }
    if lab_document_piece_tree::matches_range(s.tree, root, start, end, bytes) { return OK; }
    if size(s, id) - (end - start) > s.limits.bytes - bytes.len || s.documents[id.slot].next_revision == 0xFFFFFFFFFFFFFFFF { return LIMIT; }
    // Collection can remap roots. Never retain root IDs or document borrows across it.
    s.tree.root = root; let nodes = lab_document_piece_tree::reserve(s.tree, bytes.len); s.tree.root = -1;
    if !reserve(s, bytes.len, nodes) { return LIMIT; }
    let before = s.documents[id.slot].root; s.tree.root = before;
    let code = lab_document_piece_tree::replace(s.tree, start, end, bytes); assert(code == OK);
    let after = s.tree.root; s.tree.root = -1;
    let d .= s.documents[id.slot]; let old_selection = d.selection; let old_revision = d.revision;
    d.history.resize(d.at);
    if d.history.len == s.limits.history { for i in (d.history.len - 1) { d.history[i] = d.history[i + 1]; } d.history.resize(d.history.len - 1); }
    d.next_revision++; d.revision = d.next_revision; var cursor = start + bytes.len;
    if !boundary(s, after, cursor) { cursor++; }
    d.selection = lab_document_model::Selection { cursor, cursor };
    d.history.push(Edit { before, after, old_selection, d.selection, old_revision, d.revision }); d.at = d.history.len; d.root = after;
    observe(s); OK
}
fn undo(s: Store&, id: Id) -> bool {
    if !valid(s, id) || s.documents[id.slot].at == 0 { return false; }
    let d .= s.documents[id.slot]; d.at--; let edit = d.history[d.at]; d.root = edit.before; d.selection = edit.old_selection; d.revision = edit.old_revision; true
}
fn redo(s: Store&, id: Id) -> bool {
    if !valid(s, id) || s.documents[id.slot].at == s.documents[id.slot].history.len { return false; }
    let d .= s.documents[id.slot]; let edit = d.history[d.at]; d.at++; d.root = edit.after; d.selection = edit.selection; d.revision = edit.revision; true
}
fn mark_saved(s: Store&, id: Id, expected_revision: u64) -> i32 {
    if !valid(s, id) || revision(s, id) != expected_revision { return STALE; }
    s.documents[id.slot].saved_root = s.documents[id.slot].root; s.documents[id.slot].saved_revision = expected_revision; OK
}
fn close(s: Store&, id: Id) -> i32 {
    if !valid(s, id) { return STALE; }
    let generation = s.documents[id.slot].generation; s.documents[id.slot] = Document { generation: generation }; OK
}
fn close_all(s: Store&) { for i in s.documents.len { if s.documents[i].open { close(s, Id { i, s.documents[i].generation }); } } collect(s); }
