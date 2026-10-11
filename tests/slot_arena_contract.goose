import std;
import lab.buffer.slot_arena;
struct Model { data: u8[..256] = [] }
fn unchanged(a: lab_buffer_slot_arena::Stats, b: lab_buffer_slot_arena::Stats) {
    assert(a.logical == b.logical && a.arena == b.arena && a.holes == b.holes && a.high_water == b.high_water);
    assert(a.written == b.written && a.exported == b.exported && a.reused == b.reused);
    assert(a.compactions == b.compactions && a.moved == b.moved && a.visits == b.visits);
}
fn boundaries() {
    assert(lab_buffer_slot_arena::create(lab_buffer_slot_arena::Limits { slots: 0 }).code == 1);
    assert(lab_buffer_slot_arena::create(lab_buffer_slot_arena::Limits { bytes: -1 }).code == 1);
    assert(lab_buffer_slot_arena::create(lab_buffer_slot_arena::Limits { value_bytes: 2097153 }).code == 1);
    var invalid = lab_buffer_slot_arena::create(lab_buffer_slot_arena::Limits { slots: 65 });
    assert(lab_buffer_slot_arena::put(invalid, 0, "bad") == 1); lab_buffer_slot_arena::compact(invalid); lab_buffer_slot_arena::clear_all(invalid);
    var s = lab_buffer_slot_arena::create(lab_buffer_slot_arena::Limits { slots: 4, bytes: 12, value_bytes: 12 });
    for i in 4 { assert(lab_buffer_slot_arena::put(s, i, "abc") == 0); }
    let owned, oc = lab_buffer_slot_arena::read(s, 2); assert(oc == 0);
    let before = lab_buffer_slot_arena::stats(s);
    assert(lab_buffer_slot_arena::put(s, 1, "abcd") == 2);
    assert(lab_buffer_slot_arena::put(s, -1, "") == 1 && lab_buffer_slot_arena::clear(s, 4) == 1);
    let bad, bc = lab_buffer_slot_arena::read(s, 4); assert(bc == 1 && bad.len == 0 && lab_buffer_slot_arena::size(s, -1) == -1);
    unchanged(before, lab_buffer_slot_arena::stats(s));
    assert(lab_buffer_slot_arena::clear(s, 0) == 0 && lab_buffer_slot_arena::clear(s, 2) == 0);
    let holes = lab_buffer_slot_arena::stats(s); assert(holes.logical == 6 && holes.arena == 12 && holes.holes == 6 && holes.moved == 0);
    // Two three-byte holes and no tail room: compact survivors only on demand.
    assert(lab_buffer_slot_arena::put(s, 0, "123456") == 0);
    let compacted = lab_buffer_slot_arena::stats(s); assert(compacted.logical == 12 && compacted.arena == 12 && compacted.compactions == 1 && compacted.moved == 6);
    assert(lab_buffer_slot_arena::clear(s, 1) == 0 && lab_buffer_slot_arena::put(s, 2, "xy") == 0);
    let reused = lab_buffer_slot_arena::stats(s); assert(reused.reused == 2 && reused.moved == 6 && reused.holes == 1);
    lab_buffer_slot_arena::compact(s); let packed = lab_buffer_slot_arena::stats(s);
    assert(packed.arena == 11 && packed.moved == 15 && packed.compactions == 2);
    lab_buffer_slot_arena::clear_all(s); assert(lab_buffer_slot_arena::stats(s).arena == 0 && owned == "abc");
    var zero = lab_buffer_slot_arena::create(lab_buffer_slot_arena::Limits { bytes: 0, value_bytes: 0 });
    assert(lab_buffer_slot_arena::put(zero, 0, "") == 0 && lab_buffer_slot_arena::put(zero, 0, "x") == 2);
    var other = lab_buffer_slot_arena::create(); assert(lab_buffer_slot_arena::put(other, 0, "other") == 0);
    assert(lab_buffer_slot_arena::put(s, 0, "first") == 0); lab_buffer_slot_arena::clear_all(s);
    let value, vc = lab_buffer_slot_arena::read(other, 0); assert(vc == 0 && value == "other");
    var output: u8[>..] = "prefix:"; assert(lab_buffer_slot_arena::append_to(other, 0, output) == 0 && output == "prefix:other");
    assert(lab_buffer_slot_arena::append_to(other, -1, output) == 1 && output == "prefix:other");
    var narrow = lab_buffer_slot_arena::create(lab_buffer_slot_arena::Limits { bytes: 12, value_bytes: 2 });
    assert(lab_buffer_slot_arena::put(narrow, 0, "xy") == 0); let narrow_before = lab_buffer_slot_arena::stats(narrow);
    assert(lab_buffer_slot_arena::put(narrow, 0, "abc") == 2); unchanged(narrow_before, lab_buffer_slot_arena::stats(narrow));
    print("slot arena boundaries and ownership passed");
}
fn maximum() {
    var s = lab_buffer_slot_arena::create(); var bytes: u8[>..] = []; bytes.resize(65536, 255);
    for slot in 64 { assert(lab_buffer_slot_arena::put(s, slot, bytes) == 0); }
    let owned, code = lab_buffer_slot_arena::read(s, 63); assert(code == 0);
    assert(lab_buffer_slot_arena::stats(s).arena == 4194304);
    for cycle in 64 {
        let slot = (cycle * 17 + 3) % 64; assert(lab_buffer_slot_arena::clear(s, slot) == 0);
        assert(lab_buffer_slot_arena::put(s, slot, bytes) == 0);
        let stats = lab_buffer_slot_arena::stats(s); assert(stats.logical == 4194304 && stats.high_water == 4194304 && stats.moved == 0);
        for index in [slot, (slot + 1) % 64, (slot + 31) % 64] {
            let value, vc = lab_buffer_slot_arena::read(s, index); assert(vc == 0 && value == bytes);
        }
    }
    lab_buffer_slot_arena::clear_all(s); assert(lab_buffer_slot_arena::stats(s).arena == 0 && owned == bytes);
    print("slot arena maximum: 4194304 bytes, 64 reuse cycles passed");
}
fn check(s: lab_buffer_slot_arena::Store&, models: const Model[:], count: i64) -> i64 {
    var logical: i64 = 0; var checksum: i64 = 0;
    for i in count {
        let actual, code = lab_buffer_slot_arena::read(s, i); assert(code == 0 && actual == models[i].data);
        assert(lab_buffer_slot_arena::size(s, i) == actual.len); logical += actual.len;
        for n in actual.len { checksum += (i + 1) * (n + 1) * actual[n]; }
        let a = s.spans[i];
        if a.bytes > 0 {
            assert(a.offset >= 0 && a.offset + a.bytes <= s.data.len);
            for j in i { let b = s.spans[j]; if b.bytes > 0 { assert(a.offset + a.bytes <= b.offset || b.offset + b.bytes <= a.offset); } }
        } else { assert(a.offset == 0); }
    }
    let stats = lab_buffer_slot_arena::stats(s);
    assert(stats.logical == logical && stats.arena <= s.limits.bytes && stats.holes == stats.arena - logical);
    assert(stats.high_water >= stats.arena); checksum
}
fn model(count: i64, initial: u64) {
    var s = lab_buffer_slot_arena::create(lab_buffer_slot_arena::Limits { slots: count, bytes: count * 73, value_bytes: 256 });
    var models: Model[64] = [Model {}; 64]; var seed = initial; var refused: i64 = 0;
    var exported: u8[>..] = []; var kept: u8[..256] = [];
    for step in 3000 {
        seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
        let slot = ((seed >> 8) % (count as u64)) as i64; let choice = ((seed >> 24) % 10) as i64;
        if choice < 7 {
            let length = ((seed >> 16) % 257) as i64; var bytes: u8[..256] = [];
            for n in length { bytes.push(((step + slot * 31 + n * 17) % 256) as u8); }
            var logical: i64 = 0; for i in count { logical += models[i].data.len; }
            let expected = if length > count * 73 - (logical - models[slot].data.len) { lab_buffer_slot_arena::LIMIT } else { 0 };
            let before = lab_buffer_slot_arena::stats(s); let code = lab_buffer_slot_arena::put(s, slot, bytes); assert(code == expected);
            if code == 0 { models[slot].data = bytes; } else { refused++; unchanged(before, lab_buffer_slot_arena::stats(s)); }
        } else if choice < 9 { assert(lab_buffer_slot_arena::clear(s, slot) == 0); models[slot].data.resize(0); }
        else { lab_buffer_slot_arena::compact(s); }
        if step == 100 { let bytes, code = lab_buffer_slot_arena::read(s, slot); assert(code == 0); exported = copy(bytes); kept = models[slot].data; }
        let checksum = check(s, models, count);
        if (step + 1) % 100 == 0 {
            let stats = lab_buffer_slot_arena::stats(s);
            print("arena,", count, ",", initial, ",", step + 1, ",", stats.logical, ",", stats.written, ",", refused, ",", checksum);
        }
    }
    lab_buffer_slot_arena::clear_all(s);
    assert(lab_buffer_slot_arena::stats(s).arena == 0 && exported == kept);
}
fn main() { boundaries(); maximum(); let seeds: u64[3] = [238147, 3984127, 4294967294]; for count in [3, 16, 64] { for seed in seeds { model(count, seed); } } print("Slot arena contracts passed"); }
