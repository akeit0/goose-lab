import std;
import os;
import lab.net.http;
import lab.net.http_clients;
import lab.fs.search;
import lab.fs.search_clients;
import lab.fs.async_files;
import lab.io.stream;
import lab.io.cancel;
import lab.io.event_loop;

fn control(base: const u8[:], path: const u8[:]) {
    let value = lab_net_http::get(str(base, path), lab_net_http::Options { timeout_ms: 5000 });
    assert(value.code == 0 && value.status == 200);
}
fn http_result(s: lab_net_http_clients::Service&, id: lab_net_http_clients::Id,
               round: i64, label: const u8[:], expected: const u8[:]) -> lab_net_http_clients::Result {
    let until = clock_ns() + 10000000000;
    while !lab_net_http_clients::info(s, id).ready {
        assert(clock_ns() < until); lab_net_http_clients::poll(s, 3); sleep_ms(1);
    }
    let value, code = lab_net_http_clients::take(s, id);
    assert(code == 0 && value.response.code == 0 && value.response.status == 200 && value.response.body == expected);
    print("http,", round, ",", label, ",", value.client.slot, ",", value.client.generation, ",", value.serial, ",", value.response.status, ",", value.response.body);
    copy(value)
}
fn search_page(s: lab_fs_search_clients::Service&, id: lab_io_stream::Id) -> lab_io_stream::Page<lab_fs_search::Batch> {
    let until = clock_ns() + 10000000000;
    while !lab_io_stream::info(s.flow, id).ready {
        assert(clock_ns() < until); lab_io_stream::poll(s.flow, 5); sleep_ms(1);
    }
    let page, code = lab_fs_search_clients::take(s, id); assert(code == 0); page
}
fn held_page(s: lab_fs_search_clients::Service&, id: lab_io_stream::Id) -> lab_io_stream::Page<lab_fs_search::Batch> {
    let page = search_page(s, id);
    assert(!page.done && page.data.hits.len == 32 && page.data.issues.len == 0);
    assert(lab_io_stream::info(s.flow, id).held && lab_io_stream::stats(s.flow).inflight == 1);
    page
}
fn emit_search(page: const lab_io_stream::Page<lab_fs_search::Batch>&, round: i64, label: const u8[:]) {
    assert(page.code == 0 && page.data.code == 0 && page.data.issues.len == 0);
    for hit in page.data.hits {
        print("hit,", round, ",", label, ",", page.receipt.client.slot, ",", page.receipt.client.generation, ",", page.receipt.serial,
              ",", hit.path, ",", hit.line, ",", hit.column, ",", hit.start, ",", hit.end, ",", hit.preview);
    }
    if page.done {
        assert(page.data.done && page.data.result == 0 && page.data.progress.active == 0);
        print("done,", round, ",", label, ",", page.receipt.client.slot, ",", page.receipt.client.generation, ",", page.receipt.serial, ",", page.data.progress.matches);
    }
}
fn consume_search(s: lab_fs_search_clients::Service&, id: lab_io_stream::Id, round: i64, label: const u8[:], sequence: u64 = 1) {
    var next = sequence;
    loop {
        let page = search_page(s, id);
        assert(page.receipt.sequence == next && page.receipt.client.slot == id.slot && page.receipt.client.generation == id.generation);
        emit_search(page, round, label); if page.done { break; }
        assert(lab_io_stream::ack(s.flow, page.receipt) == 0); next++;
    }
}
fn tokens_available(expected: i64) {
    var tokens: lab_io_cancel::Token[..64] = [];
    for i in expected { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
    assert(lab_io_cancel::create().id == 0);
    for i in tokens.len { lab_io_cancel::destroy(tokens[i]); }
}
fn clean_http(s: const lab_net_http_clients::Service&) {
    let stats = lab_net_http_clients::stats(s);
    assert(stats.clients == 0 && stats.inflight == 0 && stats.ready == 0 && stats.workers == 0 && stats.payload_bytes == 0);
    assert(stats.submitted == stats.completed);
}
fn clean_search(s: const lab_fs_search_clients::Service&) {
    let stats = lab_io_stream::stats(s.flow);
    assert(stats.clients == 0 && stats.inflight == 0 && stats.ready == 0 && stats.held == 0 && stats.workers == 0);
    assert(stats.payload_bytes == 0 && stats.arena_bytes == 0 && stats.submitted == stats.completed);
}
fn http_stops(base: const u8[:], root: const u8[:], round: i64) {
    var http = lab_net_http_clients::create(lab_net_http_clients::Limits { clients: 3, workers: 2 });
    var search = lab_fs_search_clients::create(lab_io_stream::Limits { clients: 3, workers: 2 });
    assert(http.code == 0 && search.flow.code == 0);
    let sid, sc = lab_io_stream::open(search.flow); assert(sc == 0);
    assert(lab_fs_search_clients::start(search, sid, str(root, "/A"), "needle") == 0);
    let held = held_page(search, sid); let image = to_bytes([held]);
    let a, ac = lab_net_http_clients::open(http); let b, bc = lab_net_http_clients::open(http); assert(ac == 0 && bc == 0);
    let key = str("http-stop-", round);
    assert(lab_net_http_clients::get(http, a, str(base, "/hold/", key)) == 0); control(base, str("/ready/", key));
    let live = str("http-live-", round);
    assert(lab_net_http_clients::get(http, b, str(base, "/value/", live)) == 0);
    let owned = http_result(http, b, round, "http-close", live);
    assert(lab_net_http_clients::close(http, a) == 0);
    let fresh, fc = lab_net_http_clients::open(http); assert(fc == 0 && fresh.slot == a.slot && fresh.generation != a.generation);
    assert(lab_net_http_clients::get(http, a, str(base, "/value/stale")) == lab_net_http_clients::STALE);
    let newer = str("reopen-", round);
    assert(lab_net_http_clients::get(http, fresh, str(base, "/value/", newer)) == 0);
    http_result(http, fresh, round, "http-reopen", newer);
    lab_net_http_clients::shutdown(http); clean_http(http); control(base, str("/release/", key));
    assert(lab_io_stream::info(search.flow, sid).held && to_bytes([held]) == image && owned.response.body == live);
    tokens_available(63); print("tokens,", round, ",http-stopped,63");
    emit_search(held, round, "after-http"); assert(lab_io_stream::ack(search.flow, held.receipt) == 0);
    consume_search(search, sid, round, "after-http", 2);
    lab_fs_search_clients::shutdown(search); clean_search(search); tokens_available(64);
    assert(to_bytes([held]) == image && owned.response.body == live); print("clean,", round, ",http-stopped");
}
fn search_stops(base: const u8[:], root: const u8[:], round: i64) {
    var http = lab_net_http_clients::create(lab_net_http_clients::Limits { clients: 3, workers: 2 });
    var search = lab_fs_search_clients::create(lab_io_stream::Limits { clients: 3, workers: 2 });
    assert(http.code == 0 && search.flow.code == 0);
    let hid, hc = lab_net_http_clients::open(http); assert(hc == 0);
    let key = str("held-", round);
    assert(lab_net_http_clients::get(http, hid, str(base, "/hold/", key)) == 0); control(base, str("/ready/", key));
    let old, oc = lab_io_stream::open(search.flow); assert(oc == 0);
    assert(lab_fs_search_clients::start(search, old, str(root, "/A"), "needle") == 0);
    let held = held_page(search, old); let image = to_bytes([held]);
    assert(lab_io_stream::close(search.flow, old) == 0);
    let fresh, fc = lab_io_stream::open(search.flow); assert(fc == 0 && fresh.slot == old.slot && fresh.generation != old.generation);
    assert(lab_io_stream::ack(search.flow, held.receipt) == lab_io_stream::STALE);
    assert(lab_fs_search_clients::start(search, old, str(root, "/B"), "needle") == lab_io_stream::STALE);
    assert(lab_fs_search_clients::start(search, fresh, str(root, "/B"), "needle") == 0);
    consume_search(search, fresh, round, "reopened-search");
    lab_fs_search_clients::shutdown(search); clean_search(search);
    assert(lab_net_http_clients::info(http, hid).busy && !lab_net_http_clients::info(http, hid).ready && to_bytes([held]) == image);
    tokens_available(63); print("tokens,", round, ",search-stopped,63");
    control(base, str("/release/", key)); let owned = http_result(http, hid, round, "after-search", key);
    lab_net_http_clients::shutdown(http); clean_http(http); tokens_available(64);
    assert(owned.response.body == key && to_bytes([held]) == image); print("clean,", round, ",search-stopped");
}
fn shared_quota(base: const u8[:], root: const u8[:], round: i64) {
    var http = lab_net_http_clients::create(lab_net_http_clients::Limits { clients: 3, workers: 2 });
    var search = lab_fs_search_clients::create(lab_io_stream::Limits { clients: 3, workers: 2 });
    assert(http.code == 0 && search.flow.code == 0);
    let hid, hc = lab_net_http_clients::open(http); let retry_h, rhc = lab_net_http_clients::open(http); assert(hc == 0 && rhc == 0);
    let sid, sc = lab_io_stream::open(search.flow); let retry_s, rsc = lab_io_stream::open(search.flow); assert(sc == 0 && rsc == 0);
    let key = str("quota-held-", round);
    assert(lab_net_http_clients::get(http, hid, str(base, "/hold/", key)) == 0); control(base, str("/ready/", key));
    assert(lab_fs_search_clients::start(search, sid, str(root, "/A"), "needle") == 0);
    let held = held_page(search, sid); let image = to_bytes([held]);
    var tokens: lab_io_cancel::Token[..64] = [];
    for i in 62 { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
    assert(lab_io_cancel::create().id == 0);
    let refused_h = lab_net_http_clients::get(http, retry_h, str(base, "/value/refused"));
    let refused_s = lab_fs_search_clients::start(search, retry_s, str(root, "/B"), "needle");
    assert(refused_h == lab_net_http_clients::LIMIT && refused_s == lab_io_stream::LIMIT);
    assert(lab_net_http_clients::info(http, retry_h).serial == 0 && !lab_net_http_clients::info(http, retry_h).busy);
    assert(lab_io_stream::info(search.flow, retry_s).serial == 0 && !lab_io_stream::info(search.flow, retry_s).busy);
    assert(lab_net_http_clients::stats(http).submitted == 1 && lab_io_stream::stats(search.flow).submitted == 1);
    lab_io_cancel::destroy(tokens[0]);
    let recovered = str("recovered-", round);
    assert(lab_net_http_clients::get(http, retry_h, str(base, "/value/", recovered)) == 0);
    // Completion may already be queued, but its token remains owned until poll.
    let still_full = lab_fs_search_clients::start(search, retry_s, str(root, "/B"), "needle"); assert(still_full == lab_io_stream::LIMIT);
    assert(lab_io_stream::info(search.flow, retry_s).serial == 0 && lab_io_stream::stats(search.flow).submitted == 1);
    print("quota,", round, ",", refused_h, ",", refused_s, ",", still_full, ",", lab_net_http_clients::info(http, retry_h).serial,
          ",", lab_io_stream::info(search.flow, retry_s).serial, ",", lab_net_http_clients::stats(http).submitted, ",", lab_io_stream::stats(search.flow).submitted);
    let owned = http_result(http, retry_h, round, "quota-recovery", recovered);
    assert(owned.serial == 1 && lab_io_stream::info(search.flow, sid).held && to_bytes([held]) == image);
    assert(lab_fs_search_clients::start(search, retry_s, str(root, "/B"), "needle") == 0);
    consume_search(search, retry_s, round, "quota-recovery");
    for i in tokens.len { lab_io_cancel::destroy(tokens[i]); }
    lab_fs_search_clients::shutdown(search); clean_search(search); tokens_available(63);
    assert(lab_net_http_clients::info(http, hid).busy && to_bytes([held]) == image);
    control(base, str("/release/", key)); http_result(http, hid, round, "quota-survivor", key);
    lab_net_http_clients::shutdown(http); clean_http(http); tokens_available(64);
    assert(owned.response.body == recovered && to_bytes([held]) == image); print("clean,", round, ",quota");
}
fn native_slots(root: const u8[:]) {
    var contexts: lab_io_event_loop::Context[..64] = [];
    for i in 64 { let context = lab_io_event_loop::create(); assert(context.code == 0); contexts.push(context); }
    assert(lab_io_event_loop::create().code == lab_io_event_loop::LIMIT);
    var reads: lab_fs_async_files::Read[..16] = []; var listings: lab_fs_async_files::Listing[..16] = [];
    for i in 16 {
        let read = lab_fs_async_files::read(contexts[0], str(root, "/A/data.txt")); assert(read.code == 0); reads.push(read);
        let listing = lab_fs_async_files::list(contexts[0], str(root, "/A")); assert(listing.code == 0); listings.push(listing);
    }
    assert(lab_fs_async_files::read(contexts[0], str(root, "/A/data.txt")).code == lab_io_event_loop::LIMIT);
    assert(lab_fs_async_files::list(contexts[0], str(root, "/A")).code == lab_io_event_loop::LIMIT);
    for i in 16 { assert(lab_fs_async_files::close(reads[i]) && lab_fs_async_files::close(listings[i])); }
    for i in contexts.len { assert(lab_io_event_loop::info(contexts[i]).resources == 0 && lab_io_event_loop::close(contexts[i])); }
    print("native,64,16,16");
}
fn main() {
    let argv = args(); assert(argv.len == 3 && lab_net_http::init() == 0);
    for round in 3 { http_stops(argv[1], argv[2], round); search_stops(argv[1], argv[2], round); shared_quota(argv[1], argv[2], round); }
    native_slots(argv[2]); lab_net_http::shutdown(); print("Mixed service contracts passed");
}
