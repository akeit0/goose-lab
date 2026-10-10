// Upstream-compatible minimal experiment: only standard modules, no lab adapters.
import std;
import os;
fn contract() {
    reusable[] var p: u8[>..] = [];
    let a = p.alloc_slice(8); let b = p.alloc_slice(8);
    for i in a.len { a[i] = 11; } for i in b.len { b[i] = 22; }
    let moved = p.realloc_slice(a, 12);
    assert(p.index_of(moved[0]) != p.index_of(a[0]));
    for i in 8 { assert(moved[i] == 11 && b[i] == 22); }
    for i in 8..12 { assert(moved[i] == 0); }
    // Old views keep their old range; they do not follow a relocated run.
    let reused = p.alloc_slice(8); assert(p.index_of(reused[0]) == p.index_of(a[0]));
    for i in 8 { assert(a[i] == 0); reused[i] = 33; assert(a[i] == 33); }
    p.free_slice(b); let reopened = p.alloc_slice(8);
    for i in 8 { assert(b[i] == 0); reopened[i] = 44; assert(b[i] == 44); }
    p.free_slice(moved); p.free_slice(reused); p.free_slice(reopened);
    let high = p.len; let all = p.alloc_slice(high); assert(p.index_of(all[0]) == 0 && p.len == high);
    for byte in all { assert(byte == 0); } p.free_slice(all); assert(p.len == high);
    // Free bytes in separated holes cannot satisfy a contiguous run.
    reusable[] var fragmented: u8[>..] = [];
    let r0 = fragmented.alloc_slice(16); let r1 = fragmented.alloc_slice(16);
    let r2 = fragmented.alloc_slice(16); let r3 = fragmented.alloc_slice(16); let r4 = fragmented.alloc_slice(16);
    fragmented.free_slice(r0); fragmented.free_slice(r2);
    let extended = fragmented.alloc_slice(32); assert(fragmented.index_of(extended[0]) == 80 && fragmented.len == 112);
    fragmented.free_slice(r1); fragmented.free_slice(r3); fragmented.free_slice(r4); fragmented.free_slice(extended);
    let merged = fragmented.alloc_slice(64); assert(fragmented.index_of(merged[0]) == 0 && fragmented.len == 112);
    fragmented.free_slice(merged);
}
reusable[] var pool: u8[>..] = [];
struct Buffer { bytes: u8[:] = pool[..0], used: i64 = 0, offset: i64 = 0 }
var buffers: Buffer[..64] = [];
struct Range { start: i64, end: i64 }
var moved_bytes: i64 = 0;
var zeroed_bytes: i64 = 0;
var writes: i64 = 0;
var moves: i64 = 0;
var calls: i64 = 0;
fn observation(operation: const u8[:], elapsed: i64) {
    var logical: i64 = 0; var capacity: i64 = 0; var spans: Range[..64] = [];
    for b in buffers {
        logical += b.used; capacity += b.bytes.len;
        if b.bytes.len > 0 { spans.push(Range { b.offset, b.offset + b.bytes.len }); }
    }
    fn less(a: const Range&, b: const Range&) -> bool { a.start < b.start }
    sort(spans, less); var end: i64 = 0; var largest: i64 = 0;
    for r in spans { assert(r.start >= end); largest = max(largest, r.start - end); end = r.end; }
    largest = max(largest, pool.len - end);
    let duration: u8[>..] = if elapsed < 0 { "" } else { str(elapsed) };
    print(operation, ",", duration, ",", logical, ",", capacity, ",", pool.len, ",", pool.len - capacity,
        ",", largest, ",", moved_bytes, ",", zeroed_bytes, ",", writes, ",", moves, ",", calls);
}
fn grow(index: i64, step: i64, geometric: bool) {
    let b .= buffers[index]; let old_used = b.used; let old_capacity = b.bytes.len; let next_used = old_used + step;
    let before = clock_ns();
    if next_used > old_capacity {
        let old_offset = if old_capacity == 0 { -1 } else { b.offset };
        let target = if geometric { max(next_used, max(step, old_capacity * 2)) } else { next_used };
        let relocated = pool.realloc_slice(b.bytes, target);
        let after = clock_ns(); calls++; zeroed_bytes += target - old_capacity;
        b.offset = pool.index_of(relocated[0]); b.bytes = relocated;
        if old_capacity > 0 && b.offset != old_offset { moved_bytes += old_capacity; moves++; }
        // Checks/writes/statistics are deliberately outside the reallocation timer.
        for i in old_capacity..target { assert(b.bytes[i] == 0); }
        if old_used > 0 { assert(b.bytes[0] == (index + 1) as u8 && b.bytes[old_used - 1] == (index + 1) as u8); }
        for i in old_used..next_used { b.bytes[i] = (index + 1) as u8; } writes += step; b.used = next_used;
        observation("realloc", after - before);
    } else {
        for i in old_used..next_used { assert(b.bytes[i] == 0); b.bytes[i] = (index + 1) as u8; }
        writes += step; b.used = next_used;
        observation("append_reserved", -1); // No allocator call: timing intentionally absent.
    }
}
fn profile(count: i64, step: i64, rounds: i64, geometric: bool) {
    for i in count { buffers.push(Buffer {}); }
    for round in rounds { for i in count { grow(i, step, geometric); } }
    for i in count { let b = buffers[i]; assert(b.used == step * rounds); for byte in b.bytes[..b.used] { assert(byte == (i + 1) as u8); } }
    // Reverse-order cleanup and full reuse; the local contract covers non-LIFO frees.
    for i in count { let index = count - 1 - i; let before = clock_ns(); pool.free_slice(buffers[index].bytes); let elapsed = clock_ns() - before;
        buffers[index].bytes = pool[..0]; buffers[index].used = 0; observation("free", elapsed); }
    let high = pool.len; let before = clock_ns(); let reused = pool.alloc_slice(high); let elapsed = clock_ns() - before;
    assert(pool.index_of(reused[0]) == 0 && pool.len == high);
    for byte in reused { assert(byte == 0); }
    // The full-pool probe is temporary, outside the buffer accounting above.
    pool.free_slice(reused); observation("reuse_probe", elapsed);
}
fn main() {
    let argv = args(); assert(argv.len == 5);
    let count, co = parse_int(argv[2]); let step, so = parse_int(argv[3]); let rounds, ro = parse_int(argv[4]);
    assert(co && count >= 1 && count <= 64 && so && step >= 1 && step <= 65536 && ro && rounds >= 1 && rounds <= 256);
    // A pessimistic sum of all requested lengths bounds high-water below 128 MiB,
    // even if placement reused nothing. Keep this finite experiment below the
    // standard runtime reservation; reservation exhaustion is a separate probe.
    assert(count * step * rounds * (rounds + 1) <= 134217728);
    contract();
    if argv[1] == "contract" { print("pool runtime contract OK"); return; }
    assert(argv[1] == "exact" || argv[1] == "geometric");
    print("operation,elapsed_ns,logical_bytes,capacity_bytes,high_water_bytes,free_bytes,largest_free_run_bytes,moved_capacity_bytes,zeroed_growth_bytes,application_write_bytes,moves,realloc_calls");
    profile(count, step, rounds, argv[1] == "geometric");
}
