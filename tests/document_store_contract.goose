import std;
import os;
import lab.document.store;
import lab.document.model;
import experiments.pool_document;
struct Version { bytes: u8[..2048] = [], revision: u64 = 1,
    selection: lab_document_model::Selection = lab_document_model::Selection {}, old_selection: lab_document_model::Selection = lab_document_model::Selection {} }
// Independent full-snapshot oracle; no Piece Tree operations in the model.
struct Flat { id: lab_document_store::Id, versions: Version[..17] = [Version {}], at: i64 = 0,
    saved: Version = Version {}, selection: lab_document_model::Selection = lab_document_model::Selection {}, next_revision: u64 = 1 }
fn check(s: const lab_document_store::Store&, f: const Flat&) {
    let bytes, code = lab_document_store::contents(s, f.id); let saved, sc = lab_document_store::baseline(s, f.id);
    assert(code == 0 && sc == 0 && bytes == f.versions[f.at].bytes && saved == f.saved.bytes);
    assert(lab_document_store::revision(s, f.id) == f.versions[f.at].revision);
    assert(lab_document_store::dirty(s, f.id) == (f.versions[f.at].revision != f.saved.revision));
    let selected = lab_document_store::selection(s, f.id); assert(selected.cursor == f.selection.cursor && selected.anchor == f.selection.anchor);
}
fn edit(f: Flat&, start: i64, end: i64, insertion: const u8[:]) {
    var after = Version {}; after.bytes.append(f.versions[f.at].bytes[0..start]); after.bytes.append(insertion); after.bytes.append(f.versions[f.at].bytes[end..f.versions[f.at].bytes.len]);
    if after.bytes == f.versions[f.at].bytes { return; }
    f.next_revision++; after.revision = f.next_revision; after.old_selection = f.selection;
    after.selection = lab_document_model::Selection { start + insertion.len, start + insertion.len };
    f.versions.resize(f.at + 1);
    if f.versions.len == 17 { for i in 16 { f.versions[i] = f.versions[i + 1]; } f.versions.resize(16); }
    f.versions.push(after); f.at = f.versions.len - 1; f.selection = after.selection;
}
fn sequences(count: i64) {
    var s = lab_document_store::create(lab_document_store::Limits { history: 16, bytes: 2048 });
    var models: Flat[..64] = [];
    for i in count { let id, code = lab_document_store::open(s, ""); assert(code == 0); models.push(Flat { id: id }); }
    var seed: u64 = 238147;
    for round in 2400 {
        seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
        let slot = (seed % (count as u64)) as i64; let choice = (seed >> 24) % 9; let f .= models[slot];
        let length = f.versions[f.at].bytes.len;
        if choice == 0 {
            let expected = f.at > 0; assert(lab_document_store::undo(s, f.id) == expected);
            if expected { f.selection = f.versions[f.at].old_selection; f.at--; }
        } else if choice == 1 {
            let expected = f.at + 1 < f.versions.len; assert(lab_document_store::redo(s, f.id) == expected);
            if expected { f.at++; f.selection = f.versions[f.at].selection; }
        } else if choice == 2 {
            assert(lab_document_store::mark_saved(s, f.id, f.versions[f.at].revision) == 0); f.saved = f.versions[f.at];
        } else if choice == 3 {
            let cursor = (seed % ((length + 1) as u64)) as i64;
            f.selection = lab_document_model::Selection { cursor, length }; assert(lab_document_store::select(s, f.id, cursor, length) == 0);
        } else if choice == 4 {
            let stale = f.id; assert(lab_document_store::close(s, stale) == 0);
            let fresh, code = lab_document_store::open(s, ""); assert(code == 0); f = Flat { id: fresh };
            assert(lab_document_store::replace(s, stale, 0, 0, "x") == lab_document_store::STALE);
            assert(lab_document_store::mark_saved(s, stale, 1) == lab_document_store::STALE);
        } else if choice == 5 {
            lab_document_store::collect(s);
        } else {
            let start = (seed % ((length + 1) as u64)) as i64; let end = min(length, start + (round % 5));
            let insertion: u8[..4] = if round % 3 == 0 { "" } else if round % 2 == 0 { "abc" } else { "x\ny" };
            assert(lab_document_store::replace(s, f.id, start, end, insertion) == 0); edit(f, start, end, insertion);
        }
        check(s, f);
        if round % 31 == 0 { for model in models { check(s, model); } }
    }
    lab_document_store::collect(s); for model in models { check(s, model); }
    for parity in 2 { for i in count { if i % 2 == parity { assert(lab_document_store::close(s, models[i].id) == 0); } else if parity == 0 { check(s, models[i]); } } lab_document_store::collect(s); }
    let end = lab_document_store::stats(s); assert(end.documents == 0 && end.nodes == 0 && end.text == 0 && end.used == 0);
    print(count, " documents: 2400 independent snapshot-model operations passed");
}
fn three_documents(path: const u8[:]) {
    var s = lab_document_store::create();
    let a, ac = lab_document_store::open(s, "A\r\n日本"); let b, bc = lab_document_store::open(s, "B"); let c, cc = lab_document_store::open(s, "C");
    assert(ac == 0 && bc == 0 && cc == 0);
    assert(lab_document_store::select(s, a, 1, 1) == 0 && lab_document_store::replace(s, a, 1, 1, "!") == 0);
    assert(lab_document_store::replace(s, b, 1, 1, "?") == 0 && lab_document_store::replace(s, c, 1, 1, "+") == 0);
    assert(lab_document_store::undo(s, a)); lab_document_store::collect(s);
    let aa, arc = lab_document_store::contents(s, a); let bb, brc = lab_document_store::contents(s, b); let cb, crc = lab_document_store::contents(s, c);
    assert(arc == 0 && brc == 0 && crc == 0 && aa == "A\r\n日本" && bb == "B?" && cb == "C+");
    assert(lab_document_store::redo(s, a));
    let published, pc = lab_document_store::contents(s, b); assert(pc == 0);
    assert(!write_file_atomic(str(path, "/missing/file.txt"), published) && lab_document_store::dirty(s, b));
    assert(write_file_atomic(path, published)); let revision = lab_document_store::revision(s, b);
    assert(lab_document_store::mark_saved(s, b, revision) == 0);
    assert(lab_document_store::replace(s, b, 2, 2, "x") == 0 && lab_document_store::mark_saved(s, b, revision) == lab_document_store::STALE);
    assert(lab_document_store::undo(s, b) && !lab_document_store::dirty(s, b)); lab_document_store::collect(s);
    let baseline, sc = lab_document_store::baseline(s, b); assert(sc == 0 && baseline == published);
    assert(lab_document_store::redo(s, b) && lab_document_store::dirty(s, b));
    assert(lab_document_store::close(s, a) == 0); let new_a, nac = lab_document_store::open(s, "new"); assert(nac == 0 && new_a.generation != a.generation);
    assert(lab_document_store::mark_saved(s, a, 2) == lab_document_store::STALE && lab_document_store::close(s, a) == lab_document_store::STALE);
    lab_document_store::close_all(s); assert(published == "B?"); assert(delete_file(path));
}
fn limits() {
    var s = lab_document_store::create(lab_document_store::Limits { documents: 2, history: 2, bytes: 16, text: 128, nodes: 2048 });
    let a, ac = lab_document_store::open(s, "日\r\n"); let b, bc = lab_document_store::open(s, "keep"); assert(ac == 0 && bc == 0);
    let no, nc = lab_document_store::open(s, ""); assert(nc == lab_document_store::LIMIT);
    assert(lab_document_store::replace(s, a, 1, 1, "x") == lab_document_store::INVALID);
    assert(lab_document_store::replace(s, a, 4, 4, "x") == lab_document_store::INVALID);
    assert(lab_document_store::replace(s, a, 0, 0, [0xFF]) == lab_document_store::INVALID);
    assert(lab_document_store::replace(s, a, 0, 0, [0]) == lab_document_store::INVALID);
    assert(lab_document_store::replace(s, a, 0, 0, "12345678901234567") == lab_document_store::LIMIT);
    for text in ["1", "2", "3"] { assert(lab_document_store::replace(s, a, 0, 0, text) == 0); }
    assert(lab_document_store::undo(s, a) && lab_document_store::undo(s, a) && !lab_document_store::undo(s, a));
    assert(lab_document_store::replace(s, a, 0, 1, "X") == 0 && !lab_document_store::redo(s, a));
    lab_document_store::collect(s); let saved, sc = lab_document_store::baseline(s, a); assert(sc == 0 && saved == "日\r\n");
    let neighbor, ns = lab_document_store::contents(s, b); assert(ns == 0 && neighbor == "keep"); lab_document_store::close_all(s);
    // Text pressure: rejection keeps history/saved state; closing a neighbor
    // lets collection reclaim its text and the same request then succeeds.
    var small = lab_document_store::create(lab_document_store::Limits { text: 8, nodes: 2048 });
    let x, xc = lab_document_store::open(small, "abcd"); let y, yc = lab_document_store::open(small, "keep"); assert(xc == 0 && yc == 0);
    assert(lab_document_store::replace(small, x, 0, 1, "X") == lab_document_store::LIMIT);
    let old, oc = lab_document_store::contents(small, x); assert(oc == 0 && old == "abcd" && !lab_document_store::undo(small, x));
    assert(lab_document_store::close(small, y) == 0 && lab_document_store::replace(small, x, 0, 1, "X") == 0);
    lab_document_store::collect(small); assert(lab_document_store::undo(small, x)); let restored, rc = lab_document_store::contents(small, x); assert(rc == 0 && restored == old);
    lab_document_store::close_all(small);
    var empty = lab_document_store::create(lab_document_store::Limits { arena: 0 });
    let ei, ec = lab_document_store::open(empty, ""); assert(ec == 0 && lab_document_store::replace(empty, ei, 0, 0, "x") == lab_document_store::LIMIT);
    assert(lab_document_store::size(empty, ei) == 0 && !lab_document_store::undo(empty, ei));
    var nodes = lab_document_store::create(lab_document_store::Limits { nodes: 1 });
    let ni, no = lab_document_store::open(nodes, "node"); assert(no == 0);
    assert(lab_document_store::replace(nodes, ni, 0, 1, "N") == lab_document_store::LIMIT);
    let node_text, nt = lab_document_store::contents(nodes, ni); assert(nt == 0 && node_text == "node" && !lab_document_store::dirty(nodes, ni));
    assert(!lab_document_store::undo(nodes, ni) && lab_document_store::mark_saved(nodes, ni, 1) == 0);
    // The arena bound includes reserved node capacity, not just live text/nodes.
    var arena = lab_document_store::create(lab_document_store::Limits { arena: 456 });
    let ar, arc = lab_document_store::open(arena, "abcd"); assert(arc == 0); // 8 node slots plus one text word.
    assert(lab_document_store::replace(arena, ar, 0, 1, "A") == lab_document_store::LIMIT);
    let ar_text, atc = lab_document_store::baseline(arena, ar); assert(atc == 0 && ar_text == "abcd" && lab_document_store::revision(arena, ar) == 1);
    lab_document_store::close_all(empty); lab_document_store::close_all(nodes); lab_document_store::close_all(arena);
}
fn two_stores() {
    var a = lab_document_store::create(); var b = lab_document_store::create();
    let ai, ac = lab_document_store::open(a, "one"); let bi, bc = lab_document_store::open(b, "two"); assert(ac == 0 && bc == 0);
    assert(lab_document_store::replace(a, ai, 0, 1, "O") == 0); lab_document_store::close_all(a); lab_document_store::collect(b);
    let text, code = lab_document_store::contents(b, bi); assert(code == 0 && text == "two"); lab_document_store::close_all(b);
}
fn many_pieces() {
    var s = lab_document_store::create(lab_document_store::Limits { history: 16 });
    assert(experiment_pool_document::configure(experiment_pool_document::Limits { history: 16 }));
    var tree_ids: lab_document_store::Id[..3] = []; var flat_ids: experiment_pool_document::Id[..3] = [];
    var initial: u8[>..] = []; for i in 60000 { initial.push(if i % 79 == 0 { '\n' } else { 'a' }); }
    for i in 3 {
        initial[1] = ('a' + i) as u8;
        let id, code = lab_document_store::open(s, initial); let flat, fc = experiment_pool_document::open(initial);
        assert(code == 0 && fc == 0); tree_ids.push(id); flat_ids.push(flat);
    }
    var seed: u64 = 981427;
    for step in 600 {
        seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
        let slot = (seed % 3) as i64; let id = tree_ids[slot]; let flat = flat_ids[slot]; let choice = (seed >> 24) % 7;
        if choice == 0 { assert(lab_document_store::undo(s, id) == experiment_pool_document::undo(flat)); }
        else if choice == 1 { assert(lab_document_store::redo(s, id) == experiment_pool_document::redo(flat)); }
        else if choice == 2 {
            assert(lab_document_store::mark_saved(s, id, lab_document_store::revision(s, id)) == 0);
            assert(experiment_pool_document::mark_saved(flat, experiment_pool_document::revision(flat)) == 0);
        } else if choice == 3 {
            let current, rc = experiment_pool_document::contents(flat); assert(rc == 0);
            let before = lab_document_store::stats(s); let old_revision = lab_document_store::revision(s, id);
            assert(lab_document_store::replace(s, id, 0, current.len, current) == 0);
            assert(lab_document_store::revision(s, id) == old_revision && lab_document_store::stats(s).inserted == before.inserted);
        } else {
            let length = lab_document_store::size(s, id); let start = (seed % ((length + 1) as u64)) as i64;
            let end = min(length, start + (step % 2049)); var insertion: u8[..2048] = [];
            for i in (step % 1537) { insertion.push(if i % 89 == 0 { '\n' } else { ('A' + step % 26) as u8 }); }
            assert(lab_document_store::replace(s, id, start, end, insertion) == experiment_pool_document::replace(flat, start, end, insertion));
        }
        if step % 7 == 0 { lab_document_store::collect(s); }
        for i in 3 {
            let actual, ac = lab_document_store::contents(s, tree_ids[i]); let expected, ec = experiment_pool_document::contents(flat_ids[i]);
            let saved, sc = lab_document_store::baseline(s, tree_ids[i]); let baseline, bc = experiment_pool_document::baseline(flat_ids[i]);
            assert(ac == 0 && ec == 0 && sc == 0 && bc == 0 && actual == expected && saved == baseline);
            assert(lab_document_store::revision(s, tree_ids[i]) == experiment_pool_document::revision(flat_ids[i]));
            assert(lab_document_store::dirty(s, tree_ids[i]) == experiment_pool_document::dirty(flat_ids[i]));
            let ts = lab_document_store::selection(s, tree_ids[i]); let fs = experiment_pool_document::selection(flat_ids[i]);
            assert(ts.cursor == fs.cursor && ts.anchor == fs.anchor);
        }
    }
    lab_document_store::close_all(s); experiment_pool_document::close_all();
    assert(lab_document_store::stats(s).used == 0 && experiment_pool_document::stats().used == 0);
    print("three 60000-byte documents: 600 cross-piece snapshot comparisons passed");
}
fn main() { let argv = args(); assert(argv.len == 2); three_documents(argv[1]); limits(); two_stores(); sequences(3); sequences(16); sequences(64); many_pieces(); }
