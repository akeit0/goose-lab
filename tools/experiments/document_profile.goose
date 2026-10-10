// Emit per-operation timings and storage observations; Python records provenance.
import std;
import os;
import experiments.pool_document;
import lab.document.model;
import lab.document.piece_tree;
fn row(operation: const u8[:], elapsed: i64, s: experiment_pool_document::Stats) {
    print(operation, ",", elapsed, ",", s.documents, ",", s.current, ",", s.saved, ",", s.undo, ",", s.used, ",", s.high_water,
        ",", s.free, ",", s.largest_free, ",", s.copied, ",", s.zeroed, ",", s.allocations, ",", s.preflight_scans);
}
fn measure(operation: const u8[:], before: i64) { let elapsed = clock_ns() - before; row(operation, elapsed, experiment_pool_document::stats()); }
fn source(length: i64, shape: const u8[:]) -> u8[>..] {
    var text: u8[>..] = ['a'];
    if shape == "unicode" { while text.len + 10 <= length { text.append("日é🙂"); } }
    while text.len < length { text.push(if shape == "lines" && text.len % 80 == 79 { '\n' } else { 'a' }); } text
}
fn pooled(count: i64, size: i64, iterations: i64, shape: const u8[:]) {
    assert(experiment_pool_document::configure(experiment_pool_document::Limits { history: 32 }));
    let initial = source(size, shape); var ids: experiment_pool_document::Id[..64] = [];
    for i in count { let before = clock_ns(); let id, code = experiment_pool_document::open(initial); assert(code == 0); ids.push(id); measure("open", before); }
    for round in iterations {
        for i in count {
            let before = clock_ns(); assert(experiment_pool_document::replace(ids[i], 0, 1, if round % 2 == 0 { "x" } else { "a" }) == 0); measure("edit", before);
            let undo_start = clock_ns(); assert(experiment_pool_document::undo(ids[i])); measure("undo", undo_start);
            let redo_start = clock_ns(); assert(experiment_pool_document::redo(ids[i])); measure("redo", redo_start);
            if round % 8 == 0 { let save_start = clock_ns(); assert(experiment_pool_document::mark_saved(ids[i], experiment_pool_document::revision(ids[i])) == 0); measure("mark_saved", save_start); }
        }
    }
    for id in ids { let contents, code = experiment_pool_document::contents(id); assert(code == 0 && contents.len == size && contents[0] == (if iterations % 2 == 0 { 'a' } else { 'x' })); }
    for i in count {
        let slot = count - 1 - i; let old = ids[slot]; let before = clock_ns(); assert(experiment_pool_document::close(old) == 0); measure("close", before);
        let reopen_start = clock_ns(); let fresh, code = experiment_pool_document::open(initial); assert(code == 0 && !experiment_pool_document::valid(old)); ids[slot] = fresh; measure("reopen", reopen_start);
    }
    let before = clock_ns(); experiment_pool_document::close_all(); measure("close_all", before); assert(experiment_pool_document::stats().used == 0);
}
fn tree_row(operation: const u8[:], elapsed: i64, d: const lab_document_model::Document&) {
    // Roots share bytes: store counts physical text, not the sum of snapshots.
    // Pool/copy/zero counters are unavailable for this existing implementation.
    print(operation, ",", elapsed, ",1,", lab_document_model::size(d), ",", lab_document_piece_tree::size(d.tree, d.saved_root),
        ",,", d.tree.arena.len * 8, ",,,,,,,");
}
fn tree(size: i64, iterations: i64, shape: const u8[:]) {
    let initial = source(size, shape); let before = clock_ns(); var d = lab_document_model::create(initial); assert(d.code == 0); tree_row("open", clock_ns() - before, d);
    for round in iterations {
        let before = clock_ns(); let code, changed = lab_document_model::replace(d, 0, 1, if round % 2 == 0 { "x" } else { "a" }); assert(code == 0 && changed); tree_row("edit", clock_ns() - before, d);
        let undo_start = clock_ns(); assert(lab_document_model::undo(d)); tree_row("undo", clock_ns() - undo_start, d);
        let redo_start = clock_ns(); assert(lab_document_model::redo(d)); tree_row("redo", clock_ns() - redo_start, d);
        if round % 8 == 0 { let save_start = clock_ns(); lab_document_model::mark_saved(d); tree_row("mark_saved", clock_ns() - save_start, d); }
    }
    let bytes = lab_document_model::contents(d); assert(bytes.len == size && bytes[0] == (if iterations % 2 == 0 { 'a' } else { 'x' }));
}
fn main() {
    let argv = args(); assert(argv.len == 6);
    let count, count_ok = parse_int(argv[2]); let size, size_ok = parse_int(argv[3]); let iterations, iterations_ok = parse_int(argv[4]);
    assert(count_ok && count >= 1 && count <= 64 && size_ok && size >= 1 && size <= 2097152 && iterations_ok && iterations >= 1 && iterations <= 10000);
    assert(argv[5] == "lines" || argv[5] == "long-line" || argv[5] == "unicode");
    print("operation,elapsed_ns,documents,current_bytes,saved_bytes,undo_bytes,used_bytes,pool_high_water_bytes,pool_free_bytes,largest_free_run_bytes,copied_bytes,zeroed_bytes,allocations,preflight_scans");
    if argv[1] == "snapshot" { pooled(count, size, iterations, argv[5]); }
    else { assert(argv[1] == "piece-tree" && count == 1); tree(size, iterations, argv[5]); }
}
