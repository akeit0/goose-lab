import std;
import os;
import lab.io.stream;
import lab.io.cancel;
import lab.io.event_loop;
import lab.fs.search;
import lab.fs.async_files;
import lab.fs.search_clients;
import support.stream_producer;
fn wait(s: lab_fs_search_clients::Service&, id: lab_io_stream::Id) {
    let until = clock_ns() + 10000000000;
    while !lab_io_stream::info(s.flow, id).ready { assert(clock_ns() < until); lab_io_stream::poll(s.flow, 5); sleep_ms(1); }
}
fn take(s: lab_fs_search_clients::Service&, id: lab_io_stream::Id) -> lab_io_stream::Page<lab_fs_search::Batch> {
    wait(s, id); let page, code = lab_fs_search_clients::take(s, id); assert(code == 0); page
}
fn emit(page: const lab_io_stream::Page<lab_fs_search::Batch>&, label: const u8[:]) {
    for hit in page.data.hits { print("hit,", label, ",", page.receipt.client.slot, ",", page.receipt.client.generation, ",", page.receipt.serial,
        ",", hit.path, ",", hit.line, ",", hit.column, ",", hit.start, ",", hit.end); }
    for issue in page.data.issues { print("issue,", label, ",", issue.path, ",", issue.reason); }
    if page.done { print("done,", label, ",", page.receipt.client.slot, ",", page.receipt.client.generation, ",", page.receipt.serial,
        ",", page.code, ",", page.data.result, ",", page.data.progress.matches); }
}
fn hit_page(s: lab_fs_search_clients::Service&, id: lab_io_stream::Id) -> lab_io_stream::Page<lab_fs_search::Batch> {
    loop { let page = take(s, id); assert(!page.done); if page.data.hits.len > 0 { return page; } assert(lab_io_stream::ack(s.flow, page.receipt) == 0); }
}
fn consume(s: lab_fs_search_clients::Service&, id: lab_io_stream::Id, label: const u8[:]) {
    var sequence: u64 = 1;
    loop {
        let page = take(s, id); assert(page.receipt.sequence == sequence && page.receipt.client.generation == id.generation);
        emit(page, label); if page.done { assert(page.data.done && page.data.progress.active == 0); break; }
        assert(lab_io_stream::ack(s.flow, page.receipt) == 0); sequence++;
    }
}
fn cleanup(root: const u8[:]) {
    var tokens: lab_io_cancel::Token[..64] = [];
    for i in 64 { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
    assert(lab_io_cancel::create().id == 0); for i in tokens.len { lab_io_cancel::destroy(tokens[i]); }
    // Registry quotas: 64 loops, 16 reads, 16 listings. Reacquire each quota
    // while all earlier handles remain owned, to detect retained search handles.
    var contexts: lab_io_event_loop::Context[..64] = [];
    for i in 64 { let context = lab_io_event_loop::create(); assert(context.code == 0); contexts.push(context); }
    let no = lab_io_event_loop::create(); assert(no.code == lab_io_event_loop::LIMIT);
    var reads: lab_fs_async_files::Read[..16] = []; var listings: lab_fs_async_files::Listing[..16] = [];
    for i in 16 {
        let read = lab_fs_async_files::read(contexts[0], str(root, "/A/data-A.txt")); assert(read.code == 0); reads.push(read);
        let listing = lab_fs_async_files::list(contexts[0], str(root, "/A")); assert(listing.code == 0); listings.push(listing);
    }
    assert(lab_fs_async_files::read(contexts[0], str(root, "/A/data-A.txt")).code == lab_io_event_loop::LIMIT);
    assert(lab_fs_async_files::list(contexts[0], str(root, "/A")).code == lab_io_event_loop::LIMIT);
    for i in 16 { assert(lab_fs_async_files::close(reads[i]) && lab_fs_async_files::close(listings[i])); }
    for i in contexts.len { assert(lab_io_event_loop::info(contexts[i]).resources == 0 && lab_io_event_loop::close(contexts[i])); }
}
fn lifetimes(root: const u8[:]) {
    // Different fixed payload types get different typed ACK queues even for
    // the same lane tag. Hold a synthetic page throughout the real searches.
    var probe = support_stream_producer::create(lab_io_stream::Limits { clients: 1, workers: 1 });
    let probe_id, pc = lab_io_stream::open(probe); assert(pc == 0 && support_stream_producer::start(probe, probe_id, 1) == 0);
    let until = clock_ns() + 5000000000;
    while !lab_io_stream::info(probe, probe_id).ready { lab_io_stream::poll(probe); assert(clock_ns() < until); sleep_ms(1); }
    let held, hc = lab_io_stream::take(probe, probe_id); assert(hc == 0);
    var s = lab_fs_search_clients::create(lab_io_stream::Limits { clients: 3, workers: 3 });
    let a, ac = lab_io_stream::open(s.flow); let b, bc = lab_io_stream::open(s.flow); let c, cc = lab_io_stream::open(s.flow); assert(ac == 0 && bc == 0 && cc == 0);
    for id in [a, b, c] {
        assert(lab_fs_search_clients::start(s, id, str(root, "/", if id.slot == 0 { "A" } else if id.slot == 1 { "B" } else { "C" }), "needle") == 0);
    }
    let ap = hit_page(s, a); // Retain a real search's first hit page without ACK.
    consume(s, b, "B"); consume(s, c, "C");
    assert(lab_io_stream::info(s.flow, a).held && lab_io_stream::stats(s.flow).inflight == 1);
    assert(lab_io_stream::info(probe, probe_id).held && lab_io_stream::poll(probe) == 0);
    assert(lab_io_stream::close(s.flow, a) == 0);
    let fresh, fc = lab_io_stream::open(s.flow); assert(fc == 0 && fresh.slot == a.slot && fresh.generation == 2);
    assert(lab_io_stream::ack(s.flow, ap.receipt) == lab_io_stream::STALE);
    assert(lab_fs_search_clients::start(s, fresh, str(root, "/A"), "日本語") == 0);
    qput(ap); lab_io_stream::poll(s.flow); consume(s, fresh, "A2");
    assert(lab_fs_search_clients::start(s, b, str(root, "/B"), "absent") == 0); consume(s, b, "B-missing");
    // Timeout must finish and close native resources while a page is held.
    assert(lab_fs_search_clients::start(s, c, str(root, "/C"), "needle", lab_fs_search::Options { timeout_ms: 500 }) == 0);
    let pending = hit_page(s, c); let timed_at = clock_ns() + 10000000000;
    while lab_io_stream::info(s.flow, c).busy { lab_io_stream::poll(s.flow); assert(clock_ns() < timed_at); sleep_ms(1); }
    let timed = take(s, c); assert(timed.done && timed.code == lab_io_stream::TIMEOUT && timed.data.result == lab_fs_search::TIMEOUT && timed.data.progress.active == 0);
    assert(lab_io_stream::ack(s.flow, pending.receipt) == lab_io_stream::NOT_READY); emit(timed, "C-timeout");
    assert(lab_fs_search_clients::start(s, c, str(root, "/C"), "needle", lab_fs_search::Options { parallel: 0 }) == 0); consume(s, c, "C-invalid");
    assert(lab_fs_search_clients::start(s, c, str(root, "/missing"), "needle") == 0); consume(s, c, "C-io");
    assert(lab_fs_search_clients::start(s, fresh, str(root, "/A"), "needle", lab_fs_search::Options { max_matches: 2 }) == 0); consume(s, fresh, "A-limit");
    // Native ACK wait cancellation and service shutdown both operate without ACK.
    assert(lab_fs_search_clients::start(s, b, str(root, "/B"), "needle") == 0); let bp = hit_page(s, b);
    assert(lab_io_stream::cancel(s.flow, b) == 0); let cancelled = take(s, b);
    assert(cancelled.done && cancelled.code == lab_io_stream::CANCELLED && cancelled.data.result == lab_fs_search::CANCELLED && cancelled.data.hits.len == 0);
    emit(cancelled, "B-cancel");
    assert(lab_fs_search_clients::start(s, fresh, str(root, "/A"), "needle") == 0); hit_page(s, fresh);
    let before = clock_ns(); lab_fs_search_clients::shutdown(s); assert(clock_ns() - before < 2000000000);
    assert(ap.data.hits.len > 0 && ap.data.hits[0].path == "data-A.txt");
    assert(lab_io_stream::ack(probe, held.receipt) == 0);
    while !lab_io_stream::info(probe, probe_id).ready { lab_io_stream::poll(probe); assert(clock_ns() < timed_at); sleep_ms(1); }
    let end, ec = lab_io_stream::take(probe, probe_id); assert(ec == 0 && end.done && end.code == 0 && end.data.rejected == 0);
    support_stream_producer::shutdown(probe); cleanup(root); print("real search lifetimes and native cleanup passed");
}
fn many(root: const u8[:], count: i64) {
    var s = lab_fs_search_clients::create(lab_io_stream::Limits { clients: count, workers: 8 });
    var ids: lab_io_stream::Id[..64] = []; var sequence: u64[64] = [1; 64]; var matches: i64[64] = [0; 64]; var done: bool[64] = [false; 64]; var remaining = count;
    for i in count {
        let id, code = lab_io_stream::open(s.flow); assert(code == 0); ids.push(id);
        assert(lab_fs_search_clients::start(s, id, str(root, "/M", i), "needle") == 0);
    }
    let until = clock_ns() + 20000000000;
    while remaining > 0 {
        lab_io_stream::poll(s.flow, 7); assert(clock_ns() < until);
        for i in count {
            if done[i] || !lab_io_stream::info(s.flow, ids[i]).ready { continue; }
            let page, code = lab_fs_search_clients::take(s, ids[i]); assert(code == 0 && page.code == 0 && page.receipt.sequence == sequence[i]);
            assert(page.receipt.client.slot == i && page.receipt.client.generation == 1 && page.receipt.serial == 1);
            for hit in page.data.hits { assert(hit.path == str("data-M", i, ".txt")); } matches[i] += page.data.hits.len;
            emit(page, str("many-", count, "-", i));
            if page.done { assert(matches[i] == 96 && page.data.progress.matches == 96 && page.data.progress.active == 0); done[i] = true; remaining--; }
            else { assert(lab_io_stream::ack(s.flow, page.receipt) == 0); sequence[i]++; }
        }
    }
    lab_fs_search_clients::shutdown(s); cleanup(root); print("search-many,", count, ",passed");
}
fn main() { let argv = args(); assert(argv.len == 2); lifetimes(argv[1]); for count in [3, 16, 64] { many(argv[1], count); } print("Search stream contracts passed"); }
