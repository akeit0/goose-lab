// Bounded host-owned page routing; eight statically typed ACK lanes.
namespace lab_io_stream;
import std;
import os;
import lab.io.cancel;
import lab.buffer.slot_arena;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2; let STALE: i32 = 3;
let BUSY: i32 = 4; let NOT_READY: i32 = 5; let CLOSED: i32 = 6;
let CANCELLED: i32 = 7; let TIMEOUT: i32 = 8; let FAILED: i32 = 9;
struct Lane0 {} struct Lane1 {} struct Lane2 {} struct Lane3 {}
struct Lane4 {} struct Lane5 {} struct Lane6 {} struct Lane7 {}
struct Id { slot: i64 = -1, generation: u64 = 0 }
struct Receipt { client: Id = Id {}, serial: u64 = 0, ticket: u64 = 0, sequence: u64 = 0, lane: i64 = -1 }
struct Request { client: Id, serial: u64, ticket: u64, token: lab_io_cancel::Token }
struct Ack<P, L> { ticket: u64, sequence: u64 }
// P is the fixed owned export type and queue identity. Packet transports a
// bounded byte image; adapters may supply a compact domain-specific codec.
struct Page<P> { receipt: Receipt, done: bool = false, code: i32 = OK, data: P = default<P>() }
let MAX_PACKET_BYTES: i64 = 65536;
// Queue image: 8-byte tail count + 53 fixed receipt/status bytes + data.len.
struct Packet<P> { receipt: Receipt, done: bool = false, code: i32 = OK, data: u8[>..] = [] }
struct Limits { clients: i64 = 64, inflight: i64 = 64, workers: i64 = 4 }
struct Flight { ticket: u64 = 0, client: Id = Id {}, serial: u64 = 0, next: u64 = 1, lane: i64 = -1,
    token: lab_io_cancel::Token = lab_io_cancel::Token {} }
struct Client<P> { generation: u64 = 0, open: bool = false, serial: u64 = 0, ticket: u64 = 0,
    cancelling: bool = false, ready: bool = false, held: bool = false, receipt: Receipt = Receipt {}, done: bool = false, code: i32 = OK }
struct Info { code: i32, serial: u64 = 0, busy: bool = false, ready: bool = false, held: bool = false, cancelling: bool = false }
struct Stats { clients: i64 = 0, inflight: i64 = 0, ready: i64 = 0, held: i64 = 0, workers: i64 = 0,
    submitted: i64 = 0, completed: i64 = 0, received: i64 = 0, discarded: i64 = 0, replaced: i64 = 0, acknowledgements: i64 = 0,
    queue_bytes: i64 = 0, payload_bytes: i64 = 0, peak_payload_bytes: i64 = 0, exported_bytes: i64 = 0, shifted_bytes: i64 = 0,
    arena_bytes: i64 = 0, peak_arena_bytes: i64 = 0, reused_bytes: i64 = 0, compactions: i64 = 0, storage_visits: i64 = 0 }
struct Service<P> { code: i32 = OK, running: bool = false, limits: Limits = Limits {}, workers: i64[..8] = [],
    next_ticket: u64 = 0, active: i64 = 0, clients: Client<P>[..64] = [], flights: Flight[64] = [Flight {}; 64], counters: Stats = Stats {}, payloads: lab_buffer_slot_arena::Store = lab_buffer_slot_arena::Store {} }
struct Wait { code: i32, rejected: i64 = 0 }
fn create<P>(limits: Limits = Limits {}) -> Service<P> {
    if limits.clients < 1 || limits.clients > 64 || limits.inflight < 1 || limits.inflight > 64 || limits.workers < 1 || limits.workers > 8 {
        return Service<P> { code: INVALID };
    }
    let one = [default<P>()]; let bytes = bytes_of(one).len; if bytes + 3 > MAX_PACKET_BYTES { return Service<P> { code: INVALID }; }
    Service<P> { running: true, limits: limits, payloads: lab_buffer_slot_arena::create(lab_buffer_slot_arena::Limits {
        slots: limits.clients, bytes: limits.clients * MAX_PACKET_BYTES, value_bytes: MAX_PACKET_BYTES }) }
}
fn valid<P>(s: const Service<P>&, id: Id) -> bool {
    s.running && s.code == OK && id.slot >= 0 && id.slot < s.clients.len && s.clients[id.slot].open && s.clients[id.slot].generation == id.generation
}
fn open<P>(s: Service<P>&) -> Id, i32 {
    if s.code != OK { return Id {}, INVALID; } if !s.running { return Id {}, CLOSED; }
    var slot: i64 = -1;
    for i in s.clients.len { if !s.clients[i].open && s.clients[i].generation < 0xFFFFFFFFFFFFFFFF { slot = i; break; } }
    if slot < 0 { if s.clients.len == s.limits.clients { return Id {}, LIMIT; } s.clients.push(Client<P> {}); slot = s.clients.len - 1; }
    let generation = s.clients[slot].generation + 1; s.clients[slot] = Client<P> { generation: generation, open: true };
    return Id { slot, generation }, OK;
}
fn info<P>(s: const Service<P>&, id: Id) -> Info {
    if !valid(s, id) { return Info { code: STALE }; }
    let c .= s.clients[id.slot]; Info { OK, c.serial, c.ticket != 0, c.ready, c.held, c.cancelling }
}
fn flight<P>(s: const Service<P>&, ticket: u64) -> i64 {
    if ticket == 0 { return -1; } for i in s.limits.inflight { if s.flights[i].ticket == ticket { return i; } } -1
}
// Adapters validate input before begin, then put exactly one owned job containing
// the returned Request. They may attach at most limits.workers worker IDs.
fn begin<P>(s: Service<P>&, id: Id) -> Request, i32 {
    let empty = Request { Id {}, 0, 0, lab_io_cancel::Token {} };
    if !valid(s, id) { return empty, STALE; }
    let c .= s.clients[id.slot]; if c.ticket != 0 || c.ready || c.held { return empty, BUSY; }
    if s.active == s.limits.inflight || s.next_ticket == 0xFFFFFFFFFFFFFFFF || c.serial == 0xFFFFFFFFFFFFFFFF { return empty, LIMIT; }
    let token = lab_io_cancel::create(); if token.id == 0 { return empty, LIMIT; }
    var index: i64 = -1; for i in s.limits.inflight { if s.flights[i].ticket == 0 { index = i; break; } } assert(index >= 0);
    s.next_ticket++; c.serial++; c.ticket = s.next_ticket; c.cancelling = false;
    s.flights[index] = Flight { ticket: c.ticket, client: id, serial: c.serial, token: token }; s.active++; s.counters.submitted++;
    return Request { id, c.serial, c.ticket, token }, OK;
}
fn packet<P>(page: const Page<P>&) -> Packet<P> {
    let one = [page.data];
    Packet<P> { page.receipt, page.done, page.code, to_bytes(one) }
}
fn publish_bytes<P>(request: Request, lane: i64, sequence: u64, data: const u8[:], done: bool = false, code: i32 = OK) {
    assert(lane >= 0 && lane < 8 && sequence > 0 && data.len <= MAX_PACKET_BYTES);
    qput(Packet<P> { Receipt { request.client, request.serial, request.ticket, sequence, lane }, done, code, data });
}
fn publish<P>(request: Request, lane: i64, sequence: u64, data: P, done: bool = false, code: i32 = OK) {
    let one = [data]; let image = to_bytes(one); publish_bytes<P>(request, lane, sequence, image, done, code);
}
// Remove a ready payload without moving survivors. Holes are reused on adoption.
// Held pages need only their receipt; their exported payload belongs to caller.
fn erase<P>(s: Service<P>&, slot: i64) {
    assert(lab_buffer_slot_arena::clear(s.payloads, slot) == 0);
}
fn send_ack<P>(receipt: Receipt) {
    match receipt.lane {
        0 => { qput(Ack<P, Lane0> { receipt.ticket, receipt.sequence }); },
        1 => { qput(Ack<P, Lane1> { receipt.ticket, receipt.sequence }); },
        2 => { qput(Ack<P, Lane2> { receipt.ticket, receipt.sequence }); },
        3 => { qput(Ack<P, Lane3> { receipt.ticket, receipt.sequence }); },
        4 => { qput(Ack<P, Lane4> { receipt.ticket, receipt.sequence }); },
        5 => { qput(Ack<P, Lane5> { receipt.ticket, receipt.sequence }); },
        6 => { qput(Ack<P, Lane6> { receipt.ticket, receipt.sequence }); },
        7 => { qput(Ack<P, Lane7> { receipt.ticket, receipt.sequence }); },
        _ => { assert(false); },
    }
}
fn drain_lane<P, L>() -> i64 {
    var count: i64 = 0; loop { let ack, available = qpoll<Ack<P, L>>(); if !available { break; } count++; } count
}
// Called only by that lane's worker. No worker ever reads another lane's ACKs.
fn await_ack<P, L>(request: Request, sequence: u64, deadline: i64) -> Wait {
    var rejected: i64 = 0;
    loop {
        if lab_io_cancel::requested(request.token) { return Wait { CANCELLED, rejected }; }
        if clock_ns() >= deadline { return Wait { TIMEOUT, rejected }; }
        let ack, available = qpoll<Ack<P, L>>();
        if available { if ack.ticket == request.ticket && ack.sequence == sequence { return Wait { OK, rejected }; } rejected++; }
        else { sleep_ms(1); }
    }
}
fn receive<P>(s: Service<P>&, page: const Packet<P>&) {
    assert(page.data.len <= MAX_PACKET_BYTES);
    s.counters.received++; s.counters.queue_bytes += 61 + page.data.len; let r = page.receipt; let index = flight(s, r.ticket);
    if index < 0 { s.counters.discarded++; return; }
    let f .= s.flights[index];
    if f.client.slot != r.client.slot || f.client.generation != r.client.generation || f.serial != r.serial ||
        (r.sequence != f.next && !(page.done && f.next > 1 && r.sequence == f.next - 1)) ||
        r.lane < 0 || r.lane >= s.limits.workers || (f.lane >= 0 && f.lane != r.lane) {
        s.counters.discarded++; return;
    }
    f.lane = r.lane;
    if page.done { lab_io_cancel::destroy(f.token); f.ticket = 0; s.active--; s.counters.completed++; }
    if !valid(s, r.client) { s.counters.discarded++; return; }
    let c .= s.clients[r.client.slot]; if c.ticket != r.ticket || c.serial != r.serial { s.counters.discarded++; return; }
    if c.cancelling && !page.done { s.counters.discarded++; return; }
    if !page.done && (c.ready || c.held) { s.counters.discarded++; return; }
    if page.done && (c.ready || c.held) { s.counters.replaced++; }
    let cancelled = c.cancelling && page.done;
    if cancelled { erase(s, r.client.slot); }
    else { assert(lab_buffer_slot_arena::put(s.payloads, r.client.slot, page.data) == 0); }
    c.receipt = r; c.done = page.done; c.code = if cancelled { CANCELLED } else { page.code }; c.ready = true; c.held = false;
    s.counters.peak_payload_bytes = max(s.counters.peak_payload_bytes, lab_buffer_slot_arena::stats(s.payloads).logical);
    if page.done { c.ticket = 0; c.cancelling = false; }
}
fn poll<P>(s: Service<P>&, maximum: i64 = 128) -> i64 {
    if !s.running || maximum <= 0 { return 0; }
    var count: i64 = 0; while count < maximum { let page, available = qpoll<Packet<P>>(); if !available { break; } receive(s, page); count++; } count
}
fn take_packet<P>(s: Service<P>&, id: Id) -> Packet<P>, i32 {
    if !valid(s, id) { return Packet<P> { receipt: Receipt {} }, STALE; }
    let c .= s.clients[id.slot]; if !c.ready { return Packet<P> { receipt: Receipt {} }, NOT_READY; }
    var result = Packet<P> { c.receipt, c.done, c.code };
    assert(lab_buffer_slot_arena::append_to(s.payloads, id.slot, result.data) == 0);
    s.counters.exported_bytes += result.data.len; erase(s, id.slot); c.ready = false; c.held = !c.done; return result, OK;
}
// Default fixed-P codec; compact domain adapters use take_packet and decode.
fn take<P>(s: Service<P>&, id: Id) -> Page<P>, i32 {
    let received, code = take_packet(s, id);
    var page = Page<P> { received.receipt, received.done, received.code };
    if code == OK && received.data.len > 0 {
        let values, valid_image = from_bytes<P[>..]>(received.data); assert(valid_image && values.len == 1); page.data = values[0];
    }
    return page, code;
}
fn ack<P>(s: Service<P>&, receipt: Receipt) -> i32 {
    if !valid(s, receipt.client) { return STALE; }
    let c .= s.clients[receipt.client.slot]; let held = c.receipt;
    if !c.held || c.cancelling || c.ticket == 0 { return NOT_READY; }
    if c.ticket != receipt.ticket || c.serial != receipt.serial || held.sequence != receipt.sequence || held.lane != receipt.lane { return STALE; }
    let index = flight(s, receipt.ticket); assert(index >= 0 && s.flights[index].next == receipt.sequence);
    assert(receipt.sequence < 0xFFFFFFFFFFFFFFFF); s.flights[index].next++; c.held = false;
    send_ack<P>(receipt); s.counters.acknowledgements++; OK
}
fn discard<P>(s: Service<P>&, id: Id) -> i32 {
    if !valid(s, id) { return STALE; }
    let c .= s.clients[id.slot]; if !c.ready { return NOT_READY; }
    let receipt = c.receipt; erase(s, id.slot); c.ready = false; c.held = !c.done;
    if c.held { return ack(s, receipt); } OK
}
fn cancel<P>(s: Service<P>&, id: Id) -> i32 {
    if !valid(s, id) { return STALE; }
    let c .= s.clients[id.slot]; if c.ticket == 0 { return NOT_READY; }
    let index = flight(s, c.ticket); assert(index >= 0 && lab_io_cancel::request(s.flights[index].token));
    erase(s, id.slot); c.cancelling = true; c.ready = false; c.held = false; OK
}
fn close<P>(s: Service<P>&, id: Id) -> i32 {
    if !valid(s, id) { return STALE; }
    if s.clients[id.slot].ticket != 0 { cancel(s, id); }
    erase(s, id.slot); s.clients[id.slot].open = false; s.clients[id.slot].ticket = 0; s.clients[id.slot].ready = false; s.clients[id.slot].held = false; OK
}
fn stats<P>(s: const Service<P>&) -> Stats {
    var out = s.counters; out.inflight = s.active; out.workers = s.workers.len;
    let storage = lab_buffer_slot_arena::stats(s.payloads); out.payload_bytes = storage.logical; out.shifted_bytes = storage.moved;
    out.arena_bytes = storage.arena; out.peak_arena_bytes = storage.high_water; out.reused_bytes = storage.reused;
    out.compactions = storage.compactions; out.storage_visits = storage.visits;
    for c in s.clients { if c.open { out.clients++; if c.ready { out.ready++; } if c.held { out.held++; } } } out
}
fn prepare_shutdown<P>(s: Service<P>&) {
    if !s.running { return; }
    for i in s.clients.len { if s.clients[i].open { close(s, Id { i, s.clients[i].generation }); } }
    for i in s.limits.inflight { if s.flights[i].ticket != 0 { lab_io_cancel::request(s.flights[i].token); } }
}
// Adapter first sends one stop per worker. This helper joins before draining
// terminal pages/tokens and ACKs; no native token is destroyed during worker use.
fn finish_shutdown<P>(s: Service<P>&) {
    if !s.running { return; }
    for worker in s.workers { thread_wait(worker); }
    loop { if poll(s) == 0 { break; } } assert(s.active == 0 && lab_buffer_slot_arena::stats(s.payloads).arena == 0);
    drain_lane<P, Lane0>(); drain_lane<P, Lane1>(); drain_lane<P, Lane2>(); drain_lane<P, Lane3>();
    drain_lane<P, Lane4>(); drain_lane<P, Lane5>(); drain_lane<P, Lane6>(); drain_lane<P, Lane7>();
    s.workers.resize(0); s.running = false;
}
