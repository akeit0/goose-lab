// Independently lived byte buffers over one caller-owned, grow-only byte arena.
namespace lab_buffer_indexed;
import std;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2; let STALE: i32 = 3;
let MAX_BUFFERS: i64 = 64; let MAX_CHUNKS: i64 = 4096; let DIRECTORY: i64 = 512;
struct Id { slot: i64 = -1, generation: u64 = 0 }
struct Limits { buffers: i64 = 64, bytes: i64 = 2097152, chunks: i64 = 4096, chunk_bytes: i64 = 4096 }
struct Buffer { generation: u64 = 0, open: bool = false, used: i64 = 0, slots: i32[..512] = [] }
struct Stats {
    buffers: i64 = 0, logical: i64 = 0, capacity: i64 = 0, high_water: i64 = 0,
    live_chunks: i64 = 0, peak_chunks: i64 = 0, allocated: i64 = 0, released: i64 = 0,
    zeroed: i64 = 0, written: i64 = 0, cleared: i64 = 0, reads: i64 = 0, lookups: i64 = 0,
    // Reserved directory entries and freelist entries, separate from live slots.
    directory_entries: i64 = 32768, freelist_entries: i64 = 4096,
}
// Fixed metadata before a single resizable tail. No pool name, slice or native
// allocation escapes the API. Fields are implementation state, not public views.
struct Store {
    code: i32 = OK, limits: Limits = Limits {}, buffers: Buffer[..64] = [],
    next: i32[4096] = [-1; 4096], spare: i64 = -1, live: i64 = 0,
    counters: Stats = Stats {}, data: u8[>..] = [],
}
fn create(limits: Limits = Limits {}) -> Store {
    if limits.buffers < 1 || limits.buffers > MAX_BUFFERS || limits.chunk_bytes < 1 || limits.chunk_bytes > 65536 ||
        limits.chunks < 1 || limits.chunks > MAX_CHUNKS || limits.chunks * limits.chunk_bytes > 134217728 ||
        limits.bytes < 0 || limits.bytes > 2097152 || limits.bytes > DIRECTORY * limits.chunk_bytes {
        return Store { code: INVALID };
    }
    Store { limits: limits }
}
fn valid(s: const Store&, id: Id) -> bool {
    s.code == OK && id.slot >= 0 && id.slot < s.buffers.len && s.buffers[id.slot].open && s.buffers[id.slot].generation == id.generation
}
fn open(s: Store&) -> Id, i32 {
    if s.code != OK { return Id {}, INVALID; }
    var slot: i64 = -1;
    for i in s.buffers.len { if !s.buffers[i].open && s.buffers[i].generation < 0xFFFFFFFFFFFFFFFF { slot = i; break; } }
    if slot < 0 {
        if s.buffers.len == s.limits.buffers { return Id {}, LIMIT; }
        s.buffers.push(Buffer {}); slot = s.buffers.len - 1;
    }
    let b .= s.buffers[slot]; b.generation++; b.open = true; b.used = 0;
    return Id { slot, b.generation }, OK;
}
fn size(s: const Store&, id: Id) -> i64 { if valid(s, id) { s.buffers[id.slot].used } else { -1 } }
fn capacity(s: const Store&, id: Id) -> i64 { if valid(s, id) { s.buffers[id.slot].slots.len * s.limits.chunk_bytes } else { -1 } }
fn stats(s: const Store&) -> Stats {
    var result = s.counters; result.live_chunks = s.live; result.high_water = s.data.len;
    for b in s.buffers { if b.open { result.buffers++; result.logical += b.used; } }
    result.capacity = s.live * s.limits.chunk_bytes; result
}
fn allocate(s: Store&) -> i64 {
    var slot = s.spare;
    if slot >= 0 {
        s.spare = s.next[slot];
        let base = slot * s.limits.chunk_bytes;
        for i in s.limits.chunk_bytes { s.data[base + i] = 0; }
    } else {
        slot = s.data.len / s.limits.chunk_bytes;
        s.data.resize(s.data.len + s.limits.chunk_bytes, 0);
    }
    s.next[slot] = -1; s.live++; s.counters.peak_chunks = max(s.counters.peak_chunks, s.live);
    s.counters.allocated++; s.counters.zeroed += s.limits.chunk_bytes; slot
}
fn release(s: Store&, slot: i64) {
    s.next[slot] = s.spare as i32; s.spare = slot; s.live--; s.counters.released++;
}
// Validate the entire request before the first allocation or payload write.
// These quotas are recoverable library refusals, not recoverable OS allocation.
fn ensure(s: Store&, id: Id, extra: i64) -> i32 {
    if !valid(s, id) { return STALE; }
    if extra < 0 { return INVALID; }
    if extra > s.limits.bytes - s.buffers[id.slot].used { return LIMIT; }
    let required = (s.buffers[id.slot].used + extra + s.limits.chunk_bytes - 1) / s.limits.chunk_bytes;
    let additional = max(0, required - s.buffers[id.slot].slots.len);
    if additional > s.limits.chunks - s.live { return LIMIT; }
    for i in additional { let slot = allocate(s); s.buffers[id.slot].slots.push(slot as i32); }
    OK
}
fn position(s: const Store&, id: Id, at: i64) -> i64 {
    let slot = s.buffers[id.slot].slots[at / s.limits.chunk_bytes];
    slot * s.limits.chunk_bytes + at % s.limits.chunk_bytes
}
fn append(s: Store&, id: Id, bytes: const u8[:]) -> i32 {
    let code = ensure(s, id, bytes.len); if code != OK { return code; }
    let before = s.buffers[id.slot].used;
    var copied: i64 = 0;
    while copied < bytes.len {
        let at = before + copied; let take = min(bytes.len - copied, s.limits.chunk_bytes - at % s.limits.chunk_bytes);
        let base = position(s, id, at);
        for i in take { s.data[base + i] = bytes[copied + i]; }
        copied += take;
    }
    s.buffers[id.slot].used += bytes.len; s.counters.written += bytes.len; OK
}
fn append_fill(s: Store&, id: Id, count: i64, byte: u8) -> i32 {
    let code = ensure(s, id, count); if code != OK { return code; }
    let before = s.buffers[id.slot].used;
    var copied: i64 = 0;
    while copied < count {
        let at = before + copied; let take = min(count - copied, s.limits.chunk_bytes - at % s.limits.chunk_bytes);
        let base = position(s, id, at);
        for i in take { s.data[base + i] = byte; }
        copied += take;
    }
    s.buffers[id.slot].used += count; s.counters.written += count; OK
}
fn read_at(s: Store&, id: Id, at: i64) -> u8, i32 {
    if !valid(s, id) { return 0, STALE; }
    if at < 0 || at >= s.buffers[id.slot].used { return 0, INVALID; }
    s.counters.reads++; s.counters.lookups++;
    return s.data[position(s, id, at)], OK;
}
fn read(s: const Store&, id: Id, start: i64, end: i64) -> u8[>..], i32 {
    if !valid(s, id) { return [], STALE; }
    if start < 0 || end < start || end > s.buffers[id.slot].used { return [], INVALID; }
    var result: u8[>..] = [];
    var at = start;
    while at < end {
        let take = min(end - at, s.limits.chunk_bytes - at % s.limits.chunk_bytes); let base = position(s, id, at);
        result.append(s.data[base..(base + take)]); at += take;
    }
    return result, OK;
}
fn write(s: Store&, id: Id, start: i64, bytes: const u8[:]) -> i32 {
    if !valid(s, id) { return STALE; }
    let used = s.buffers[id.slot].used;
    if start < 0 || start > used || bytes.len > used - start { return INVALID; }
    var copied: i64 = 0;
    while copied < bytes.len {
        let at = start + copied; let take = min(bytes.len - copied, s.limits.chunk_bytes - at % s.limits.chunk_bytes);
        let base = position(s, id, at);
        for i in take { s.data[base + i] = bytes[copied + i]; }
        copied += take;
    }
    s.counters.written += bytes.len; OK
}
fn truncate(s: Store&, id: Id, length: i64) -> i32 {
    if !valid(s, id) { return STALE; }
    let b .= s.buffers[id.slot]; if length < 0 || length > b.used { return INVALID; }
    if length == b.used { return OK; }
    let kept = (length + s.limits.chunk_bytes - 1) / s.limits.chunk_bytes;
    while b.slots.len > kept { let slot = b.slots.pop(); release(s, slot); }
    let end = kept * s.limits.chunk_bytes;
    for at in length..end { s.data[position(s, id, at)] = 0; }
    s.counters.cleared += end - length; b.used = length; OK
}
fn close(s: Store&, id: Id) -> i32 {
    if !valid(s, id) { return STALE; }
    let b .= s.buffers[id.slot]; while b.slots.len > 0 { let slot = b.slots.pop(); release(s, slot); }
    b.used = 0; b.open = false; OK
}
fn close_all(s: Store&) { for i in s.buffers.len { if s.buffers[i].open { close(s, Id { i, s.buffers[i].generation }); } } }
