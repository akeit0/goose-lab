// UI-independent edits, selection, persistent undo and saved revision identity.
namespace lab_document_model;
import std;
import lab.document.piece_tree;
import lab.text.utf8;
import lab.text.grapheme;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2;
struct Selection { cursor: i64 = 0, anchor: i64 = 0 }
struct Edit { before: i64, after: i64, old_selection: Selection, selection: Selection, old_revision: u64, revision: u64, group: u64, typing: bool }
struct Document { code: i32 = OK, revision: u64 = 1, saved_revision: u64 = 1, next_revision: u64 = 1, group: u64 = 1, saved_root: i64 = -1,
    selection: Selection = Selection {}, history: Edit[..256] = [], at: i64 = 0, newline: u8[..2] = "\n", tree: lab_document_piece_tree::Buffer = lab_document_piece_tree::Buffer {} }
fn create(bytes: const u8[:], limits: lab_document_piece_tree::Limits = lab_document_piece_tree::Limits {}) -> Document {
    var tree = lab_document_piece_tree::create(bytes, limits); var code = tree.code; for byte in bytes { if byte == 0 { code = INVALID; } }
    var newline: u8[..2] = "\n"; for i in bytes.len { if bytes[i] == '\n' { if i > 0 && bytes[i - 1] == '\r' { newline = "\r\n"; } break; } }
    let saved = tree.root; Document { code: code, saved_root: saved, newline: newline, tree: tree }
}
fn size(d: const Document&) -> i64 { lab_document_piece_tree::size(d.tree, d.tree.root) }
fn lines(d: const Document&) -> i64 { lab_document_piece_tree::feeds(d.tree, d.tree.root) + 1 }
fn dirty(d: const Document&) -> bool { d.revision != d.saved_revision }
fn first(d: const Document&) -> i64 { min(d.selection.cursor, d.selection.anchor) }
fn last(d: const Document&) -> i64 { max(d.selection.cursor, d.selection.anchor) }
fn boundary(d: const Document&, at: i64) -> bool {
    if !lab_document_piece_tree::boundary(d.tree, at) { return false; }
    !(at > 0 && at < size(d) && lab_document_piece_tree::byte_at(d.tree, d.tree.root, at - 1) == '\r' && lab_document_piece_tree::byte_at(d.tree, d.tree.root, at) == '\n')
}
fn break_group(d: Document&) { d.group++; }
fn select(d: Document&, cursor: i64, anchor: i64) -> bool { if !boundary(d, cursor) || !boundary(d, anchor) { return false; } break_group(d); d.selection = Selection { cursor, anchor }; true }
fn scalar(d: const Document&, at: i64, backwards: bool) -> i64, i64 {
    var start=at;
    if backwards { start--; while start>0 && (lab_document_piece_tree::byte_at(d.tree,d.tree.root,start) & 0xC0)==0x80 { start--; } }
    var bytes: u8[..4]=[]; var end=start;
    loop { bytes.push(lab_document_piece_tree::byte_at(d.tree,d.tree.root,end)); end++; if end==size(d) || (lab_document_piece_tree::byte_at(d.tree,d.tree.root,end) & 0xC0)!=0x80 { break; } }
    let cp,next,ok=lab_text_utf8::decode(bytes,0); assert(ok); return cp, if backwards { start } else { end };
}
fn grapheme_boundary(d: const Document&, at: i64) -> bool {
    if !boundary(d,at) { return false; }
    fn read(pos: i64, backwards: bool) -> i64, i64 { let cp,end=scalar(d,pos,backwards); return cp,end; }
    lab_text_grapheme::boundary_at(at,size(d),read)
}
fn previous(d: const Document&, at: i64) -> i64 {
    assert(boundary(d,at)); var pos=at;
    if pos>0 { let cp,before=scalar(d,pos,true); pos=before; }
    while pos>0 && !grapheme_boundary(d,pos) { let cp,before=scalar(d,pos,true); pos=before; } pos
}
fn next(d: const Document&, at: i64) -> i64 {
    assert(boundary(d,at)); var pos=at;
    if pos<size(d) { let cp,end=scalar(d,pos,false); pos=end; }
    while pos<size(d) && !grapheme_boundary(d,pos) { let cp,end=scalar(d,pos,false); pos=end; } pos
}
fn read(d: const Document&, start: i64, end: i64) -> u8[>..] { lab_document_piece_tree::read(d.tree, start, end) }
fn contents(d: const Document&) -> u8[>..] { read(d, 0, size(d)) }
fn baseline(d: const Document&) -> u8[>..] { lab_document_piece_tree::read_at(d.tree, d.saved_root, 0, lab_document_piece_tree::size(d.tree, d.saved_root)) }
fn collect(d: Document&) {
    var roots: i64[..513] = [d.saved_root];
    for entry in d.history { roots.push(entry.before); roots.push(entry.after); }
    lab_document_piece_tree::collect(d.tree, roots); lab_document_piece_tree::collect_bytes(d.tree); d.saved_root = roots[0];
    for i in d.history.len { d.history[i].before = roots[1 + i * 2]; d.history[i].after = roots[2 + i * 2]; }
}
fn replace(d: Document&, start: i64, end: i64, text: const u8[:], typing: bool = false) -> i32, bool {
    if d.code != OK || !boundary(d, start) || !boundary(d, end) || end < start || !lab_text_utf8::valid(text) { return INVALID, false; }
    for byte in text { if byte == 0 { return INVALID, false; } }
    let old = read(d, start, end); if old == text { return OK, false; }
    if d.next_revision == 0xFFFFFFFFFFFFFFFF { return LIMIT, false; }
    if lab_document_piece_tree::reserve(d.tree, text.len) > d.tree.limits.nodes - d.tree.nodes || text.len > d.tree.limits.store - d.tree.stored { collect(d); }
    let before = d.tree.root; let selection = d.selection; let revision = d.revision;
    let code = lab_document_piece_tree::replace(d.tree, start, end, text); if code != OK { return code, false; }
    var grouped = typing; for byte in text { if byte == '\n' || byte == '\r' { grouped = false; } }
    var merge = grouped && start == end && text.len > 0 && d.at > 0 && d.at == d.history.len;
    if merge { let last = d.history[d.at - 1]; merge = last.typing && last.group == d.group && last.selection.cursor == start && last.selection.anchor == start; }
    d.history.resize(d.at);
    if !merge && d.history.len == 256 { for i in 255 { d.history[i] = d.history[i + 1]; } d.history.resize(255); }
    d.next_revision++; d.revision = d.next_revision; d.selection = Selection { start + text.len, start + text.len };
    // Joining CR + LF can make the insertion endpoint an interior CRLF boundary.
    if !boundary(d, d.selection.cursor) { d.selection = Selection { d.selection.cursor + 1, d.selection.cursor + 1 }; }
    if merge { let edit .= d.history[d.at - 1]; edit.after = d.tree.root; edit.selection = d.selection; edit.revision = d.revision; }
    else { d.history.push(Edit { before, d.tree.root, selection, d.selection, revision, d.revision, d.group, grouped }); }
    d.at = d.history.len; if !grouped { break_group(d); } return OK, true;
}
fn insert(d: Document&, text: const u8[:], typing: bool = false) -> i32, bool { let code, changed = replace(d, first(d), last(d), text, typing); return code, changed; }
fn undo(d: Document&) -> bool { if d.at <= 0 { return false; } break_group(d); d.at--; let edit = d.history[d.at]; d.tree.root = edit.before; d.selection = edit.old_selection; d.revision = edit.old_revision; true }
fn redo(d: Document&) -> bool { if d.at >= d.history.len { return false; } break_group(d); let edit = d.history[d.at]; d.at++; d.tree.root = edit.after; d.selection = edit.selection; d.revision = edit.revision; true }
fn mark_saved(d: Document&) { break_group(d); d.saved_revision = d.revision; d.saved_root = d.tree.root; }
fn compact(d: Document&) -> bool {
    let saved = baseline(d); let current = contents(d); var tree = lab_document_piece_tree::create(saved, d.tree.limits); if tree.code != OK { return false; }
    let root = tree.root;
    if saved != current && lab_document_piece_tree::replace(tree, 0, saved.len, current) != OK { return false; }
    d.tree = copy(tree); d.saved_root = root; d.history.resize(0); d.at = 0; break_group(d); true
}
fn message(code: i32) -> const u8[:] { match code { 0 => "Ready", 1 => "Invalid UTF-8 text or edit boundary", _ => "Document/storage limit reached; compact to clear undo history" } }
