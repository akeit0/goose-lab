// Equal edit/history/save traces for snapshots and an explicit shared tree Store.
import std;
import os;
import experiments.pool_document;
import lab.document.store;
fn source(length: i64, shape: const u8[:], index: i64) -> u8[>..] {
    var text: u8[>..] = ['q', ('a' + index % 26) as u8];
    if shape == "unicode" { while text.len + 10 <= length { text.append("日é🙂"); } }
    while text.len < length { text.push(if shape == "lines" && text.len % 80 == 79 { '\n' } else { 'a' }); } text
}
fn snapshot_row(operation: const u8[:], elapsed: i64) {
    let s = experiment_pool_document::stats(); var history: i64 = 0;
    for d in experiment_pool_document::documents { if d.open { history += d.versions.len - 1; } }
    print(operation, ",", elapsed, ",", s.documents, ",", s.current, ",", s.saved, ",", history,
        ",", s.used, ",", s.high_water, ",", s.high_water, ",", s.used, ",0,", s.copied, ",,,,,");
}
fn shared_row(operation: const u8[:], elapsed: i64, store: const lab_document_store::Store&) {
    let s = lab_document_store::stats(store);
    print(operation, ",", elapsed, ",", s.documents, ",", s.current, ",", s.saved, ",", s.history_roots / 2,
        ",", s.used, ",", s.arena, ",", s.high_water, ",", s.text, ",", s.nodes * 56, ",", s.inserted,
        ",", s.collected_bytes, ",", s.growth_moved, ",", s.node_writes, ",", s.collections, ",", s.scanned_nodes);
}
fn check_snapshot(ids: const experiment_pool_document::Id[:], size: i64, iterations: i64, shape: const u8[:], retired: bool) {
    for i in ids.len { if !retired || i % 2 == 1 {
        let text, code = experiment_pool_document::contents(ids[i]); var expected = source(size, shape, i);
        expected[0] = if iterations % 2 == 0 { 'a' } else { 'x' }; assert(code == 0 && text == expected);
    } }
}
fn check_shared(store: const lab_document_store::Store&, ids: const lab_document_store::Id[:], size: i64, iterations: i64, shape: const u8[:], retired: bool) {
    for i in ids.len { if !retired || i % 2 == 1 {
        let text, code = lab_document_store::contents(store, ids[i]); var expected = source(size, shape, i);
        expected[0] = if iterations % 2 == 0 { 'a' } else { 'x' }; assert(code == 0 && text == expected);
    } }
}
fn snapshots(count: i64, size: i64, iterations: i64, shape: const u8[:], history: i64) {
    assert(experiment_pool_document::configure(experiment_pool_document::Limits { history: history }));
    var ids: experiment_pool_document::Id[..64] = [];
    for i in count { let text = source(size, shape, i); let start = clock_ns(); let id, code = experiment_pool_document::open(text); assert(code == 0); ids.push(id); snapshot_row("open", clock_ns() - start); }
    for round in iterations {
        for i in count {
            let start = clock_ns(); assert(experiment_pool_document::replace(ids[i], 0, 1, if round % 2 == 0 { "x" } else { "a" }) == 0); snapshot_row("edit", clock_ns() - start);
            let undo_start = clock_ns(); assert(experiment_pool_document::undo(ids[i])); snapshot_row("undo", clock_ns() - undo_start);
            let redo_start = clock_ns(); assert(experiment_pool_document::redo(ids[i])); snapshot_row("redo", clock_ns() - redo_start);
            if round % 8 == 0 { let saved = clock_ns(); assert(experiment_pool_document::mark_saved(ids[i], experiment_pool_document::revision(ids[i])) == 0); snapshot_row("mark_saved", clock_ns() - saved); }
        }
        if round % 8 == 0 { snapshot_row("checkpoint", 0); }
    }
    check_snapshot(ids, size, iterations, shape, false);
    for i in count { if i % 2 == 0 { let start = clock_ns(); assert(experiment_pool_document::close(ids[i]) == 0); snapshot_row("close", clock_ns() - start); } }
    snapshot_row("checkpoint", 0); check_snapshot(ids, size, iterations, shape, true);
    for i in count { if i % 2 == 0 {
        let old = ids[i]; let text = source(size, shape, i); let start = clock_ns(); let fresh, code = experiment_pool_document::open(text); assert(code == 0 && !experiment_pool_document::valid(old)); ids[i] = fresh; snapshot_row("reopen", clock_ns() - start);
        let actual, rc = experiment_pool_document::contents(fresh); assert(rc == 0 && actual == text);
    } }
    check_snapshot(ids, size, iterations, shape, true);
    let start = clock_ns(); experiment_pool_document::close_all(); snapshot_row("close_all", clock_ns() - start);
}
fn shared(count: i64, size: i64, iterations: i64, shape: const u8[:], history: i64) {
    var store = lab_document_store::create(lab_document_store::Limits { history: history });
    var ids: lab_document_store::Id[..64] = [];
    for i in count { let text = source(size, shape, i); let start = clock_ns(); let id, code = lab_document_store::open(store, text); assert(code == 0); ids.push(id); shared_row("open", clock_ns() - start, store); }
    for round in iterations {
        for i in count {
            let start = clock_ns(); assert(lab_document_store::replace(store, ids[i], 0, 1, if round % 2 == 0 { "x" } else { "a" }) == 0); shared_row("edit", clock_ns() - start, store);
            let undo_start = clock_ns(); assert(lab_document_store::undo(store, ids[i])); shared_row("undo", clock_ns() - undo_start, store);
            let redo_start = clock_ns(); assert(lab_document_store::redo(store, ids[i])); shared_row("redo", clock_ns() - redo_start, store);
            if round % 8 == 0 { let saved = clock_ns(); assert(lab_document_store::mark_saved(store, ids[i], lab_document_store::revision(store, ids[i])) == 0); shared_row("mark_saved", clock_ns() - saved, store); }
        }
        if round % 8 == 0 { let start = clock_ns(); lab_document_store::collect(store); shared_row("collect", clock_ns() - start, store); }
    }
    check_shared(store, ids, size, iterations, shape, false);
    for i in count { if i % 2 == 0 { let start = clock_ns(); assert(lab_document_store::close(store, ids[i]) == 0); shared_row("close", clock_ns() - start, store); } }
    let collect_start = clock_ns(); lab_document_store::collect(store); shared_row("collect", clock_ns() - collect_start, store); check_shared(store, ids, size, iterations, shape, true);
    for i in count { if i % 2 == 0 {
        let old = ids[i]; let text = source(size, shape, i); let start = clock_ns(); let fresh, code = lab_document_store::open(store, text); assert(code == 0 && !lab_document_store::valid(store, old)); ids[i] = fresh; shared_row("reopen", clock_ns() - start, store);
        let actual, rc = lab_document_store::contents(store, fresh); assert(rc == 0 && actual == text);
    } }
    check_shared(store, ids, size, iterations, shape, true);
    let start = clock_ns(); lab_document_store::close_all(store); shared_row("close_all", clock_ns() - start, store);
}
fn main() {
    let argv = args(); assert(argv.len == 7);
    let count, co = parse_int(argv[2]); let size, so = parse_int(argv[3]); let iterations, io = parse_int(argv[4]); let history, ho = parse_int(argv[6]);
    assert(co && so && io && ho && count >= 1 && count <= 64 && size >= 2 && size <= 2097152 && iterations >= 1 && iterations <= 10000 && history >= 1 && history <= 256);
    assert(argv[5] == "lines" || argv[5] == "long-line" || argv[5] == "unicode");
    print("operation,elapsed_ns,documents,current_bytes,saved_bytes,history_versions,used_bytes,arena_bytes,high_water_bytes,text_bytes,node_bytes,inserted_bytes,collected_bytes,growth_moved_bytes,node_writes,collections,scanned_nodes");
    if argv[1] == "snapshot" { snapshots(count, size, iterations, argv[5], history); }
    else { assert(argv[1] == "shared-tree"); shared(count, size, iterations, argv[5], history); }
}
