import std;
import os;
import lab.io.admission;
import lab.io.cancel;
import lab.io.stream;
import lab.io.event_loop;
import lab.fs.async_files;
import lab.fs.search;
import lab.fs.search_clients;
import lab.net.http;
import lab.net.http_clients;

fn queue_model(domains: i64) {
    var queue = lab_io_admission::create(lab_io_admission::Limits { domains: domains, pending: 17 });
    var seed: u64 = 19; var last: u64 = 0;
    for step in 600 {
        seed = (seed * 37 + 11) % 9973;
        let op = seed % 10; let domain = (seed / 10) % ((domains + 2) as u64); let key = (seed / 100) % 13;
        var d = lab_io_admission::Demand {}; var code: i32 = 0;
        let ticket = if step % 3 == 0 { seed % (queue.next_ticket + 2) } else { last };
        if op < 4 { let offered, c = lab_io_admission::enqueue(queue, domain as i64, key); d = offered; code = c; }
        else if op < 7 { let offered, c = lab_io_admission::peek(queue, key); d = offered; code = c; }
        else if op < 9 { code = lab_io_admission::accept(queue, ticket); }
        else { code = lab_io_admission::cancel(queue, ticket); }
        if d.ticket != 0 { last = d.ticket; }
        let stats = lab_io_admission::stats(queue);
        print("model,", domains, ",", step, ",", op, ",", domain, ",", key, ",", ticket, ",", code,
              ",", d.ticket, ",", d.domain, ",", d.key, ",", stats.pending, ",", stats.queued, ",", stats.accepted, ",", stats.cancelled);
    }
    queue.next_ticket = 0xFFFFFFFFFFFFFFFF;
    let rejected, code = lab_io_admission::enqueue(queue, 0, 999); assert(code == lab_io_admission::LIMIT && rejected.ticket == 0);
}
fn queue_capacity() {
    var queue = lab_io_admission::create(lab_io_admission::Limits { domains: 8, pending: 128 });
    for i in 128 { let d, code = lab_io_admission::enqueue(queue, i % 8, (i / 8) as u64); assert(code == 0 && d.ticket == (i + 1) as u64); }
    let image = to_bytes([queue]);
    let overflow, oc = lab_io_admission::enqueue(queue, 0, 16); assert(oc == lab_io_admission::LIMIT && overflow.ticket == 0);
    assert(lab_io_admission::accept(queue, 9) == lab_io_admission::BUSY); // Not the FIFO head.
    assert(lab_io_admission::accept(queue, 2) == lab_io_admission::BUSY); // Not this domain's turn.
    assert(to_bytes([queue]) == image);
    assert(lab_io_admission::accept(queue, 2, 2) == 0); // Domain 1 alone is eligible.
    let after = to_bytes([queue]);
    let zero, zc = lab_io_admission::peek(queue, 0); assert(zc == lab_io_admission::EMPTY && zero.ticket == 0);
    let high, hc = lab_io_admission::peek(queue, (1 as u64) << 50); assert(hc == lab_io_admission::EMPTY && high.ticket == 0);
    assert(lab_io_admission::accept(queue, 3, 0) == lab_io_admission::BUSY && to_bytes([queue]) == after);
    assert(lab_io_admission::cancel(queue, 1) == 0 && lab_io_admission::cancel(queue, 1) == lab_io_admission::STALE);
    let newer, nc = lab_io_admission::enqueue(queue, 0, 16); assert(nc == 0 && newer.ticket == 129);
    let head, pc = lab_io_admission::peek(queue, 1); assert(pc == 0 && head.ticket == 9);
    while lab_io_admission::stats(queue).pending > 0 {
        let d, code = lab_io_admission::peek(queue, 255 | ((1 as u64) << 50)); assert(code == 0);
        print("boundary,", d.ticket, ",", d.domain, ",", d.key);
        assert(lab_io_admission::accept(queue, d.ticket) == 0);
    }
    let stats = lab_io_admission::stats(queue); assert(stats.queued == 129 && stats.accepted == 128 && stats.cancelled == 1);
    let empty, ec = lab_io_admission::peek(queue); assert(ec == lab_io_admission::EMPTY && empty.ticket == 0);
    print("boundary-complete,", stats.queued, ",", stats.accepted, ",", stats.cancelled);
}
fn tokens_available(expected: i64) {
    var tokens: lab_io_cancel::Token[..64] = [];
    for i in expected { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
    assert(lab_io_cancel::create().id == 0);
    for i in tokens.len { lab_io_cancel::destroy(tokens[i]); }
}
fn native_slots(root: const u8[:]) {
    var contexts: lab_io_event_loop::Context[..64] = [];
    for i in 64 { let c = lab_io_event_loop::create(); assert(c.code == 0); contexts.push(c); }
    assert(lab_io_event_loop::create().code == lab_io_event_loop::LIMIT);
    var reads: lab_fs_async_files::Read[..16] = []; var listings: lab_fs_async_files::Listing[..16] = [];
    for i in 16 {
        let r = lab_fs_async_files::read(contexts[0], str(root, "/data.txt")); assert(r.code == 0); reads.push(r);
        let l = lab_fs_async_files::list(contexts[0], root); assert(l.code == 0); listings.push(l);
    }
    assert(lab_fs_async_files::read(contexts[0], str(root, "/data.txt")).code == lab_io_event_loop::LIMIT);
    assert(lab_fs_async_files::list(contexts[0], root).code == lab_io_event_loop::LIMIT);
    for i in 16 { assert(lab_fs_async_files::close(reads[i]) && lab_fs_async_files::close(listings[i])); }
    for i in contexts.len { assert(lab_io_event_loop::info(contexts[i]).resources == 0 && lab_io_event_loop::close(contexts[i])); }
}
fn page(s: lab_fs_search_clients::Service&, id: lab_io_stream::Id) -> lab_io_stream::Page<lab_fs_search::Batch> {
    let until = clock_ns() + 10000000000;
    while !lab_io_stream::info(s.flow, id).ready { assert(clock_ns() < until); lab_io_stream::poll(s.flow); sleep_ms(1); }
    let p, code = lab_fs_search_clients::take(s, id); assert(code == 0); p
}
fn hits(p: const lab_io_stream::Page<lab_fs_search::Batch>&, round: i64) {
    assert(p.code == 0 && p.data.issues.len == 0);
    for h in p.data.hits { print("hit,", round, ",", p.receipt.client.generation, ",", p.receipt.serial,
        ",", h.path, ",", h.line, ",", h.column, ",", h.start, ",", h.end, ",", h.preview); }
}
fn search_result(s: lab_fs_search_clients::Service&, id: lab_io_stream::Id, round: i64) {
    let held = page(s, id); assert(!held.done && held.data.hits.len == 32 && held.receipt.sequence == 1);
    let image = to_bytes([held]); hits(held, round);
    let cancelled = round % 4 == 0;
    if cancelled { assert(lab_io_stream::cancel(s.flow, id) == 0); }
    else { assert(lab_io_stream::ack(s.flow, held.receipt) == 0); }
    var sequence: u64 = 2;
    loop {
        let p = page(s, id);
        if p.done {
            assert(p.code == (if cancelled { lab_io_stream::CANCELLED } else { 0 }) && p.data.progress.active == 0);
            print("search,", round, ",", p.receipt.client.generation, ",", p.receipt.serial, ",", p.code, ",", p.data.progress.matches);
            break;
        }
        assert(!cancelled && p.receipt.sequence == sequence); hits(p, round);
        assert(lab_io_stream::ack(s.flow, p.receipt) == 0); sequence++;
    }
    assert(to_bytes([held]) == image);
}
fn main() {
    let argv = args(); assert(argv.len == 4); let rounds, rc = parse_int(argv[3]); assert(rc && rounds >= 1 && rounds <= 4096);
    for domains in [2, 3, 8] { queue_model(domains); }
    queue_capacity();
    assert(lab_io_admission::create(lab_io_admission::Limits { domains: 0 }).code == lab_io_admission::INVALID);
    assert(lab_net_http::init() == 0);
    var http = lab_net_http_clients::create(lab_net_http_clients::Limits { clients: 4, workers: 2, body_bytes: 12288 });
    var search = lab_fs_search_clients::create(lab_io_stream::Limits { clients: 1, workers: 1 });
    var queue = lab_io_admission::create(lab_io_admission::Limits { domains: 2, pending: 5 });
    var ids: lab_net_http_clients::Id[..4] = [];
    for i in 4 { let id, code = lab_net_http_clients::open(http); assert(code == 0); ids.push(id); }
    var sid, sc = lab_io_stream::open(search.flow); assert(sc == 0);
    var saved: u8[..12000] = [];
    for round in rounds {
        let abandoned, ac = lab_io_admission::enqueue(queue, 1, 99); assert(ac == 0);
        assert(lab_io_admission::cancel(queue, abandoned.ticket) == 0 && lab_io_admission::cancel(queue, abandoned.ticket) == lab_io_admission::STALE);
        for i in 4 { let d, code = lab_io_admission::enqueue(queue, 0, i as u64); assert(code == 0); }
        let sd, code = lab_io_admission::enqueue(queue, 1, 0); assert(code == 0);
        let overflow, oc = lab_io_admission::enqueue(queue, 1, 100); assert(oc == lab_io_admission::LIMIT && overflow.ticket == 0);
        var tokens: lab_io_cancel::Token[..64] = [];
        for i in 64 { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
        let selected, pc = lab_io_admission::peek(queue); assert(pc == 0);
        let refused_h = lab_net_http_clients::get(http, ids[0], str(argv[1], "/value/refused"));
        let refused_s = lab_fs_search_clients::start(search, sid, argv[2], "needle");
        let again, again_code = lab_io_admission::peek(queue);
        assert(refused_h == lab_net_http_clients::LIMIT && refused_s == lab_io_stream::LIMIT && again_code == 0 && again.ticket == selected.ticket);
        print("refused,", round, ",", lab_net_http_clients::info(http, ids[0]).serial, ",", lab_io_stream::info(search.flow, sid).serial);
        lab_io_cancel::destroy(tokens[0]); // One shared slot, with a persistent HTTP backlog.
        while lab_io_admission::stats(queue).pending > 0 {
            lab_net_http_clients::poll(http); lab_io_stream::poll(search.flow);
            let d, dc = lab_io_admission::peek(queue); assert(dc == 0);
            if d.domain == 0 {
                let i = d.key as i64; let large = (round + i) % 3 == 0;
                let key = str(round, "-", i);
                let path: u8[>..] = if large { "/large" } else { str("/value/", key) };
                assert(lab_net_http_clients::get(http, ids[i], str(argv[1], path)) == 0);
                assert(lab_io_admission::accept(queue, d.ticket) == 0);
                print("admit,", round, ",0,", i);
                let until = clock_ns() + 10000000000;
                while !lab_net_http_clients::info(http, ids[i]).ready { assert(clock_ns() < until); lab_net_http_clients::poll(http); sleep_ms(1); }
                let value, vc = lab_net_http_clients::take(http, ids[i]); assert(vc == 0 && value.response.code == 0 && value.response.status == 200);
                if large { assert(value.response.body.len == 12000); for b in value.response.body { assert(b == 'x'); } }
                else { assert(value.response.body == key); }
                if round == 0 && i == 0 { saved.append(value.response.body); }
                print("http,", round, ",", i, ",", value.client.generation, ",", value.serial, ",", value.response.body.len);
            } else {
                assert(lab_fs_search_clients::start(search, sid, argv[2], "needle") == 0);
                assert(lab_io_admission::accept(queue, d.ticket) == 0); print("admit,", round, ",1,0");
                search_result(search, sid, round);
            }
            assert(lab_io_admission::accept(queue, d.ticket) == lab_io_admission::STALE);
        }
        for i in tokens.len { lab_io_cancel::destroy(tokens[i]); }
        tokens_available(64); native_slots(argv[2]);
        let hs = lab_net_http_clients::stats(http); let ss = lab_io_stream::stats(search.flow);
        let qs = lab_io_admission::stats(queue);
        assert(hs.inflight == 0 && hs.ready == 0 && hs.payload_bytes == 0 && hs.submitted == hs.completed && hs.storage_refused == 0);
        assert(ss.inflight == 0 && ss.ready == 0 && ss.held == 0 && ss.payload_bytes == 0 && ss.arena_bytes == 0 && ss.submitted == ss.completed);
        assert(qs.pending == 0 && qs.queued == (round + 1) * 6 && qs.accepted == (round + 1) * 5 && qs.cancelled == round + 1);
        assert(saved.len == 12000); for b in saved { assert(b == 'x'); }
        print("cycle,", round, ",", hs.submitted, ",", ss.submitted, ",", qs.queued, ",", qs.accepted, ",", qs.cancelled, ",", hs.arena_bytes, ",", ss.peak_arena_bytes);
        // Reuse slots/generations after retiring all native flights.
        let slot = round % 4; assert(lab_net_http_clients::close(http, ids[slot]) == 0);
        let fresh, fc = lab_net_http_clients::open(http); assert(fc == 0 && fresh.slot == slot && fresh.generation != ids[slot].generation); ids[slot] = fresh;
        if round % 4 == 0 {
            assert(lab_io_stream::close(search.flow, sid) == 0);
            let fresh_s, fsc = lab_io_stream::open(search.flow); assert(fsc == 0 && fresh_s.generation != sid.generation); sid = fresh_s;
        }
        if round % 8 == 7 || round == rounds - 1 {
            let sampled = lab_net_http::get(str(argv[1], "/checkpoint/", round)); assert(sampled.code == 0 && sampled.status == 200);
        }
    }
    lab_fs_search_clients::shutdown(search); lab_net_http_clients::shutdown(http);
    let hs = lab_net_http_clients::stats(http); let ss = lab_io_stream::stats(search.flow);
    assert(hs.clients == 0 && hs.workers == 0 && hs.inflight == 0 && hs.payload_bytes == 0 && ss.clients == 0 && ss.workers == 0 && ss.inflight == 0 && ss.arena_bytes == 0);
    tokens_available(64); native_slots(argv[2]); lab_net_http::shutdown();
    print("Admission service contracts passed,", rounds);
}
