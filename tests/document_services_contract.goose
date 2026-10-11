import std;
import os;
import experiments.document_requests;
import lab.document.store;
import lab.io.admission;
import lab.io.cancel;
import lab.io.stream;
import lab.fs.search;
import lab.fs.search_clients;
import lab.net.http;
import lab.net.http_clients;

fn ask(s: lab_experiment_document_requests::State&, docs: const lab_document_store::Store&, id: lab_document_store::Id,
       kind: i64, label: const u8[:], first: const u8[:], second: const u8[:],
       http: lab_net_http_clients::Service&, search: lab_fs_search_clients::Service&) {
    let key, code = lab_experiment_document_requests::request(s, docs, id, kind, first, second, http, search); assert(code == 0);
    print("request,", label, ",", id.slot, ",", id.generation, ",", lab_document_store::revision(docs, id), ",", key, ",", kind);
}
fn control(base: const u8[:], path: const u8[:]) {
    let result = lab_net_http::get(str(base, path)); assert(result.code == 0 && result.status == 200);
}
fn tokens_available(expected: i64) {
    var tokens: lab_io_cancel::Token[..64] = [];
    for i in expected { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
    assert(lab_io_cancel::create().id == 0); for i in tokens.len { lab_io_cancel::destroy(tokens[i]); }
}
fn wait_http(s: lab_experiment_document_requests::State&, slot: i64, http: lab_net_http_clients::Service&) -> lab_experiment_document_requests::HttpCompletion {
    let until = clock_ns() + 10000000000;
    loop {
        lab_net_http_clients::poll(http); let value, ready = lab_experiment_document_requests::receive_http(s, slot, http);
        if ready { return value; } assert(clock_ns() < until); sleep_ms(1);
    }
}
fn http_event(s: lab_experiment_document_requests::State&, docs: const lab_document_store::Store&,
              label: const u8[:], value: const lab_experiment_document_requests::HttpCompletion&) -> bool {
    let accepted = lab_experiment_document_requests::apply_http(s, docs, value);
    print("http,", label, ",", value.scope.document.slot, ",", value.scope.document.generation, ",", value.scope.revision,
          ",", value.scope.key, ",", value.serial, ",", value.code, ",", value.status, ",", value.body, ",", if accepted { 1 } else { 0 }); accepted
}
fn wait_search(s: lab_experiment_document_requests::State&, slot: i64, search: lab_fs_search_clients::Service&) -> lab_experiment_document_requests::SearchCompletion {
    let until = clock_ns() + 10000000000;
    loop {
        lab_io_stream::poll(search.flow); let value, ready = lab_experiment_document_requests::receive_search(s, slot, search);
        if ready { return value; } assert(clock_ns() < until); sleep_ms(1);
    }
}
fn search_event(s: lab_experiment_document_requests::State&, docs: const lab_document_store::Store&,
                label: const u8[:], value: const lab_experiment_document_requests::SearchCompletion&) -> bool {
    let accepted = lab_experiment_document_requests::apply_search(s, docs, value); let p .= value.page;
    print("page,", label, ",", value.scope.document.slot, ",", value.scope.document.generation, ",", value.scope.revision,
          ",", value.scope.key, ",", p.receipt.serial, ",", p.receipt.sequence, ",", if p.done { 1 } else { 0 }, ",", p.code,
          ",", p.data.hits.len, ",", if accepted { 1 } else { 0 });
    for h in p.data.hits {
        print("hit,", label, ",", h.path, ",", h.line, ",", h.column, ",", h.start, ",", h.end, ",", h.preview);
    } accepted
}
fn drain_search(s: lab_experiment_document_requests::State&, docs: const lab_document_store::Store&, slot: i64,
                label: const u8[:], search: lab_fs_search_clients::Service&) {
    loop {
        let value = wait_search(s, slot, search); assert(search_event(s, docs, label, value));
        if value.page.done { break; } assert(lab_experiment_document_requests::ack(s, docs, search, value) == 0);
    }
}
fn document_event(docs: const lab_document_store::Store&, id: lab_document_store::Id) {
    let text, code = lab_document_store::contents(docs, id); let base, bc = lab_document_store::baseline(docs, id);
    let selection = lab_document_store::selection(docs, id); assert(code == 0 && bc == 0);
    print("document,", id.slot, ",", id.generation, ",", lab_document_store::revision(docs, id), ",", if lab_document_store::dirty(docs, id) { 1 } else { 0 },
          ",", selection.cursor, ",", selection.anchor, ",", text, ",", base);
}
fn main() {
    let argv = args(); assert(argv.len == 3 && lab_net_http::init() == 0);
    var docs = lab_document_store::create(lab_document_store::Limits { documents: 3, bytes: 4096, history: 8, text: 65536, nodes: 512, arena: 131072 });
    var http = lab_net_http_clients::create(lab_net_http_clients::Limits { clients: 3, workers: 2, body_bytes: 512 });
    var search = lab_fs_search_clients::create(lab_io_stream::Limits { clients: 3, workers: 2 });
    var http_ids: lab_net_http_clients::Id[..3] = []; var search_ids: lab_io_stream::Id[..3] = [];
    for i in 3 {
        let h, hc = lab_net_http_clients::open(http); let f, fc = lab_io_stream::open(search.flow); assert(hc == 0 && fc == 0);
        http_ids.push(h); search_ids.push(f);
    }
    var prior = lab_experiment_document_requests::HttpCompletion {};
    for round in 3 {
        print("round,", round); var s = lab_experiment_document_requests::create(); var ids: lab_document_store::Id[..3] = [];
        for i in 3 {
            let text = str("doc-", round, "-", i); let id, code = lab_document_store::open(docs, text); assert(code == 0);
            ids.push(id); lab_experiment_document_requests::attach(s, docs, id, http_ids[i], search_ids[i]);
            assert(lab_document_store::select(docs, id, 3, 1) == 0); print("open,", i, ",", id.generation, ",", text);
        }
        {
            var probe = lab_experiment_document_requests::create();
            for i in 3 { lab_experiment_document_requests::attach(probe, docs, ids[i], http_ids[i], search_ids[i]); }
            for pass in 2 { for slot in 3 { for kind in 2 {
                let first: u8[>..] = if kind == 0 { str(argv[1], "/value/capacity-", pass, "-", slot) } else { str(argv[2]) };
                let key, code = lab_experiment_document_requests::request(probe, docs, ids[slot], kind, first, if kind == 1 { "needle" } else { "" }, http, search);
                assert(code == 0 && key == (pass * 6 + slot * 2 + kind + 1) as u64);
            } } }
            for lane in 6 { assert(probe.pending[lane].scope.key == (lane + 7) as u64); print("pending-slot,", lane, ",", probe.pending[lane].scope.key); }
            let image = to_bytes([probe]);
            let invalid, ic = lab_experiment_document_requests::request(probe, docs, ids[0], 0, "", "", http, search);
            assert(ic == lab_io_admission::INVALID && invalid == 0 && to_bytes([probe]) == image);
            let stats = lab_io_admission::stats(probe.queue); assert(stats.pending == 6 && stats.queued == 12 && stats.cancelled == 6 && probe.superseded == 6);
            for id in ids { lab_experiment_document_requests::invalidate(probe, id, http, search); }
            assert(lab_io_admission::stats(probe.queue).pending == 0); print("pending-capacity,6,6,12,0");
        }
        // New application owner reuses key 1 and revision 1. Old document
        // generation must still reject a real exported completion from prior.
        let epoch = str("epoch-", round);
        ask(s, docs, ids[0], 0, "epoch", str(argv[1], "/value/", epoch), "", http, search);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1);
        let fresh_epoch = wait_http(s, 0, http);
        if round > 0 { assert(!http_event(s, docs, "prior-controller", prior)); }
        assert(http_event(s, docs, "epoch", fresh_epoch)); prior = fresh_epoch;

        var tokens: lab_io_cancel::Token[..64] = [];
        for i in 64 { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
        ask(s, docs, ids[0], 0, "pending-old", str(argv[1], "/value/pending-old-", round), "", http, search);
        ask(s, docs, ids[0], 0, "pending-new", str(argv[1], "/value/pending-new-", round), "", http, search);
        ask(s, docs, ids[1], 1, "query-old", argv[2], "needle", http, search);
        ask(s, docs, ids[1], 1, "query-new", argv[2], "missing", http, search);
        ask(s, docs, ids[2], 0, "revision-pending", str(argv[1], "/value/revision-pending-", round), "", http, search);
        assert(lab_document_store::replace(docs, ids[2], lab_document_store::size(docs, ids[2]), lab_document_store::size(docs, ids[2]), "!") == 0); print("edit,2,!");
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 0 && s.stale_pending == 1 && lab_io_admission::stats(s.queue).pending == 2);
        print("blocked,2,0,0");
        lab_io_cancel::destroy(tokens[0]); lab_io_cancel::destroy(tokens[1]);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 2);
        let pending = wait_http(s, 0, http); assert(http_event(s, docs, "pending-new", pending));
        drain_search(s, docs, 1, "query-new", search);
        for i in tokens.len { lab_io_cancel::destroy(tokens[i]); } tokens_available(64);

        let old_key = str("active-old-", round);
        ask(s, docs, ids[0], 0, "active-old", str(argv[1], "/hold/", old_key), "", http, search);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1); control(argv[1], str("/ready/", old_key));
        ask(s, docs, ids[0], 0, "active-new", str(argv[1], "/value/active-new-", round), "", http, search);
        ask(s, docs, ids[2], 0, "live", str(argv[1], "/value/live-", round), "", http, search);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1 && s.flights[0].active && s.pending[0].ticket != 0);
        tokens_available(62); print("retained,active,62");
        let live = wait_http(s, 2, http); assert(http_event(s, docs, "live", live));
        let retired = wait_http(s, 0, http); assert(!http_event(s, docs, "active-old", retired)); control(argv[1], str("/release/", old_key));
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1);
        let replacement = wait_http(s, 0, http); assert(http_event(s, docs, "active-new", replacement));

        ask(s, docs, ids[1], 0, "delayed", str(argv[1], "/value/delayed-", round), "", http, search);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1); let delayed = wait_http(s, 1, http);
        ask(s, docs, ids[1], 0, "delayed-new", str(argv[1], "/value/delayed-new-", round), "", http, search);
        assert(!http_event(s, docs, "delayed", delayed));
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1);
        let delayed_new = wait_http(s, 1, http); assert(http_event(s, docs, "delayed-new", delayed_new));
        ask(s, docs, ids[2], 0, "revision-active", str(argv[1], "/value/revision-active-", round), "", http, search);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1); let revision = wait_http(s, 2, http);
        assert(lab_document_store::replace(docs, ids[2], lab_document_store::size(docs, ids[2]), lab_document_store::size(docs, ids[2]), "+") == 0); print("edit,2,+");
        assert(!http_event(s, docs, "revision-active", revision));

        ask(s, docs, ids[0], 1, "held-old", argv[2], "needle", http, search);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1);
        let held = wait_search(s, 0, search); assert(!held.page.done && search_event(s, docs, "held-old", held)); let image = to_bytes([held]);
        assert(!search_event(s, docs, "held-duplicate", held));
        ask(s, docs, ids[0], 1, "held-new", argv[2], "missing", http, search);
        ask(s, docs, ids[2], 0, "while-held", str(argv[1], "/value/while-held-", round), "", http, search);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1);
        let other = wait_http(s, 2, http); assert(http_event(s, docs, "while-held", other));
        let stopped = wait_search(s, 0, search); assert(stopped.page.done && !search_event(s, docs, "held-old", stopped));
        assert(lab_experiment_document_requests::ack(s, docs, search, held) == lab_io_stream::STALE); print("ack,held-old,3");
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 1); drain_search(s, docs, 0, "held-new", search);
        assert(to_bytes([held]) == image);

        let closed_key = str("close-old-", round);
        ask(s, docs, ids[1], 0, "close-old", str(argv[1], "/hold/", closed_key), "", http, search);
        ask(s, docs, ids[1], 1, "close-search", argv[2], "needle", http, search);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 2); control(argv[1], str("/ready/", closed_key));
        let closed_page = wait_search(s, 1, search); assert(search_event(s, docs, "close-search", closed_page)); let closed_image = to_bytes([closed_page]);
        ask(s, docs, ids[1], 0, "close-queued", str(argv[1], "/value/close-queued-", round), "", http, search);
        ask(s, docs, ids[1], 1, "close-query-queued", argv[2], "missing", http, search);
        lab_experiment_document_requests::close(s, docs, ids[1], http, search); print("close,1,", ids[1].generation);
        let reopened, roc = lab_document_store::open(docs, str("reopened-", round)); assert(roc == 0 && reopened.slot == 1 && reopened.generation != ids[1].generation); ids[1] = reopened;
        lab_experiment_document_requests::attach(s, docs, reopened, http_ids[1], search_ids[1]); print("open,1,", reopened.generation, ",reopened-", round);
        ask(s, docs, ids[1], 0, "reopened", str(argv[1], "/value/reopened-", round), "", http, search);
        ask(s, docs, ids[1], 1, "reopened-search", argv[2], "needle", http, search);
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 0); tokens_available(62); print("retained,closed,62");
        let closed_http = wait_http(s, 1, http); assert(!http_event(s, docs, "close-old", closed_http)); control(argv[1], str("/release/", closed_key));
        let closed_terminal = wait_search(s, 1, search); assert(closed_terminal.page.done && !search_event(s, docs, "close-search", closed_terminal));
        assert(lab_experiment_document_requests::ack(s, docs, search, closed_page) == lab_io_stream::STALE); print("ack,close-search,3");
        assert(lab_experiment_document_requests::dispatch(s, docs, http, search) == 2);
        let reopened_http = wait_http(s, 1, http); assert(http_event(s, docs, "reopened", reopened_http));
        assert(!http_event(s, docs, "reopened-duplicate", reopened_http)); drain_search(s, docs, 1, "reopened-search", search);
        assert(to_bytes([closed_page]) == closed_image);
        for i in 3 { document_event(docs, ids[i]); lab_experiment_document_requests::close(s, docs, ids[i], http, search); }
        assert(lab_io_admission::stats(s.queue).pending == 0 && s.admitted == s.finished && s.superseded == 2 && s.stale_pending == 1);
        for f in s.flights { assert(!f.active); }
        lab_document_store::collect(docs); assert(lab_document_store::stats(docs).documents == 0 && lab_document_store::stats(docs).used == 0);
        tokens_available(64); print("clean,", s.admitted, ",", s.finished, ",", s.superseded, ",", s.stale_pending);
    }
    lab_fs_search_clients::shutdown(search); lab_net_http_clients::shutdown(http); tokens_available(64);
    let hs = lab_net_http_clients::stats(http); let ss = lab_io_stream::stats(search.flow);
    assert(hs.clients == 0 && hs.workers == 0 && hs.inflight == 0 && hs.payload_bytes == 0 && hs.submitted == hs.completed);
    assert(ss.clients == 0 && ss.workers == 0 && ss.inflight == 0 && ss.arena_bytes == 0 && ss.submitted == ss.completed);
    lab_net_http::shutdown(); print("Document service contracts passed");
}
