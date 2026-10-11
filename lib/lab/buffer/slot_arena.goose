// Bounded variable-length values in stable caller-assigned slots.
namespace lab_buffer_slot_arena;
import std;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2;
struct Limits { slots: i64 = 64, bytes: i64 = 4194304, value_bytes: i64 = 65536 }
struct Span { offset: i64 = 0, bytes: i64 = 0 }
struct Stats { logical: i64 = 0, arena: i64 = 0, holes: i64 = 0, high_water: i64 = 0,
    written: i64 = 0, exported: i64 = 0, reused: i64 = 0, compactions: i64 = 0, moved: i64 = 0, visits: i64 = 0 }
// Slots have no lifetime/generation of their own: the caller owns their identity.
// No borrowed arena slice escapes. Fields are implementation state.
struct Store { code: i32 = OK, limits: Limits = Limits {}, spans: Span[64] = [Span {}; 64],
    counters: Stats = Stats {}, data: u8[>..<] = [] }
fn create(limits: Limits = Limits {}) -> Store {
    if limits.slots < 1 || limits.slots > 64 || limits.bytes < 0 || limits.bytes > 134217728 ||
        limits.value_bytes < 0 || limits.value_bytes > 2097152 { return Store { code: INVALID }; }
    Store { limits: limits }
}
fn valid(s: const Store&, slot: i64) -> bool { s.code == OK && slot >= 0 && slot < s.limits.slots }
fn size(s: const Store&, slot: i64) -> i64 { if valid(s, slot) { s.spans[slot].bytes } else { -1 } }
fn stats(s: const Store&) -> Stats {
    var out = s.counters; out.arena = s.data.len; out.holes = out.arena - out.logical; out
}
// Clear only metadata and trim unused trailing bytes; survivors never move.
fn clear(s: Store&, slot: i64) -> i32 {
    if !valid(s, slot) { return INVALID; }
    s.counters.logical -= s.spans[slot].bytes; s.spans[slot] = Span {};
    var end: i64 = 0;
    for i in s.limits.slots { let p = s.spans[i]; if p.bytes > 0 { end = max(end, p.offset + p.bytes); } }
    s.data.resize(end); OK
}
fn clear_all(s: Store&) {
    if s.code != OK { return; }
    for i in s.limits.slots { s.spans[i] = Span {}; } s.counters.logical = 0; s.data.resize(0);
}
// Find the first sufficient gap in physical order, without a freelist. At most
// 64 scans of 64 records; visits measure that fixed-table addressing work.
fn gap(s: Store&, count: i64) -> i64 {
    var at: i64 = 0;
    loop {
        var next = s.limits.bytes; var end = next;
        for i in s.limits.slots {
            s.counters.visits++; let p = s.spans[i];
            if p.bytes > 0 && p.offset >= at && p.offset < next { next = p.offset; end = p.offset + p.bytes; }
        }
        if count <= next - at { return at; }
        if next == s.limits.bytes { return -1; } at = end;
    }
}
// Preserve slot identity while remapping internal offsets. Forward copies are
// safe for overlapping leftward moves. The caller never holds internal slices.
fn compact(s: Store&) {
    if s.code != OK { return; }
    s.counters.compactions++; var source: i64 = 0; var target: i64 = 0;
    loop {
        var slot: i64 = -1; var at = s.data.len;
        for i in s.limits.slots {
            s.counters.visits++; let p = s.spans[i];
            if p.bytes > 0 && p.offset >= source && p.offset < at { slot = i; at = p.offset; }
        }
        if slot < 0 { break; }
        let count = s.spans[slot].bytes; source = at + count;
        if at != target { for i in count { s.data[target + i] = s.data[at + i]; } s.counters.moved += count; }
        s.spans[slot].offset = target; target += count;
    }
    assert(target == s.counters.logical); s.data.resize(target);
}
// Full preflight before any mutation, including replacing the previous value.
// A logical quota refusal leaves payload, layout and counters unchanged.
fn put(s: Store&, slot: i64, bytes: const u8[:]) -> i32 {
    if !valid(s, slot) { return INVALID; }
    let retained = s.counters.logical - s.spans[slot].bytes;
    if bytes.len > s.limits.value_bytes || bytes.len > s.limits.bytes - retained { return LIMIT; }
    assert(clear(s, slot) == OK); if bytes.len == 0 { return OK; }
    var at = gap(s, bytes.len);
    if at < 0 { compact(s); at = s.data.len; } // Total preflight guarantees fit.
    assert(at >= 0 && bytes.len <= s.limits.bytes - at);
    s.counters.reused += max(0, min(bytes.len, s.data.len - at));
    s.data.resize(max(s.data.len, at + bytes.len), 0);
    for i in bytes.len { s.data[at + i] = bytes[i]; }
    s.spans[slot] = Span { at, bytes.len }; s.counters.logical += bytes.len;
    s.counters.written += bytes.len; s.counters.high_water = max(s.counters.high_water, s.data.len); OK
}
// Copy directly into a caller-owned output, avoiding an intermediate export.
fn append_to(s: Store&, slot: i64, out: u8[>..]&) -> i32 {
    if !valid(s, slot) { return INVALID; }
    let p = s.spans[slot];
    if p.bytes > 0 { out.append(s.data[p.offset..p.offset + p.bytes]); }
    s.counters.exported += p.bytes; OK
}
fn read(s: Store&, slot: i64) -> u8[>..], i32 {
    var out: u8[>..] = []; let code = append_to(s, slot, out); return out, code;
}
