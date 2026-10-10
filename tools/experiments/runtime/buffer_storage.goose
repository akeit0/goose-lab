// Same logical work on a geometric run or a linked list of fixed-size pool chunks.
// Only standard modules: this source is shared by the recorded upstream and fork.
import std;
import os;
reusable[] var pool: u8[>..] = [];
struct Buffer { bytes: u8[:] = pool[..0], offset: i64 = 0, used: i64 = 0, capacity: i64 = 0,
    first: i64 = -1, last: i64 = -1, pattern: u8 = 1 }
struct Chunk { bytes: u8[:] = pool[..0], offset: i64 = 0, next: i64 = -1 }
struct Range { start: i64, end: i64 }
var buffers: Buffer[..64] = [];
// A fixed, reusable metadata table. This bound is experiment policy, not a Goose limit.
var chunks: Chunk[..4096] = [];
var spare: i64 = -1;
var live_chunks: i64 = 0;
var moved: i64 = 0; var zeroed: i64 = 0; var written: i64 = 0;
var alloc_calls: i64 = 0; var realloc_calls: i64 = 0; var free_calls: i64 = 0;
var read_calls: i64 = 0; var address_visits: i64 = 0;
fn slot() -> i64 {
    if spare >= 0 { let result = spare; spare = chunks[result].next; return result; }
    assert(chunks.len < 4096); chunks.push(Chunk {}); chunks.len - 1
}
fn observe(phase: const u8[:], operation: const u8[:], elapsed: i64, chunked: bool) {
    var logical: i64 = 0; var capacity: i64 = 0; var spans: Range[..4096] = [];
    for b in buffers {
        logical += b.used; capacity += b.capacity;
        if chunked {
            var at = b.first; var run_capacity: i64 = 0;
            while at >= 0 { let c = chunks[at]; assert(c.bytes.len > 0);
                spans.push(Range { c.offset, c.offset + c.bytes.len }); run_capacity += c.bytes.len; at = c.next; }
            assert(run_capacity == b.capacity);
        } else if b.capacity > 0 { spans.push(Range { b.offset, b.offset + b.capacity }); }
    }
    assert(!chunked || spans.len == live_chunks);
    fn less(a: const Range&, b: const Range&) -> bool { a.start < b.start }
    sort(spans, less); var end: i64 = 0; var largest: i64 = 0;
    for r in spans { assert(r.start >= end); largest = max(largest, r.start - end); end = r.end; }
    largest = max(largest, pool.len - end);
    let duration: u8[>..] = if elapsed < 0 { "" } else { str(elapsed) };
    print(phase, ",", operation, ",", duration, ",", logical, ",", capacity, ",", pool.len,
        ",", pool.len - capacity, ",", largest, ",", moved, ",", zeroed, ",", written,
        ",", alloc_calls, ",", realloc_calls, ",", free_calls, ",", spans.len, ",", live_chunks,
        ",", chunks.len, ",", read_calls, ",", address_visits);
}
fn append_run(index: i64, size: i64, phase: const u8[:]) {
    let b .= buffers[index]; let old_capacity = b.capacity; let required = b.used + size;
    var elapsed: i64 = -1;
    if required > old_capacity {
        let target = max(required, old_capacity * 2); let before = clock_ns();
        let run = pool.realloc_slice(b.bytes, target); elapsed = clock_ns() - before;
        let offset = pool.index_of(run[0]);
        if old_capacity > 0 && offset != b.offset { moved += old_capacity; }
        realloc_calls++; zeroed += target - old_capacity;
        b.bytes = run; b.offset = offset; b.capacity = target;
        for i in old_capacity..target { assert(b.bytes[i] == 0); }
    }
    for i in b.used..required { assert(b.bytes[i] == 0); b.bytes[i] = b.pattern; }
    b.used = required; written += size;
    observe(phase, if elapsed < 0 { "append_reserved" } else { "append_realloc" }, elapsed, false);
}
fn append_chunks(index: i64, size: i64, chunk_size: i64, phase: const u8[:]) {
    let b .= buffers[index]; var remaining = size; var elapsed: i64 = 0; var allocations: i64 = 0;
    while remaining > 0 {
        if b.used == b.capacity {
            let before = clock_ns(); let run = pool.alloc_slice(chunk_size); elapsed += clock_ns() - before;
            let offset = pool.index_of(run[0]); alloc_calls++; zeroed += chunk_size; allocations++;
            for byte in run { assert(byte == 0); }
            let at = slot(); chunks[at] = Chunk { run, offset, -1 }; live_chunks++;
            if b.last >= 0 { chunks[b.last].next = at; } else { b.first = at; }
            b.last = at; b.capacity += chunk_size;
        }
        let local = b.used % chunk_size; let take = min(remaining, chunk_size - local);
        let tail .= chunks[b.last];
        for i in local..(local + take) { assert(tail.bytes[i] == 0); tail.bytes[i] = b.pattern; }
        b.used += take; remaining -= take;
    }
    written += size;
    observe(phase, if allocations == 0 { "append_reserved" } else { "append_alloc" },
        if allocations == 0 { -1 } else { elapsed }, true);
}
fn append(index: i64, size: i64, chunk_size: i64, phase: const u8[:], chunked: bool) {
    if chunked { append_chunks(index, size, chunk_size, phase); } else { append_run(index, size, phase); }
}
fn verify(chunked: bool) {
    for b in buffers {
        if chunked {
            var at = b.first; var remaining = b.used;
            while at >= 0 { let c = chunks[at]; let take = min(remaining, c.bytes.len);
                for byte in c.bytes[..take] { assert(byte == b.pattern); }
                for byte in c.bytes[take..] { assert(byte == 0); }
                remaining -= take; at = c.next; }
            assert(remaining == 0);
        } else {
            for byte in b.bytes[..b.used] { assert(byte == b.pattern); }
            for byte in b.bytes[b.used..] { assert(byte == 0); }
        }
    }
}
fn read_at(index: i64, offset: i64, chunked: bool) -> u8 {
    read_calls++; let b = buffers[index]; assert(offset >= 0 && offset < b.used);
    if !chunked { address_visits++; return b.bytes[offset]; }
    var at = b.first; var local = offset;
    while at >= 0 { address_visits++; let c = chunks[at];
        if local < c.bytes.len { return c.bytes[local]; } local -= c.bytes.len; at = c.next; }
    assert(false); 0
}
fn read_probe(phase: const u8[:], chunked: bool) {
    let before = clock_ns();
    for i in buffers.len { if buffers[i].used > 0 {
        for sample in 64 { let offset = (sample * 7919 + i * 101) % buffers[i].used;
            assert(read_at(i, offset, chunked) == buffers[i].pattern); }
    } }
    let elapsed = clock_ns() - before; observe(phase, "read_probe", elapsed, chunked);
}
fn close(index: i64, phase: const u8[:], chunked: bool) {
    let b .= buffers[index]; var elapsed: i64 = 0;
    if chunked {
        var at = b.first;
        while at >= 0 { let next = chunks[at].next; let before = clock_ns();
            pool.free_slice(chunks[at].bytes); elapsed += clock_ns() - before; free_calls++;
            chunks[at] = Chunk { pool[..0], 0, spare }; spare = at; live_chunks--; at = next; }
    } else if b.capacity > 0 { let before = clock_ns(); pool.free_slice(b.bytes);
        elapsed = clock_ns() - before; free_calls++; }
    // Reopening writes a different pattern, so accidental reuse of old payload is detected.
    b.bytes = pool[..0]; b.used = 0; b.capacity = 0; b.offset = 0; b.first = -1; b.last = -1;
    b.pattern = ((b.pattern as i64 + 71) % 251 + 1) as u8;
    observe(phase, "close", elapsed, chunked);
}
fn amount(index: i64, round: i64, step: i64, mixed: bool) -> i64 {
    // Persistent per-buffer size differences plus alternating append sizes.
    let factor = if mixed { index % 4 + 1 + round % 2 } else { 1 }; step * factor
}
fn main() {
    let argv = args(); assert(argv.len == 7);
    assert(argv[1] == "geometric" || argv[1] == "chunked"); let chunked = argv[1] == "chunked";
    let count, co = parse_int(argv[2]); let step, so = parse_int(argv[3]); let rounds, ro = parse_int(argv[4]);
    let chunk_size, cs = parse_int(argv[5]); let workload = argv[6];
    assert(co && count >= 1 && count <= 64 && so && step >= 1 && step <= 65536 && ro && rounds >= 1 && rounds <= 256);
    assert(cs && chunk_size >= 1 && chunk_size <= 65536);
    assert(workload == "uniform" || workload == "mixed" || workload == "churn");
    let mixed = workload != "uniform"; let churn = workload == "churn";
    let factor = if mixed { 5 } else { 1 }; let maximum = step * rounds * factor;
    let reopened = if churn { (count + 1) / 2 } else { 0 };
    let work_bound = count * maximum + reopened * step * max(1, rounds / 2) * 5;
    assert(max(work_bound * 4, work_bound + (count + reopened) * chunk_size) <= 134217728);
    assert(count * ((maximum + chunk_size - 1) / chunk_size) <= 4096);
    for i in count { buffers.push(Buffer { pattern: (i + 1) as u8 }); }
    print("phase,operation,elapsed_ns,logical_bytes,capacity_bytes,high_water_bytes,free_bytes,largest_free_run_bytes,moved_capacity_bytes,zeroed_bytes,application_write_bytes,alloc_calls,realloc_calls,free_calls,live_runs,metadata_live_slots,metadata_high_water_slots,read_calls,address_visits");
    for round in rounds { for i in count { append(i, amount(i, round, step, mixed), chunk_size, "grow", chunked); } }
    verify(chunked); observe("grow", "growth_end", -1, chunked); read_probe("grow", chunked);
    if churn {
        for i in count { if i % 2 == 0 { close(i, "retire", chunked); verify(chunked); } }
        observe("retire", "retired_end", -1, chunked);
        for round in max(1, rounds / 2) { for i in count { if i % 2 == 0 {
            append(i, amount(i, round + rounds, step, true), chunk_size, "reopen", chunked);
        } } }
        verify(chunked); observe("reopen", "reopened_end", -1, chunked); read_probe("reopen", chunked);
    }
    // Even slots first, then odd slots: deliberately non-LIFO lifetimes.
    for parity in 2 { for i in count { if i % 2 == parity { close(i, "cleanup", chunked); verify(chunked); } } }
    assert(live_chunks == 0); observe("cleanup", "cleanup_end", -1, chunked);
    let high = pool.len; let before = clock_ns(); let run = pool.alloc_slice(high); let elapsed = clock_ns() - before;
    assert(pool.index_of(run[0]) == 0 && pool.len == high); for byte in run { assert(byte == 0); }
    pool.free_slice(run); observe("cleanup", "reuse_probe", elapsed, chunked); // Excluded from counters.
}
