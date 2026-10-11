// Use the public library on the same append/read/retire/reopen trace as buffer_storage.
import std;
import os;
import lab.buffer.indexed;
struct Entry { id: lab_buffer_indexed::Id, pattern: u8 = 1 }
fn observe(s: const lab_buffer_indexed::Store&, phase: const u8[:], operation: const u8[:], elapsed: i64) {
    let stats = lab_buffer_indexed::stats(s); var occupied: bool[4096] = [false; 4096];
    for b in s.buffers { if b.open { for slot in b.slots { assert(!occupied[slot]); occupied[slot] = true; } } }
    var gap: i64 = 0; var largest: i64 = 0;
    for i in (s.data.len / s.limits.chunk_bytes) { if occupied[i] { gap = 0; } else { gap += s.limits.chunk_bytes; largest = max(largest, gap); } }
    let duration: u8[>..] = if elapsed < 0 { "" } else { str(elapsed) };
    print(phase, ",", operation, ",", duration, ",", stats.logical, ",", stats.capacity, ",", stats.high_water,
        ",", stats.high_water - stats.capacity, ",", largest, ",0,", stats.zeroed, ",", stats.written,
        ",", stats.allocated, ",0,", stats.released, ",", stats.live_chunks, ",", stats.live_chunks,
        ",", s.data.len / s.limits.chunk_bytes, ",", stats.reads, ",", stats.lookups);
}
fn verify(s: const lab_buffer_indexed::Store&, entries: const Entry[:]) {
    for e in entries { if lab_buffer_indexed::valid(s, e.id) {
        var remaining = lab_buffer_indexed::size(s, e.id);
        // Diagnostic scan, as in the linked control: no owned-export copies.
        let b .= s.buffers[e.id.slot];
        for slot in b.slots {
            let base = slot * s.limits.chunk_bytes; let take = min(remaining, s.limits.chunk_bytes);
            for i in take { assert(s.data[base + i] == e.pattern); }
            for i in take..s.limits.chunk_bytes { assert(s.data[base + i] == 0); }
            remaining -= take;
        }
        assert(remaining == 0);
    } }
}
fn append(s: lab_buffer_indexed::Store&, e: Entry, size: i64, phase: const u8[:]) {
    let before = clock_ns(); assert(lab_buffer_indexed::append_fill(s, e.id, size, e.pattern) == 0);
    let elapsed = clock_ns() - before; observe(s, phase, "append_library", elapsed);
}
fn close(s: lab_buffer_indexed::Store&, e: Entry&, phase: const u8[:]) {
    let before = clock_ns(); assert(lab_buffer_indexed::close(s, e.id) == 0);
    let elapsed = clock_ns() - before; e.pattern = ((e.pattern as i64 + 71) % 251 + 1) as u8;
    observe(s, phase, "close_library", elapsed);
}
fn read_probe(s: lab_buffer_indexed::Store&, entries: const Entry[:], phase: const u8[:]) {
    let before = clock_ns();
    for i in entries.len { let used = lab_buffer_indexed::size(s, entries[i].id); if used > 0 {
        for sample in 64 { let byte, code = lab_buffer_indexed::read_at(s, entries[i].id, (sample * 7919 + i * 101) % used); assert(code == 0 && byte == entries[i].pattern); }
    } }
    let elapsed = clock_ns() - before; observe(s, phase, "read_probe", elapsed);
}
fn main() {
    let argv = args(); assert(argv.len == 7 && argv[1] == "indexed");
    let count, co = parse_int(argv[2]); let step, so = parse_int(argv[3]); let rounds, ro = parse_int(argv[4]);
    let chunk, cs = parse_int(argv[5]); let workload = argv[6];
    assert(co && count >= 1 && count <= 64 && so && step >= 1 && step <= 65536 && ro && rounds >= 1 && rounds <= 256 && cs && chunk >= 1 && chunk <= 65536);
    assert(workload == "uniform" || workload == "mixed" || workload == "churn");
    let mixed = workload != "uniform"; let churn = workload == "churn"; let maximum = step * rounds * (if mixed { 5 } else { 1 });
    assert(maximum <= 2097152 && maximum <= 512 * chunk && count * ((maximum + chunk - 1) / chunk) <= 4096);
    var s = lab_buffer_indexed::create(lab_buffer_indexed::Limits { bytes: min(2097152, 512 * chunk), chunks: min(4096, 134217728 / chunk), chunk_bytes: chunk });
    assert(s.code == 0); var entries: Entry[..64] = [];
    for i in count { let id, code = lab_buffer_indexed::open(s); assert(code == 0); entries.push(Entry { id: id, pattern: (i + 1) as u8 }); }
    print("phase,operation,elapsed_ns,logical_bytes,capacity_bytes,high_water_bytes,free_bytes,largest_free_run_bytes,moved_capacity_bytes,zeroed_bytes,application_write_bytes,alloc_calls,realloc_calls,free_calls,live_runs,metadata_live_slots,metadata_high_water_slots,read_calls,address_visits");
    for round in rounds { for i in count { append(s, entries[i], step * (if mixed { i % 4 + 1 + round % 2 } else { 1 }), "grow"); } }
    verify(s, entries); observe(s, "grow", "growth_end", -1); read_probe(s, entries, "grow");
    if churn {
        for i in count { if i % 2 == 0 { close(s, entries[i], "retire"); verify(s, entries); } }
        observe(s, "retire", "retired_end", -1);
        for i in count { if i % 2 == 0 { let old = entries[i].id; let id, code = lab_buffer_indexed::open(s); assert(code == 0 && !lab_buffer_indexed::valid(s, old)); entries[i].id = id; } }
        for round in max(1, rounds / 2) { for i in count { if i % 2 == 0 { append(s, entries[i], step * (i % 4 + 1 + (round + rounds) % 2), "reopen"); } } }
        verify(s, entries); observe(s, "reopen", "reopened_end", -1); read_probe(s, entries, "reopen");
    }
    for parity in 2 { for i in count { if i % 2 == parity { close(s, entries[i], "cleanup"); verify(s, entries); } } }
    let stats = lab_buffer_indexed::stats(s); assert(stats.live_chunks == 0 && stats.allocated == stats.released);
    observe(s, "cleanup", "cleanup_end", -1);
    // Check every freed slot can be used again without increasing arena high-water.
    let before = clock_ns(); var remaining = stats.high_water;
    while remaining > 0 { let id, code = lab_buffer_indexed::open(s); assert(code == 0);
        let take = min(remaining, s.limits.bytes / chunk * chunk); assert(take > 0);
        assert(lab_buffer_indexed::append_fill(s, id, take, 0) == 0); remaining -= take;
    }
    assert(s.data.len == stats.high_water); for byte in s.data { assert(byte == 0); }
    lab_buffer_indexed::close_all(s); let elapsed = clock_ns() - before;
    // Reuse probe operations are outside the experiment counters, as in the control.
    s.counters = stats; s.counters.buffers = 0; s.counters.logical = 0; s.counters.capacity = 0;
    observe(s, "cleanup", "reuse_library", elapsed);
}
