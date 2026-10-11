import std;
import os;
import lab.net.http;
import lab.net.http_clients;
import lab.io.cancel;

fn get(base: const u8[:], path: const u8[:]) -> u8[>..] { str(base, path) }
fn control(base: const u8[:], path: const u8[:]) {
    let result = lab_net_http::get(str(base, path), lab_net_http::Options { timeout_ms: 5000 });
    assert(result.code == 0 && result.status == 200);
}
fn wait(s: lab_net_http_clients::Service&, id: lab_net_http_clients::Id) {
    let until = clock_ns() + 10000000000;
    while lab_net_http_clients::info(s, id).busy {
        assert(clock_ns() < until); lab_net_http_clients::poll(s, 3); sleep_ms(1);
    }
    assert(lab_net_http_clients::info(s, id).ready);
}
fn drain(s: lab_net_http_clients::Service&) {
    let until = clock_ns() + 10000000000;
    while lab_net_http_clients::stats(s).inflight != 0 {
        assert(clock_ns() < until); lab_net_http_clients::poll(s, 7); sleep_ms(1);
    }
}
fn result(s: lab_net_http_clients::Service&, id: lab_net_http_clients::Id, bytes: const u8[:], code: i32 = 0) -> lab_net_http_clients::Result {
    wait(s, id); let value, taken = lab_net_http_clients::take(s, id);
    assert(taken == 0 && value.client.slot == id.slot && value.client.generation == id.generation);
    if value.response.code != code || value.response.body != bytes {
        print("unexpected result: ", value.response.code, " status ", value.response.status, " body ", value.response.body, " error ", value.response.error, " expected ", code, " / ", bytes);
    }
    assert(value.response.code == code && value.response.body == bytes);
    assert(!lab_net_http_clients::info(s, id).ready); copy(value)
}
fn tokens_released() {
    // The native registry has 64 slots. Acquiring all of them proves no client
    // owner or completed native lease remains, without adding a test-only ABI.
    var tokens: lab_io_cancel::Token[..64] = [];
    for i in 64 { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
    let overflow = lab_io_cancel::create(); assert(overflow.id == 0);
    for i in tokens.len { lab_io_cancel::destroy(tokens[i]); }
}
fn lifetimes(base: const u8[:]) {
    var s = lab_net_http_clients::create(lab_net_http_clients::Limits { clients: 3, workers: 3 }); assert(s.code == 0);
    let a, ac = lab_net_http_clients::open(s); let b, bc = lab_net_http_clients::open(s); let c, cc = lab_net_http_clients::open(s);
    assert(ac == 0 && bc == 0 && cc == 0);
    assert(lab_net_http_clients::get(s, a, get(base, "/hold/A")) == 0);
    assert(lab_net_http_clients::get(s, b, get(base, "/hold/B")) == 0);
    assert(lab_net_http_clients::get(s, c, get(base, "/value/C")) == 0);
    control(base, "/ready/A"); control(base, "/ready/B");
    let owned = result(s, c, "C"); assert(owned.serial == 1);
    assert(lab_net_http_clients::info(s, a).busy && lab_net_http_clients::info(s, b).busy);
    assert(lab_net_http_clients::cancel(s, a) == 0 && lab_net_http_clients::cancel(s, a) == 0);
    assert(lab_net_http_clients::close(s, b) == 0);
    let reopened, rc = lab_net_http_clients::open(s); assert(rc == 0 && reopened.slot == b.slot && reopened.generation != b.generation);
    assert(lab_net_http_clients::get(s, b, get(base, "/value/stale")) == lab_net_http_clients::STALE);
    assert(lab_net_http_clients::cancel(s, b) == lab_net_http_clients::STALE);
    assert(lab_net_http_clients::get(s, reopened, get(base, "/value/new-B")) == 0);
    result(s, a, "", lab_net_http::CANCELLED); result(s, reopened, "new-B");
    control(base, "/release/A"); control(base, "/release/B"); drain(s);
    assert(lab_net_http_clients::stats(s).discarded == 1 && owned.response.body == "C");

    // A real success is held outside the Service before Cancel. Poll must apply
    // cancellation intent even though the response has already arrived.
    assert(lab_net_http_clients::get(s, c, get(base, "/value/queued")) == 0);
    let queued = qget<lab_net_http_clients::Completed>(); assert(queued.client.slot == c.slot && queued.response.body == "queued");
    qput(queued); assert(lab_net_http_clients::cancel(s, c) == 0);
    result(s, c, "", lab_net_http::CANCELLED);
    assert(lab_net_http_clients::get(s, c, get(base, "/hold/same-generation")) == 0);
    control(base, "/ready/same-generation"); qput(queued); assert(lab_net_http_clients::poll(s, 1) == 1);
    assert(lab_net_http_clients::info(s, c).busy && lab_net_http_clients::info(s, c).serial == 3);
    control(base, "/release/same-generation"); result(s, c, "same-generation");
    assert(lab_net_http_clients::close(s, c) == 0);
    let fresh, fc = lab_net_http_clients::open(s); assert(fc == 0 && fresh.slot == c.slot);
    assert(lab_net_http_clients::get(s, fresh, get(base, "/hold/fresh")) == 0); control(base, "/ready/fresh");
    qput(queued); assert(lab_net_http_clients::poll(s, 1) == 1);
    assert(lab_net_http_clients::info(s, fresh).busy && !lab_net_http_clients::info(s, fresh).ready);
    control(base, "/release/fresh"); result(s, fresh, "fresh");

    // Simultaneous success and HTTP failure retain independent status/payload.
    assert(lab_net_http_clients::get(s, a, get(base, "/failure")) == 0);
    assert(lab_net_http_clients::get(s, reopened, get(base, "/value/survivor")) == 0);
    let failed = result(s, a, "failure"); assert(failed.response.status == 503);
    result(s, reopened, "survivor");
    assert(lab_net_http_clients::get(s, a, get(base, "/hold/timeout"), lab_net_http::Options { timeout_ms: 300 }) == 0);
    control(base, "/ready/timeout");
    assert(lab_net_http_clients::get(s, reopened, get(base, "/value/while-timeout")) == 0); result(s, reopened, "while-timeout");
    wait(s, a); let timed, tc = lab_net_http_clients::take(s, a); assert(tc == 0 && timed.response.code == lab_net_http::TIMEOUT);
    control(base, "/release/timeout");

    // The queue owns the request bytes; modifying the caller's original after
    // start cannot change a binary, multi-chunk request or its returned export.
    var payload: u8[>..] = [0; 12000]; for i in payload.len { payload[i] = (i % 251) as u8; }
    let original = copy(payload); let echo_url = get(base, "/echo");
    assert(lab_net_http_clients::start(s, reopened, lab_net_http::Request { url: echo_url, method: "POST", body: payload }) == 0);
    for i in payload.len { payload[i] = 255; }
    let binary = result(s, reopened, original); assert(binary.response.headers.len > 0);
    assert(lab_net_http_clients::close(s, a) == 0);
    assert(lab_net_http_clients::get(s, reopened, get(base, "/value/still-alive")) == 0); result(s, reopened, "still-alive");

    assert(lab_net_http_clients::get(s, reopened, get(base, "/hold/shutdown")) == 0); control(base, "/ready/shutdown");
    let before = clock_ns(); lab_net_http_clients::shutdown(s);
    assert(clock_ns() - before < 2000000000); control(base, "/release/shutdown");
    let stats = lab_net_http_clients::stats(s);
    assert(stats.clients == 0 && stats.inflight == 0 && stats.ready == 0 && stats.workers == 0 && stats.payload_bytes == 0);
    assert(stats.submitted == stats.completed); lab_net_http_clients::shutdown(s);
    assert(!lab_net_http_clients::valid(s, reopened) && owned.response.body == "C" && binary.response.body == original);
    let no, nc = lab_net_http_clients::open(s); assert(nc == lab_net_http_clients::CLOSED);
    tokens_released(); print("lifetime, routing, queued cancellation and shutdown passed");
}
fn bounds(base: const u8[:]) {
    var invalid = lab_net_http_clients::create(lab_net_http_clients::Limits { workers: 0 }); assert(invalid.code == lab_net_http_clients::INVALID);
    lab_net_http_clients::shutdown(invalid);
    var s = lab_net_http_clients::create(lab_net_http_clients::Limits { clients: 3, workers: 1, inflight: 2, chunks: 1 });
    let a, ac = lab_net_http_clients::open(s); let b, bc = lab_net_http_clients::open(s); let c, cc = lab_net_http_clients::open(s);
    let no, nc = lab_net_http_clients::open(s); assert(nc == lab_net_http_clients::LIMIT);
    assert(lab_net_http_clients::get(s, a, get(base, "/hold/budget")) == 0); control(base, "/ready/budget");
    assert(lab_net_http_clients::get(s, b, get(base, "/value/B")) == 0);
    assert(lab_net_http_clients::get(s, c, get(base, "/value/C")) == lab_net_http_clients::LIMIT);
    assert(lab_net_http_clients::info(s, c).serial == 0 && !lab_net_http_clients::info(s, c).busy);
    assert(lab_net_http_clients::get(s, a, get(base, "/value/busy")) == lab_net_http_clients::BUSY);
    assert(lab_net_http_clients::cancel(s, b) == 0); control(base, "/release/budget"); drain(s);
    let ar, arc = lab_net_http_clients::take(s, a); assert(arc == 0 && ar.response.body == "budget");
    result(s, b, "", lab_net_http::CANCELLED);
    // One chunk fits either mailbox, but not both. A failed adoption cannot
    // overwrite the first client's response or leak partial stored payload.
    assert(lab_net_http_clients::get(s, a, get(base, "/value/first")) == 0); wait(s, a);
    assert(lab_net_http_clients::get(s, b, get(base, "/value/second")) == 0); wait(s, b);
    assert(lab_net_http_clients::stats(s).storage_refused == 1);
    result(s, b, "", lab_net_http::LIMIT); let first = result(s, a, "first");
    assert(lab_net_http_clients::get(s, b, get(base, "/large")) == 0); result(s, b, "", lab_net_http::LIMIT);
    assert(lab_net_http_clients::get(s, c, get(base, "/value/recovered")) == 0); wait(s, c);
    assert(lab_net_http_clients::get(s, c, get(base, "/value/blocked")) == lab_net_http_clients::BUSY);
    assert(lab_net_http_clients::discard(s, c) == 0 && lab_net_http_clients::discard(s, c) == lab_net_http_clients::NOT_READY);
    assert(lab_net_http_clients::get(s, c, get(base, "/value/reuse")) == 0); result(s, c, "reuse");
    assert(first.response.body == "first");
    var token = lab_io_cancel::create();
    assert(lab_net_http_clients::get(s, c, get(base, "/value/invalid"), lab_net_http::Options { cancel: token }) == lab_net_http_clients::INVALID);
    lab_io_cancel::destroy(token);
    assert(lab_net_http_clients::start(s, c, lab_net_http::Request { url: "" }) == lab_net_http_clients::INVALID);
    assert(lab_net_http_clients::info(s, c).serial == 2);
    assert(lab_net_http_clients::get(s, c, get(base, "/invalid"), lab_net_http::Options { timeout_ms: 0 }) == lab_net_http_clients::INVALID);
    var tokens: lab_io_cancel::Token[..64] = [];
    for i in 64 { let next = lab_io_cancel::create(); assert(next.id != 0); tokens.push(next); }
    assert(lab_net_http_clients::get(s, c, get(base, "/value/full-token-registry")) == lab_net_http_clients::LIMIT);
    assert(lab_net_http_clients::info(s, c).serial == 2 && !lab_net_http_clients::info(s, c).busy);
    for i in tokens.len { lab_io_cancel::destroy(tokens[i]); }
    lab_net_http_clients::shutdown(s); tokens_released();
    var small = lab_net_http_clients::create(lab_net_http_clients::Limits { body_bytes: 4 });
    let limited, lc = lab_net_http_clients::open(small); assert(lc == 0);
    assert(lab_net_http_clients::get(small, limited, get(base, "/value/123456")) == 0);
    let truncated = result(small, limited, "", lab_net_http::LIMIT); assert(truncated.response.headers.len > 0);
    lab_net_http_clients::shutdown(small); tokens_released();

    // Shutdown with one real blocked transfer and 63 queued jobs, all belonging
    // to already closed generations. Close is immediate, quota release is not.
    var full = lab_net_http_clients::create(lab_net_http_clients::Limits { workers: 1 });
    var clients: lab_net_http_clients::Id[..64] = [];
    for i in 64 { let id, code = lab_net_http_clients::open(full); assert(code == 0); clients.push(id); }
    assert(lab_net_http_clients::get(full, clients[0], get(base, "/hold/full-shutdown")) == 0); control(base, "/ready/full-shutdown");
    for i in 1..64 { assert(lab_net_http_clients::get(full, clients[i], get(base, "/value/queued-shutdown")) == 0); }
    for id in clients { assert(lab_net_http_clients::close(full, id) == 0); }
    let reuse, ruc = lab_net_http_clients::open(full); assert(ruc == 0);
    assert(lab_net_http_clients::get(full, reuse, get(base, "/value/retired-still-full")) == lab_net_http_clients::LIMIT);
    let shutting_at = clock_ns(); lab_net_http_clients::shutdown(full); assert(clock_ns() - shutting_at < 2000000000);
    control(base, "/release/full-shutdown");
    let finished = lab_net_http_clients::stats(full);
    assert(finished.inflight == 0 && finished.completed == 64 && finished.discarded == 64 && finished.payload_bytes == 0);
    tokens_released(); print("client, inflight, mailbox and storage bounds passed");
}
fn many(base: const u8[:], count: i64) {
    var s = lab_net_http_clients::create(lab_net_http_clients::Limits { clients: count, workers: 8 });
    var ids: lab_net_http_clients::Id[..64] = [];
    var serials: u64[64] = [0; 64]; var generations: u64[64] = [1; 64];
    for i in count { let id, code = lab_net_http_clients::open(s); assert(code == 0); ids.push(id); }
    for round in 12 {
        for i in count {
            let text = str(count, "-", round, "-", i);
            assert(lab_net_http_clients::get(s, ids[i], get(base, str("/value/", text))) == 0); serials[i]++;
        }
        // All cancel/close decisions precede adoption, independent of network
        // completion ordering. The model uses only IDs, serials and literal data.
        for i in count {
            if (i + round) % 4 == 0 { assert(lab_net_http_clients::close(s, ids[i]) == 0); }
            else if (i + round) % 3 == 0 { assert(lab_net_http_clients::cancel(s, ids[i]) == 0); }
        }
        drain(s);
        for i in count {
            if (i + round) % 4 == 0 {
                let stale = ids[i]; let id, code = lab_net_http_clients::open(s); assert(code == 0);
                // Open in ascending order, reusing the closed descriptor slots.
                assert(id.slot == stale.slot && id.generation == generations[i] + 1);
                generations[i]++; ids[i] = id; serials[i] = 0;
                let missing, mc = lab_net_http_clients::take(s, stale); assert(mc == lab_net_http_clients::STALE);
                assert(!lab_net_http_clients::info(s, id).busy && !lab_net_http_clients::info(s, id).ready);
                print("closed,", count, ",", round, ",", i);
            } else {
                let cancelled = (i + round) % 3 == 0;
                let expected: u8[>..] = if cancelled { "" } else { str(count, "-", round, "-", i) };
                let value = result(s, ids[i], expected, if cancelled { lab_net_http::CANCELLED } else { 0 });
                assert(value.serial == serials[i] && value.client.generation == generations[i]);
                print("result,", count, ",", round, ",", i, ",", value.serial, ",", value.client.generation, ",", value.response.code, ",", value.response.body);
            }
        }
    }
    lab_net_http_clients::shutdown(s); assert(lab_net_http_clients::stats(s).submitted == count * 12);
    assert(lab_net_http_clients::stats(s).payload_bytes == 0); tokens_released(); print("many,", count, ",passed");
}
fn main() {
    let argv = args(); assert(argv.len == 2); assert(lab_net_http::init() == 0);
    lifetimes(argv[1]); bounds(argv[1]); for count in [3, 16, 64] { many(argv[1], count); }
    lab_net_http::shutdown(); print("HTTP client contracts passed");
}
