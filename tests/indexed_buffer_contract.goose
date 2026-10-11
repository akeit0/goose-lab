import std;
import os;
import lab.buffer.indexed;
struct Model { id: lab_buffer_indexed::Id = lab_buffer_indexed::Id {}, bytes: u8[..8192] = [] }
fn check(s: lab_buffer_indexed::Store&, model: const Model&) {
    let bytes, code = lab_buffer_indexed::read(s, model.id, 0, model.bytes.len);
    assert(code == lab_buffer_indexed::OK && bytes == model.bytes && lab_buffer_indexed::size(s, model.id) == model.bytes.len);
    if bytes.len > 0 { for at in [0, bytes.len / 2, bytes.len - 1] {
        let byte, status = lab_buffer_indexed::read_at(s, model.id, at); assert(status == lab_buffer_indexed::OK && byte == bytes[at]);
    } }
}
fn unchanged(before: lab_buffer_indexed::Stats, after: lab_buffer_indexed::Stats) {
    assert(before.logical == after.logical && before.capacity == after.capacity && before.high_water == after.high_water);
    assert(before.allocated == after.allocated && before.released == after.released && before.written == after.written && before.zeroed == after.zeroed);
    assert(before.buffers == after.buffers && before.live_chunks == after.live_chunks && before.peak_chunks == after.peak_chunks);
    assert(before.cleared == after.cleared && before.reads == after.reads && before.lookups == after.lookups);
}
fn quotas() {
    var invalid = lab_buffer_indexed::create(lab_buffer_indexed::Limits { chunk_bytes: 0 }); assert(invalid.code == lab_buffer_indexed::INVALID);
    var s = lab_buffer_indexed::create(lab_buffer_indexed::Limits { buffers: 2, bytes: 1024, chunks: 3, chunk_bytes: 257 });
    let a, ac = lab_buffer_indexed::open(s); let b, bc = lab_buffer_indexed::open(s); assert(ac == 0 && bc == 0);
    let no_id, no_code = lab_buffer_indexed::open(s); assert(no_code == lab_buffer_indexed::LIMIT && no_id.slot == -1);
    assert(lab_buffer_indexed::append_fill(s, a, 256, 'a') == 0 && lab_buffer_indexed::append_fill(s, b, 257, 'b') == 0);
    let before = lab_buffer_indexed::stats(s);
    // Needs two new chunks, only one is free: refuse the whole append.
    assert(lab_buffer_indexed::append_fill(s, a, 300, 'x') == lab_buffer_indexed::LIMIT); unchanged(before, lab_buffer_indexed::stats(s));
    assert(lab_buffer_indexed::append_fill(s, a, 0x7FFFFFFFFFFFFFFF, 0) == lab_buffer_indexed::LIMIT);
    assert(lab_buffer_indexed::append_fill(s, a, -1, 0) == lab_buffer_indexed::INVALID);
    assert(lab_buffer_indexed::write(s, a, 255, "xx") == lab_buffer_indexed::INVALID);
    assert(lab_buffer_indexed::truncate(s, a, 257) == lab_buffer_indexed::INVALID); unchanged(before, lab_buffer_indexed::stats(s));
    let old, old_code = lab_buffer_indexed::read(s, a, 0, 256); assert(old_code == 0 && old.len == 256);
    assert(lab_buffer_indexed::close(s, b) == 0 && lab_buffer_indexed::append_fill(s, a, 300, 'x') == 0);
    assert(lab_buffer_indexed::stats(s).high_water == 771); // Reuse the freed chunk before growing.
    let head, head_code = lab_buffer_indexed::read(s, a, 0, 256); assert(head_code == 0 && head == old);
    assert(lab_buffer_indexed::write(s, a, 255, "qrs") == 0);
    let patch, pc = lab_buffer_indexed::read(s, a, 254, 259); assert(pc == 0 && patch == "aqrsx");
    assert(lab_buffer_indexed::truncate(s, a, 255) == 0 && lab_buffer_indexed::append(s, a, "yz") == 0);
    let edge, edge_code = lab_buffer_indexed::read(s, a, 253, 257); assert(edge_code == 0 && edge == "aayz");
    let bad_byte, bad_at = lab_buffer_indexed::read_at(s, a, 257); assert(bad_at == lab_buffer_indexed::INVALID);
    let bad_read, bad_range = lab_buffer_indexed::read(s, a, -1, 257); assert(bad_range == lab_buffer_indexed::INVALID && bad_read.len == 0);
    assert(lab_buffer_indexed::close(s, a) == 0 && lab_buffer_indexed::close(s, a) == lab_buffer_indexed::STALE);
    let fresh, fresh_code = lab_buffer_indexed::open(s); assert(fresh_code == 0 && fresh.slot == a.slot && fresh.generation != a.generation);
    let stale_byte, stale_code = lab_buffer_indexed::read_at(s, a, 0); assert(stale_code == lab_buffer_indexed::STALE);
    assert(lab_buffer_indexed::size(s, a) == -1 && lab_buffer_indexed::append(s, a, "bad") == lab_buffer_indexed::STALE);
    assert(lab_buffer_indexed::write(s, a, 0, []) == lab_buffer_indexed::STALE && lab_buffer_indexed::truncate(s, a, 0) == lab_buffer_indexed::STALE);
    assert(lab_buffer_indexed::append_fill(s, fresh, 771, 0) == 0 && lab_buffer_indexed::stats(s).high_water == 771);
    let zeros, zc = lab_buffer_indexed::read(s, fresh, 0, 771); assert(zc == 0); for byte in zeros { assert(byte == 0); }
    lab_buffer_indexed::close_all(s); let end = lab_buffer_indexed::stats(s); assert(end.logical == 0 && end.live_chunks == 0 && end.allocated == end.released);
    var tiny = lab_buffer_indexed::create(lab_buffer_indexed::Limits { bytes: 512, chunk_bytes: 1 });
    let ti, tc = lab_buffer_indexed::open(tiny); assert(tc == 0 && lab_buffer_indexed::append_fill(tiny, ti, 512, 7) == 0);
    let full = lab_buffer_indexed::stats(tiny); assert(lab_buffer_indexed::append(tiny, ti, "x") == lab_buffer_indexed::LIMIT); unchanged(full, lab_buffer_indexed::stats(tiny));
    lab_buffer_indexed::close_all(tiny);
}
fn independent_stores() {
    var a = lab_buffer_indexed::create(); var b = lab_buffer_indexed::create();
    let ai, ac = lab_buffer_indexed::open(a); let bi, bc = lab_buffer_indexed::open(b); assert(ac == 0 && bc == 0);
    assert(lab_buffer_indexed::append(a, ai, "one") == 0 && lab_buffer_indexed::append(b, bi, "two") == 0);
    var copied, rc = lab_buffer_indexed::read(a, ai, 0, 3); assert(rc == 0); copied[0] = 'X';
    let original, oc = lab_buffer_indexed::read(a, ai, 0, 3); assert(oc == 0 && original == "one");
    lab_buffer_indexed::close_all(a); let result, code = lab_buffer_indexed::read(b, bi, 0, 3); assert(code == 0 && result == "two");
    lab_buffer_indexed::close_all(b);
}
fn filled(s: const lab_buffer_indexed::Store&, id: lab_buffer_indexed::Id, length: i64, pattern: u8) {
    let bytes, code = lab_buffer_indexed::read(s, id, 0, length);
    assert(code == 0 && bytes.len == length && lab_buffer_indexed::size(s, id) == length);
    for byte in bytes { assert(byte == pattern); }
}
fn maximum_capacity() {
    var s = lab_buffer_indexed::create();
    var ids: lab_buffer_indexed::Id[..64] = []; var patterns: u8[8] = [1, 2, 3, 4, 5, 6, 7, 8];
    let length: i64 = 2097152; let high: i64 = 16777216;
    for i in 64 { let id, code = lab_buffer_indexed::open(s); assert(code == 0); ids.push(id); }
    let before_open = lab_buffer_indexed::stats(s); let extra, opened = lab_buffer_indexed::open(s);
    assert(opened == lab_buffer_indexed::LIMIT && extra.slot == -1); unchanged(before_open, lab_buffer_indexed::stats(s));
    for i in 8 { assert(lab_buffer_indexed::append_fill(s, ids[i], length, patterns[i]) == 0); filled(s, ids[i], length, patterns[i]); }
    let full = lab_buffer_indexed::stats(s);
    assert(full.live_chunks == 4096 && full.capacity == high && full.logical == high && full.high_water == high);
    // A full directory and the aggregate chunk limit are separate refusals.
    assert(lab_buffer_indexed::append(s, ids[0], "x") == lab_buffer_indexed::LIMIT);
    assert(lab_buffer_indexed::append(s, ids[8], "x") == lab_buffer_indexed::LIMIT);
    unchanged(full, lab_buffer_indexed::stats(s));
    let exported, ec = lab_buffer_indexed::read(s, ids[0], 0, length); assert(ec == 0);
    for cycle in 64 {
        // A permutation retires different owners, not just the newest allocation.
        let index = (cycle * 5 + 3) % 8; let stale = ids[index];
        assert(lab_buffer_indexed::close(s, stale) == 0);
        let fresh, code = lab_buffer_indexed::open(s); assert(code == 0 && fresh.slot == stale.slot && fresh.generation != stale.generation);
        ids[index] = fresh; patterns[index] = ((cycle * 37) % 256) as u8;
        let empty = lab_buffer_indexed::stats(s);
        assert(lab_buffer_indexed::append_fill(s, fresh, length + 1, 0) == lab_buffer_indexed::LIMIT);
        unchanged(empty, lab_buffer_indexed::stats(s));
        assert(lab_buffer_indexed::append_fill(s, fresh, length, patterns[index]) == 0);
        assert(lab_buffer_indexed::append(s, stale, "bad") == lab_buffer_indexed::STALE);
        filled(s, fresh, length, patterns[index]);
        // Release 511 chunks, keep one byte, then refill at the maximum boundary.
        assert(lab_buffer_indexed::truncate(s, fresh, 1) == 0);
        assert(lab_buffer_indexed::append_fill(s, fresh, length - 1, patterns[index]) == 0);
        let tail: u8[3] = [9, 0, 255]; assert(lab_buffer_indexed::write(s, fresh, length - 3, tail) == 0);
        let edge, rc = lab_buffer_indexed::read(s, fresh, length - 4, length);
        assert(rc == 0 && edge.len == 4 && edge[0] == patterns[index] && edge[1..4] == tail);
        let restored: u8[3] = [patterns[index], patterns[index], patterns[index]];
        assert(lab_buffer_indexed::write(s, fresh, length - 3, restored) == 0);
        for survivor in 8 { for at in [0, 4095, 4096, length - 1] {
            let byte, status = lab_buffer_indexed::read_at(s, ids[survivor], at); assert(status == 0 && byte == patterns[survivor]);
        } }
        let reused = lab_buffer_indexed::stats(s);
        assert(reused.buffers == 64 && reused.live_chunks == 4096 && reused.logical == high && reused.high_water == high);
    }
    for i in 8 { filled(s, ids[i], length, patterns[i]); }
    lab_buffer_indexed::close_all(s);
    let end = lab_buffer_indexed::stats(s);
    assert(end.buffers == 0 && end.live_chunks == 0 && end.allocated == end.released && end.high_water == high);
    for byte in exported { assert(byte == 1); } // Export survives many close/reuse cycles.
    print("maximum capacity: 4096 chunks, 64 reuse cycles, high-water 16777216 passed");
}
fn sequences(count: i64, rounds: i64, initial_seed: u64) {
    var s = lab_buffer_indexed::create(lab_buffer_indexed::Limits { bytes: 8192, chunk_bytes: 257 });
    var models: Model[..64] = [];
    for i in count { let id, code = lab_buffer_indexed::open(s); assert(code == 0); models.push(Model { id: id }); }
    var seed = initial_seed; var closed: i64 = 0; var refused: i64 = 0;
    for round in rounds {
        seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF; let slot = (seed % (count as u64)) as i64;
        let m .= models[slot]; let choice = (seed >> 24) % 7;
        if choice == 0 {
            let stale = m.id; assert(lab_buffer_indexed::close(s, stale) == 0); m.bytes.clear();
            let id, code = lab_buffer_indexed::open(s); assert(code == 0); m.id = id;
            assert(lab_buffer_indexed::append(s, stale, "stale") == lab_buffer_indexed::STALE);
            closed++;
        } else if choice == 1 && m.bytes.len > 0 {
            let length = (seed % ((m.bytes.len + 1) as u64)) as i64;
            assert(lab_buffer_indexed::truncate(s, m.id, length) == 0); m.bytes.resize(length);
        } else if choice == 2 && m.bytes.len > 0 {
            let at = (seed % (m.bytes.len as u64)) as i64;
            var patch: u8[..600] = []; let length = min(m.bytes.len - at, (seed % 600 + 1) as i64);
            for i in length { patch.push(((seed + (i as u64) * 73) % 256) as u8); }
            assert(lab_buffer_indexed::write(s, m.id, at, patch) == 0);
            for i in length { m.bytes[at + i] = patch[i]; }
        } else if choice == 3 {
            let before = lab_buffer_indexed::stats(s);
            assert(lab_buffer_indexed::append_fill(s, m.id, 8193 - m.bytes.len, 99) == lab_buffer_indexed::LIMIT);
            unchanged(before, lab_buffer_indexed::stats(s)); refused++;
        } else {
            var payload: u8[..600] = []; let length = min(8192 - m.bytes.len, (seed % 600 + 1) as i64);
            for i in length { payload.push(((i * 73 + slot * 11 + round) % 256) as u8); }
            assert(lab_buffer_indexed::append(s, m.id, payload) == 0); m.bytes.append(payload);
        }
        check(s, m);
        if round % 29 == 0 {
            var logical: i64 = 0; var chunks: i64 = 0;
            for model in models { check(s, model); logical += model.bytes.len; chunks += (model.bytes.len + 256) / 257; }
            let current = lab_buffer_indexed::stats(s);
            assert(current.buffers == count && current.logical == logical && current.live_chunks == chunks && current.capacity == chunks * 257);
        }
    }
    for model in models { check(s, model); }
    // Arbitrary lifetime order; the survivors retain their independently owned bytes.
    for parity in 2 { for i in count { if i % 2 == parity { assert(lab_buffer_indexed::close(s, models[i].id) == 0); } else if parity == 0 { check(s, models[i]); } } }
    let end = lab_buffer_indexed::stats(s); assert(end.buffers == 0 && end.logical == 0 && end.live_chunks == 0 && end.allocated == end.released);
    assert(end.lookups == end.reads && end.directory_entries == 32768);
    assert(closed > 0 && refused > 0);
    print(count, " buffers: ", rounds, " model operations, seed ", initial_seed, ", ", closed, " reopens, ", refused, " refusals passed");
}
fn main() {
    let argv = args(); assert(argv.len == 1 || argv.len == 3);
    var rounds: i64 = 900; var seed: u64 = 238147;
    if argv.len == 3 {
        let n, nc = parse_int(argv[1]); let value, vc = parse_int(argv[2]);
        assert(nc && vc && n >= 900 && n <= 1000000 && value >= 0 && value <= 0xFFFFFFFF);
        rounds = n; seed = value as u64;
    }
    quotas(); independent_stores(); maximum_capacity();
    sequences(3, rounds, seed); sequences(16, rounds, seed); sequences(64, rounds, seed);
}
