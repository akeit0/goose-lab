import std;
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
fn sequences(count: i64) {
    var s = lab_buffer_indexed::create(lab_buffer_indexed::Limits { bytes: 8192, chunk_bytes: 257 });
    var models: Model[..64] = [];
    for i in count { let id, code = lab_buffer_indexed::open(s); assert(code == 0); models.push(Model { id: id }); }
    var seed: u64 = 238147;
    for round in 900 {
        seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF; let slot = (seed % (count as u64)) as i64;
        let m .= models[slot]; let choice = (seed >> 24) % 6;
        if choice == 0 {
            let stale = m.id; assert(lab_buffer_indexed::close(s, stale) == 0); m.bytes.clear();
            let id, code = lab_buffer_indexed::open(s); assert(code == 0); m.id = id;
            assert(lab_buffer_indexed::append(s, stale, "stale") == lab_buffer_indexed::STALE);
        } else if choice == 1 && m.bytes.len > 0 {
            let length = (seed % ((m.bytes.len + 1) as u64)) as i64;
            assert(lab_buffer_indexed::truncate(s, m.id, length) == 0); m.bytes.resize(length);
        } else if choice == 2 && m.bytes.len > 0 {
            let at = (seed % (m.bytes.len as u64)) as i64; let byte = ((seed >> 16) % 256) as u8;
            let patch: u8[1] = [byte]; assert(lab_buffer_indexed::write(s, m.id, at, patch) == 0); m.bytes[at] = byte;
        } else {
            var payload: u8[..600] = []; let length = min(8192 - m.bytes.len, (seed % 600 + 1) as i64);
            for i in length { payload.push(((i * 73 + slot * 11 + round) % 256) as u8); }
            assert(lab_buffer_indexed::append(s, m.id, payload) == 0); m.bytes.append(payload);
        }
        check(s, m);
        if round % 29 == 0 { for model in models { check(s, model); } }
    }
    for model in models { check(s, model); }
    // Arbitrary lifetime order; the survivors retain their independently owned bytes.
    for parity in 2 { for i in count { if i % 2 == parity { assert(lab_buffer_indexed::close(s, models[i].id) == 0); } else if parity == 0 { check(s, models[i]); } } }
    let end = lab_buffer_indexed::stats(s); assert(end.buffers == 0 && end.logical == 0 && end.live_chunks == 0 && end.allocated == end.released);
    assert(end.lookups == end.reads && end.directory_entries == 32768);
    print(count, " buffers: 900 model operations, stale IDs, quota refusal and cleanup passed");
}
fn main() { quotas(); independent_stores(); sequences(3); sequences(16); sequences(64); }
