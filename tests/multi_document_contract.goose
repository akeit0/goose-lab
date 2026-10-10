import std;
import os;
import experiments.pool_document;
import lab.document.model;
fn text(id: experiment_pool_document::Id, expected: const u8[:]) {
    let bytes, code = experiment_pool_document::contents(id); assert(code == 0 && bytes == expected);
}
fn three_documents(path: const u8[:]) {
    let a, ac = experiment_pool_document::open("A\r\n日本"); let b, bc = experiment_pool_document::open("B");
    let c, cc = experiment_pool_document::open("C"); assert(ac == 0 && bc == 0 && cc == 0);
    assert(experiment_pool_document::select(a, 1, 1) == 0);
    assert(experiment_pool_document::replace(a, 1, 1, "!") == 0);
    assert(experiment_pool_document::replace(b, 1, 1, "?") == 0);
    assert(experiment_pool_document::replace(c, 1, 1, "+") == 0);
    assert(experiment_pool_document::dirty(a) && experiment_pool_document::dirty(b) && experiment_pool_document::dirty(c));
    assert(experiment_pool_document::undo(a)); text(a, "A\r\n日本"); text(b, "B?"); text(c, "C+");
    assert(!experiment_pool_document::dirty(a)); assert(experiment_pool_document::selection(a).cursor == 1);
    assert(experiment_pool_document::redo(a)); text(a, "A!\r\n日本");
    assert(experiment_pool_document::select(b, 0, 2) == 0);
    let old_b_revision = experiment_pool_document::revision(b);
    assert(experiment_pool_document::replace(b, 0, 2, "B edited") == 0);
    assert(experiment_pool_document::mark_saved(b, old_b_revision) == experiment_pool_document::STALE);
    assert(experiment_pool_document::close(a) == 0);
    let new_a, code = experiment_pool_document::open("new A"); assert(code == 0 && new_a.slot == a.slot && new_a.generation != a.generation);
    assert(experiment_pool_document::replace(a, 0, 0, "stale search") == experiment_pool_document::STALE);
    assert(experiment_pool_document::mark_saved(a, 2) == experiment_pool_document::STALE);
    assert(experiment_pool_document::select(a, 0, 0) == experiment_pool_document::STALE);
    assert(!experiment_pool_document::undo(a) && experiment_pool_document::close(a) == experiment_pool_document::STALE);
    text(new_a, "new A"); text(b, "B edited"); text(c, "C+");
    let publication, pc = experiment_pool_document::contents(b); assert(pc == 0);
    assert(!write_file_atomic(str(path, "/missing/child.txt"), publication));
    assert(experiment_pool_document::dirty(b)); text(b, "B edited");
    assert(write_file_atomic(path, publication));
    assert(experiment_pool_document::mark_saved(b, experiment_pool_document::revision(b)) == 0);
    var disk: u8[>..] = []; assert(read_file(path, disk) && disk == "B edited");
    let saved, saved_code = experiment_pool_document::baseline(b); assert(saved_code == 0 && saved == "B edited");
    assert(!experiment_pool_document::dirty(b) && experiment_pool_document::dirty(c));
    assert(experiment_pool_document::undo(b)); text(b, "B?"); assert(experiment_pool_document::selection(b).cursor == 0 && experiment_pool_document::selection(b).anchor == 2);
    assert(experiment_pool_document::dirty(b)); assert(experiment_pool_document::redo(b)); assert(!experiment_pool_document::dirty(b));
    assert(experiment_pool_document::undo(c)); text(c, "C"); assert(experiment_pool_document::redo(c)); text(c, "C+");
    experiment_pool_document::close_all(); assert(experiment_pool_document::stats().used == 0);
    assert(experiment_pool_document::mark_saved(new_a, 1) == experiment_pool_document::STALE);
}
fn limits_and_boundaries() {
    let high = experiment_pool_document::stats().high_water;
    assert(experiment_pool_document::configure(experiment_pool_document::Limits { documents: 3, bytes: 16, history: 2, pool: max(high, 128) }));
    let a, code = experiment_pool_document::open("日\r\n"); assert(code == 0);
    assert(experiment_pool_document::select(a, 1, 0) == experiment_pool_document::INVALID);
    assert(experiment_pool_document::replace(a, 4, 4, "x") == experiment_pool_document::INVALID);
    assert(experiment_pool_document::replace(a, 0, 0, [0xFF]) == experiment_pool_document::INVALID);
    assert(experiment_pool_document::replace(a, 0, 0, [0]) == experiment_pool_document::INVALID);
    assert(experiment_pool_document::replace(a, 0, 0, "01234567890123456") == experiment_pool_document::LIMIT);
    text(a, "日\r\n"); assert(!experiment_pool_document::dirty(a) && !experiment_pool_document::undo(a));
    assert(experiment_pool_document::replace(a, 0, 0, "1") == 0);
    assert(experiment_pool_document::replace(a, 0, 0, "2") == 0);
    assert(experiment_pool_document::replace(a, 0, 0, "3") == 0);
    assert(experiment_pool_document::undo(a) && experiment_pool_document::undo(a) && !experiment_pool_document::undo(a)); text(a, "1日\r\n");
    assert(experiment_pool_document::replace(a, 0, 1, "x") == 0 && !experiment_pool_document::redo(a));
    let baseline, bc = experiment_pool_document::baseline(a); assert(bc == 0 && baseline == "日\r\n");
    experiment_pool_document::close_all();
    let used = experiment_pool_document::stats(); assert(used.used == 0 && used.free == used.high_water && used.largest_free == used.high_water);
    // A budget refusal preserves every document and history; freeing a neighbor
    // permits allocation again without increasing the high-water length.
    assert(experiment_pool_document::configure(experiment_pool_document::Limits { documents: 3, bytes: 64, history: 2, pool: max(used.high_water, 128) }));
    let x, xc = experiment_pool_document::open("01234567890123456789012345678901");
    let y, yc = experiment_pool_document::open("01234567890123456789012345678901"); assert(xc == 0 && yc == 0);
    let before = experiment_pool_document::stats();
    assert(experiment_pool_document::replace(x, 0, 1, "x") == experiment_pool_document::LIMIT);
    text(x, "01234567890123456789012345678901"); assert(!experiment_pool_document::undo(x));
    assert(experiment_pool_document::close(y) == 0 && experiment_pool_document::replace(x, 0, 1, "x") == 0);
    assert(experiment_pool_document::stats().high_water == before.high_water);
    assert(experiment_pool_document::replace(x, 1, 2, "y") == 0);
    assert(experiment_pool_document::mark_saved(x, experiment_pool_document::revision(x)) == experiment_pool_document::LIMIT);
    let retained, retained_code = experiment_pool_document::baseline(x); assert(retained_code == 0 && retained == "01234567890123456789012345678901");
    assert(experiment_pool_document::dirty(x) && experiment_pool_document::undo(x) && experiment_pool_document::redo(x));
    experiment_pool_document::close_all();
    // Two new allocations may fit separate gaps even when no one gap holds
    // their combined length. Exercise the first-fit budget prediction.
    let p, pc = experiment_pool_document::open("0123456789012345");
    let q, qc = experiment_pool_document::open("0123456789012345");
    let r, rc = experiment_pool_document::open("0123456789012345"); assert(pc == 0 && qc == 0 && rc == 0);
    let extra, ec = experiment_pool_document::open("fourth"); assert(ec == experiment_pool_document::LIMIT);
    assert(experiment_pool_document::close(q) == 0);
    assert(experiment_pool_document::stats().largest_free == 32);
    let split, sc = experiment_pool_document::open("01234567890123456789012345678901"); assert(sc == 0);
    assert(experiment_pool_document::stats().high_water == before.high_water);
    text(p, "0123456789012345"); text(r, "0123456789012345");
    experiment_pool_document::close_all();
}
fn churn(count: i64) {
    assert(experiment_pool_document::configure(experiment_pool_document::Limits {}));
    var ids: experiment_pool_document::Id[..64] = [];
    for i in count { let id, code = experiment_pool_document::open("seed"); assert(code == 0); ids.push(id); }
    for i in count { assert(experiment_pool_document::replace(ids[i], 4, 4, "!") == 0); }
    let full, code = experiment_pool_document::open("overflow"); if count == 64 { assert(code == experiment_pool_document::LIMIT); } else { assert(code == 0); experiment_pool_document::close(full); }
    for round in 20 {
        for i in count {
            let slot = (i * (count - 1) + round) % count; let old = ids[slot];
            assert(experiment_pool_document::close(old) == 0);
            let fresh, code = experiment_pool_document::open("seed"); assert(code == 0); ids[slot] = fresh;
            assert(!experiment_pool_document::valid(old));
            assert(experiment_pool_document::replace(fresh, 4, 4, "!") == 0);
        }
        for id in ids { text(id, "seed!"); assert(experiment_pool_document::dirty(id)); assert(experiment_pool_document::undo(id)); text(id, "seed"); assert(experiment_pool_document::redo(id)); }
    }
    experiment_pool_document::close_all(); assert(experiment_pool_document::stats().used == 0);
}
fn differential() {
    assert(experiment_pool_document::configure(experiment_pool_document::Limits {}));
    let id, opened = experiment_pool_document::open("seed"); assert(opened == 0);
    var reference = lab_document_model::create("seed");
    for step in 700 {
        let size = lab_document_model::size(reference);
        if step % 19 == 0 { assert(experiment_pool_document::undo(id) == lab_document_model::undo(reference)); }
        else if step % 19 == 1 { assert(experiment_pool_document::redo(id) == lab_document_model::redo(reference)); }
        else if step % 17 == 0 { lab_document_model::mark_saved(reference); assert(experiment_pool_document::mark_saved(id, reference.revision) == 0); }
        else if step % 7 == 0 { let at = step % (size + 1); assert(lab_document_model::select(reference, at, size)); assert(experiment_pool_document::select(id, at, size) == 0); }
        else {
            let at = step % (size + 1); let end = min(size, at + (if step % 3 == 0 { 1 } else { 0 }));
            let insertion: u8[..1] = if step % 5 == 0 { "" } else if step % 2 == 0 { "x" } else { "y" };
            let code, changed = lab_document_model::replace(reference, at, end, insertion);
            assert(code == 0 && experiment_pool_document::replace(id, at, end, insertion) == 0);
        }
        let bytes, code = experiment_pool_document::contents(id); assert(code == 0 && bytes == lab_document_model::contents(reference));
        let saved, saved_code = experiment_pool_document::baseline(id); assert(saved_code == 0 && saved == lab_document_model::baseline(reference));
        assert(experiment_pool_document::revision(id) == reference.revision);
        assert(experiment_pool_document::dirty(id) == lab_document_model::dirty(reference));
        assert(experiment_pool_document::selection(id) == reference.selection);
    }
    experiment_pool_document::close_all(); assert(experiment_pool_document::stats().used == 0);
}
fn main() {
    let argv = args(); assert(argv.len == 2);
    three_documents(argv[1]); limits_and_boundaries(); differential(); churn(3); churn(16); churn(64);
    assert(delete_file(argv[1])); print("multi-document contract OK");
}
