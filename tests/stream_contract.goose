import std;
import os;
import lab.io.stream;
import lab.io.cancel;
import support.stream_producer;
fn wait(s: lab_io_stream::Service<support_stream_producer::Payload>&, id: lab_io_stream::Id) {
    let until = clock_ns() + 5000000000;
    while !lab_io_stream::info(s, id).ready { assert(clock_ns() < until); lab_io_stream::poll(s); sleep_ms(1); }
}
fn take(s: lab_io_stream::Service<support_stream_producer::Payload>&, id: lab_io_stream::Id) -> lab_io_stream::Page<support_stream_producer::Payload> {
    wait(s, id); let page, code = lab_io_stream::take(s, id); assert(code == 0); page
}
fn complete(s: lab_io_stream::Service<support_stream_producer::Payload>&, id: lab_io_stream::Id, first: lab_io_stream::Receipt, pages: i64) -> lab_io_stream::Page<support_stream_producer::Payload> {
    var receipt = first;
    for n in 1..pages {
        assert(lab_io_stream::ack(s, receipt) == 0);
        let page = take(s, id); assert(!page.done && page.receipt.sequence == (n + 1) as u64 && page.data.owner == id.slot);
        assert(page.data.text == str(id.slot, ":", page.receipt.serial, ":", page.receipt.sequence)); receipt = page.receipt;
        assert(lab_io_stream::ack(s, first) == lab_io_stream::STALE);
    }
    assert(lab_io_stream::ack(s, receipt) == 0); let final = take(s, id);
    assert(final.done && final.code == 0 && final.receipt.sequence == (pages + 1) as u64); final
}
fn free_tokens() {
    var tokens: lab_io_cancel::Token[..64] = [];
    for i in 64 { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
    assert(lab_io_cancel::create().id == 0); for i in tokens.len { lab_io_cancel::destroy(tokens[i]); }
}
fn races() {
    var s = support_stream_producer::create(lab_io_stream::Limits { clients: 3, workers: 3 });
    let a, ac = lab_io_stream::open(s); let b, bc = lab_io_stream::open(s); let c, cc = lab_io_stream::open(s); assert(ac == 0 && bc == 0 && cc == 0);
    for id in [a, b, c] { assert(support_stream_producer::start(s, id, 4) == 0); }
    let ap = take(s, a); let bp = take(s, b); let cp = take(s, c);
    assert(ap.receipt.lane != bp.receipt.lane && ap.receipt.lane != cp.receipt.lane && bp.receipt.lane != cp.receipt.lane);
    qput(lab_io_stream::packet(ap)); var altered = ap; altered.receipt.serial++; qput(lab_io_stream::packet(altered));
    assert(lab_io_stream::poll(s) == 2 && lab_io_stream::info(s, a).held);
    var invalid_receipt = ap.receipt; invalid_receipt.lane = bp.receipt.lane;
    assert(lab_io_stream::ack(s, invalid_receipt) == lab_io_stream::STALE && lab_io_stream::info(s, a).held);
    // Put B's valid ACK into A's typed lane. A must reject it; B progresses
    // through its own lane while A and C deliberately retain their first page.
    var wrong = bp.receipt; wrong.lane = ap.receipt.lane; lab_io_stream::send_ack<support_stream_producer::Payload>(wrong);
    let bf = complete(s, b, bp.receipt, 4); assert(bf.data.rejected == 0);
    assert(lab_io_stream::info(s, a).held && lab_io_stream::info(s, c).held);
    assert(lab_io_stream::stats(s).inflight == 2 && lab_io_stream::stats(s).held == 2);
    let missing, mc = lab_io_stream::take(s, a); assert(mc == lab_io_stream::NOT_READY);
    assert(lab_io_stream::ack(s, bp.receipt) == lab_io_stream::NOT_READY);
    let af = complete(s, a, ap.receipt, 4); assert(af.data.rejected == 1);
    assert(ap.data.text == "0:1:1"); // Owned export survives subsequent pages.
    assert(lab_io_stream::close(s, c) == 0);
    let fresh, fc = lab_io_stream::open(s); assert(fc == 0 && fresh.slot == c.slot && fresh.generation != c.generation);
    assert(lab_io_stream::ack(s, cp.receipt) == lab_io_stream::STALE);
    assert(support_stream_producer::start(s, fresh, 2) == 0);
    qput(lab_io_stream::packet(cp)); lab_io_stream::poll(s);
    let fp = take(s, fresh); assert(fp.receipt.client.generation == fresh.generation && fp.receipt.serial == 1);
    complete(s, fresh, fp.receipt, 2);
    // A cancelled, unread page cannot block terminal adoption. No ACK required.
    assert(support_stream_producer::start(s, a, 4) == 0); wait(s, a);
    assert(lab_io_stream::cancel(s, a) == 0); let cancelled = take(s, a);
    assert(cancelled.done && cancelled.code == lab_io_stream::CANCELLED && cancelled.data.text.len == 0);
    // ACK followed immediately by Cancel may be observed by the worker in
    // either order. Its terminal must release the Flight in both cases.
    for i in 100 {
        assert(support_stream_producer::start(s, b, 4) == 0); let first = take(s, b);
        assert(lab_io_stream::ack(s, first.receipt) == 0 && lab_io_stream::cancel(s, b) == 0);
        let final = take(s, b); assert(final.done && final.code == lab_io_stream::CANCELLED);
    }
    // Real successful terminal publication already queued before cancellation.
    assert(support_stream_producer::start(s, b, 0) == 0);
    let until = clock_ns() + 5000000000; var queued = lab_io_stream::Packet<support_stream_producer::Payload> { receipt: lab_io_stream::Receipt {} };
    loop { let page, available = qpoll<lab_io_stream::Packet<support_stream_producer::Payload>>(); if available { queued = copy(page); break; } assert(clock_ns() < until); sleep_ms(1); }
    assert(queued.done && queued.code == 0); qput(queued); assert(lab_io_stream::cancel(s, b) == 0);
    let converted = take(s, b); assert(converted.done && converted.code == lab_io_stream::CANCELLED);
    // A deadline releases the producer even when the consumer never takes/ACKs.
    assert(support_stream_producer::start(s, a, 4, 50) == 0); wait(s, a);
    let timeout_at = clock_ns() + 5000000000;
    while lab_io_stream::info(s, a).busy { lab_io_stream::poll(s); assert(clock_ns() < timeout_at); sleep_ms(1); }
    let timed = take(s, a); assert(timed.done && timed.code == lab_io_stream::TIMEOUT && lab_io_stream::stats(s).replaced > 0);
    support_stream_producer::shutdown(s); support_stream_producer::shutdown(s);
    let stats = lab_io_stream::stats(s); assert(stats.inflight == 0 && stats.clients == 0 && stats.held == 0 && stats.ready == 0 && stats.workers == 0);
    assert(stats.submitted == stats.completed && ap.data.text == "0:1:1"); free_tokens(); print("stream races and typed ACK isolation passed");
}
fn many(count: i64) {
    var s = support_stream_producer::create(lab_io_stream::Limits { clients: count, workers: 8 });
    var ids: lab_io_stream::Id[..64] = []; var expected: u64[64] = [1; 64];
    for i in count { let id, code = lab_io_stream::open(s); assert(code == 0); ids.push(id); assert(support_stream_producer::start(s, id, 3) == 0); }
    var done: bool[64] = [false; 64]; var remaining = count; let until = clock_ns() + 10000000000;
    while remaining > 0 {
        lab_io_stream::poll(s, 5); assert(clock_ns() < until);
        for i in count {
            if done[i] || !lab_io_stream::info(s, ids[i]).ready { continue; }
            let page, code = lab_io_stream::take(s, ids[i]); assert(code == 0 && page.receipt.sequence == expected[i]);
            assert(page.receipt.client.slot == i && page.receipt.client.generation == 1 && page.receipt.serial == 1 && page.code == 0);
            if page.done { assert(expected[i] == 4); done[i] = true; remaining--; }
            else { assert(page.data.text == str(i, ":1:", expected[i])); assert(lab_io_stream::ack(s, page.receipt) == 0); expected[i]++; }
            print("page,", count, ",", i, ",", page.receipt.sequence, ",", page.done, ",", page.data.text);
        }
    }
    assert(lab_io_stream::stats(s).acknowledgements == count * 3);
    support_stream_producer::shutdown(s); free_tokens(); print("many,", count, ",passed");
}
fn bounds() {
    var invalid = support_stream_producer::create(lab_io_stream::Limits { workers: 0 }); assert(invalid.code == lab_io_stream::INVALID);
    support_stream_producer::shutdown(invalid);
    var one = support_stream_producer::create(lab_io_stream::Limits { clients: 2, inflight: 1, workers: 1 });
    let a, ac = lab_io_stream::open(one); let b, bc = lab_io_stream::open(one); let no, nc = lab_io_stream::open(one);
    assert(ac == 0 && bc == 0 && nc == lab_io_stream::LIMIT);
    assert(support_stream_producer::start(one, a, 1) == 0 && support_stream_producer::start(one, b, 1) == lab_io_stream::LIMIT);
    assert(lab_io_stream::info(one, b).serial == 0 && !lab_io_stream::info(one, b).busy);
    assert(support_stream_producer::start(one, a) == lab_io_stream::BUSY);
    wait(one, a); assert(lab_io_stream::discard(one, a) == 0); wait(one, a);
    assert(!lab_io_stream::info(one, a).busy && lab_io_stream::stats(one).acknowledgements == 1);
    assert(support_stream_producer::start(one, a) == lab_io_stream::BUSY);
    assert(lab_io_stream::discard(one, a) == 0 && lab_io_stream::discard(one, a) == lab_io_stream::NOT_READY);
    assert(lab_io_stream::stats(one).acknowledgements == 1);
    assert(support_stream_producer::start(one, b, 0) == 0); let terminal = take(one, b); assert(terminal.done);
    support_stream_producer::shutdown(one); free_tokens();
    var s = support_stream_producer::create(lab_io_stream::Limits { clients: 64, workers: 8 }); var ids: lab_io_stream::Id[..64] = [];
    for i in 64 { let id, code = lab_io_stream::open(s); assert(code == 0); ids.push(id); assert(support_stream_producer::start(s, id, 64) == 0); }
    for i in 8 { wait(s, ids[i]); }
    assert(lab_io_stream::stats(s).ready == 8 && lab_io_stream::stats(s).acknowledgements == 0);
    // Polling cannot release credit. With all eight lanes stalled, only eight
    // pages can be published; the remaining 56 jobs remain bounded submissions.
    assert(lab_io_stream::poll(s) == 0); assert(lab_io_stream::stats(s).received == 8);
    for id in ids { assert(lab_io_stream::close(s, id) == 0); }
    let reuse, rc = lab_io_stream::open(s); assert(rc == 0);
    assert(support_stream_producer::start(s, reuse) == lab_io_stream::LIMIT && lab_io_stream::info(s, reuse).serial == 0);
    let before = clock_ns(); support_stream_producer::shutdown(s); assert(clock_ns() - before < 2000000000);
    assert(lab_io_stream::stats(s).completed == 64 && lab_io_stream::stats(s).inflight == 0); free_tokens(); print("stream stalled-lane bounds and shutdown passed");
}
struct EmptyPayload {}
struct HugePayload { bytes: u8[65534] }
fn compact_storage() {
    var empty = lab_io_stream::create<EmptyPayload>(); assert(empty.code == 0);
    let eid, ec = lab_io_stream::open(empty); let request, rc = lab_io_stream::begin(empty, eid); assert(ec == 0 && rc == 0);
    lab_io_stream::publish<EmptyPayload>(request, 0, 1, EmptyPayload {}, true); assert(lab_io_stream::poll(empty) == 1);
    let ep, pc = lab_io_stream::take(empty, eid); assert(pc == 0 && ep.done);
    lab_io_stream::prepare_shutdown(empty); lab_io_stream::finish_shutdown(empty);
    assert(lab_io_stream::create<HugePayload>().code == lab_io_stream::INVALID);
    var s = lab_io_stream::create<support_stream_producer::Payload>(lab_io_stream::Limits { clients: 64, workers: 1 });
    var ids: lab_io_stream::Id[..64] = []; var requests: lab_io_stream::Request[..64] = []; var total: i64 = 0;
    assert(lab_io_stream::stats(s).payload_bytes == 0);
    for i in 64 {
        let id, ic = lab_io_stream::open(s); let request, rc = lab_io_stream::begin(s, id); assert(ic == 0 && rc == 0);
        ids.push(id); requests.push(request); var data: u8[>..] = []; data.resize(i * 7, i as u8); total += data.len;
        lab_io_stream::publish_bytes<support_stream_producer::Payload>(request, 0, 1, data);
    }
    assert(lab_io_stream::poll(s) == 64 && lab_io_stream::stats(s).payload_bytes == total);
    assert(lab_io_stream::stats(s).peak_payload_bytes == total);
    let owned, oc = lab_io_stream::take_packet(s, ids[63]); assert(oc == 0 && owned.data.len == 441);
    assert(lab_io_stream::ack(s, owned.receipt) == 0); total -= 441;
    for n in 63 {
        let i = (n * 17) % 63; let page, code = lab_io_stream::take_packet(s, ids[i]); assert(code == 0 && page.data.len == i * 7);
        for byte in page.data { assert(byte == i as u8); } total -= i * 7;
        assert(lab_io_stream::stats(s).payload_bytes == total && lab_io_stream::info(s, ids[i]).held);
        assert(lab_io_stream::ack(s, page.receipt) == 0);
        lab_io_stream::publish_bytes<support_stream_producer::Payload>(requests[i], 0, 2, "", true);
        lab_io_stream::poll(s); // Empty terminal among other live payload ranges.
    }
    lab_io_stream::publish_bytes<support_stream_producer::Payload>(requests[63], 0, 2, "", true); lab_io_stream::poll(s);
    assert(total == 0 && lab_io_stream::stats(s).payload_bytes == 0 && lab_io_stream::stats(s).inflight == 0);
    for id in ids { let page, code = lab_io_stream::take_packet(s, id); assert(code == 0 && page.done && page.data.len == 0); }
    lab_io_stream::prepare_shutdown(s); lab_io_stream::finish_shutdown(s);
    assert(owned.data.len == 441); for byte in owned.data { assert(byte == 63); }
    let stats = lab_io_stream::stats(s);
    assert(stats.shifted_bytes == 0 && stats.arena_bytes == 0);
    print("compact-storage,", stats.peak_payload_bytes, ",", stats.queue_bytes, ",", stats.exported_bytes, ",", stats.shifted_bytes);
    free_tokens(); print("compact stream storage and owned exports passed");
}
fn fragmented_storage() {
    var s = lab_io_stream::create<support_stream_producer::Payload>(lab_io_stream::Limits { clients: 3, workers: 1 });
    var ids: lab_io_stream::Id[..3] = []; var requests: lab_io_stream::Request[..3] = [];
    for i in 3 {
        let id, ic = lab_io_stream::open(s); let request, rc = lab_io_stream::begin(s, id); assert(ic == 0 && rc == 0);
        ids.push(id); requests.push(request); var bytes: u8[>..] = []; bytes.resize(if i == 0 { 32768 } else { 65536 }, (i + 1) as u8);
        lab_io_stream::publish_bytes<support_stream_producer::Payload>(request, 0, 1, bytes);
    }
    assert(lab_io_stream::poll(s) == 3); let kept, kc = lab_io_stream::take_packet(s, ids[0]); assert(kc == 0 && kept.data.len == 32768);
    let hole = lab_io_stream::stats(s); assert(hole.payload_bytes == 131072 && hole.arena_bytes == 163840 && hole.shifted_bytes == 0);
    assert(lab_io_stream::ack(s, kept.receipt) == 0); var large: u8[>..] = []; large.resize(65536, 9);
    // Neither the old hole nor the remaining tail fits the new page; compact
    // once to preserve two unread survivors and fit the complete bounded arena.
    lab_io_stream::publish_bytes<support_stream_producer::Payload>(requests[0], 0, 2, large); assert(lab_io_stream::poll(s) == 1);
    let full = lab_io_stream::stats(s); assert(full.payload_bytes == 196608 && full.arena_bytes == 196608 && full.compactions == 1 && full.shifted_bytes == 131072);
    for i in 3 {
        let page, code = lab_io_stream::take_packet(s, ids[i]); assert(code == 0 && page.data.len == 65536);
        let pattern: u8 = if i == 0 { 9 } else { (i + 1) as u8 }; for byte in page.data { assert(byte == pattern); }
        assert(lab_io_stream::ack(s, page.receipt) == 0);
        lab_io_stream::publish_bytes<support_stream_producer::Payload>(requests[i], 0, if i == 0 { 3 } else { 2 }, "", true);
    }
    lab_io_stream::poll(s); for id in ids { let page, code = lab_io_stream::take_packet(s, id); assert(code == 0 && page.done); }
    lab_io_stream::prepare_shutdown(s); lab_io_stream::finish_shutdown(s);
    for byte in kept.data { assert(byte == 1); }
    let end = lab_io_stream::stats(s); assert(end.arena_bytes == 0 && end.inflight == 0);
    print("fragmented-storage,", end.peak_payload_bytes, ",", end.peak_arena_bytes, ",", end.shifted_bytes, ",", end.compactions);
    free_tokens(); print("fragmented stream storage and pressure compaction passed");
}
fn main() { races(); for count in [3, 16, 64] { many(count); } bounds(); compact_storage(); fragmented_storage(); print("Stream contracts passed"); }
