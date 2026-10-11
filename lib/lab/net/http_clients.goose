// One explicit queue owner, many independently lived HTTP clients.
namespace lab_net_http_clients;
import std;
import lab.net.http;
import lab.io.cancel;
import lab.buffer.indexed;

let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2; let STALE: i32 = 3;
let BUSY: i32 = 4; let NOT_READY: i32 = 5; let CLOSED: i32 = 6;
struct Id { slot: i64 = -1, generation: u64 = 0 }
struct Limits {
    clients: i64 = 64, workers: i64 = 4, inflight: i64 = 64,
    body_bytes: i64 = 1048576, header_bytes: i64 = 65536,
    request_bytes: i64 = 1048576, chunks: i64 = 4096,
}
struct Job {
    stop: bool = false, ticket: u64 = 0, client: Id = Id {}, serial: u64 = 0,
    options: lab_net_http::Options = lab_net_http::Options {},
    url: u8[] = [], method: u8[] = [], headers: u8[] = [], body: u8[] = [], ca_file: u8[] = [],
}
struct Completed { ticket: u64, client: Id, serial: u64, response: lab_net_http::Response }
struct Flight { ticket: u64 = 0, client: Id = Id {}, token: lab_io_cancel::Token = lab_io_cancel::Token {} }
struct Client {
    generation: u64 = 0, open: bool = false, serial: u64 = 0, ticket: u64 = 0,
    cancelling: bool = false, ready: bool = false, code: i32 = 0, status: i64 = 0,
    body: i64 = 0, headers: i64 = 0, error: i64 = 0, buffer: lab_buffer_indexed::Id = lab_buffer_indexed::Id {},
}
struct Info { code: i32, serial: u64 = 0, busy: bool = false, ready: bool = false, cancelling: bool = false }
struct Result { client: Id, serial: u64, response: lab_net_http::Response }
struct Stats {
    clients: i64 = 0, inflight: i64 = 0, ready: i64 = 0, workers: i64 = 0,
    submitted: i64 = 0, completed: i64 = 0, discarded: i64 = 0, storage_refused: i64 = 0,
    payload_bytes: i64 = 0, arena_bytes: i64 = 0,
}
// Do not copy this resource owner. Exactly one Service owns these queue types
// in a program. All clients of this protocol must go through that Service.
struct Service {
    code: i32 = OK, running: bool = false, limits: Limits = Limits {},
    workers: i64[..8] = [], clients: Client[..64] = [], flights: Flight[64] = [Flight {}; 64],
    next_ticket: u64 = 0, active: i64 = 0, counters: Stats = Stats {},
    storage: lab_buffer_indexed::Store = lab_buffer_indexed::Store {},
}
thread_fn worker() {
    loop {
        let job = qget<Job>(); if job.stop { break; }
        let response = lab_net_http::send(lab_net_http::Request {
            url: job.url, method: job.method, headers: job.headers, body: job.body, ca_file: job.ca_file,
        }, job.options);
        qput(Completed { job.ticket, job.client, job.serial, copy(response) });
    }
}
// The caller initializes HTTP before create and shuts it down after shutdown.
fn create(limits: Limits = Limits {}) -> Service {
    if limits.clients < 1 || limits.clients > 64 || limits.workers < 1 || limits.workers > 8 ||
        limits.inflight < 1 || limits.inflight > 64 || limits.body_bytes < 0 || limits.body_bytes > 1048576 ||
        limits.header_bytes < 0 || limits.header_bytes > 65536 || limits.request_bytes < 1 || limits.request_bytes > 2097152 ||
        limits.chunks < 1 || limits.chunks > 4096 { return Service { code: INVALID }; }
    var s = Service { running: true, limits: limits, storage: lab_buffer_indexed::create(lab_buffer_indexed::Limits {
        buffers: limits.clients, bytes: limits.body_bytes + limits.header_bytes + 512, chunks: limits.chunks,
    }) };
    assert(s.storage.code == lab_buffer_indexed::OK);
    for i in limits.workers { s.workers.push(thread_spawn(worker)); }
    s
}
fn valid(s: const Service&, id: Id) -> bool {
    s.code == OK && s.running && id.slot >= 0 && id.slot < s.clients.len &&
        s.clients[id.slot].open && s.clients[id.slot].generation == id.generation
}
fn open(s: Service&) -> Id, i32 {
    if s.code != OK { return Id {}, INVALID; }
    if !s.running { return Id {}, CLOSED; }
    var slot: i64 = -1;
    for i in s.clients.len { if !s.clients[i].open && s.clients[i].generation < 0xFFFFFFFFFFFFFFFF { slot = i; break; } }
    if slot < 0 {
        if s.clients.len == s.limits.clients { return Id {}, LIMIT; }
        s.clients.push(Client {}); slot = s.clients.len - 1;
    }
    let buffer, code = lab_buffer_indexed::open(s.storage); assert(code == lab_buffer_indexed::OK);
    let generation = s.clients[slot].generation + 1;
    s.clients[slot] = Client { generation: generation, open: true, buffer: buffer };
    return Id { slot, generation }, OK;
}
fn info(s: const Service&, id: Id) -> Info {
    if !valid(s, id) { return Info { code: STALE }; }
    let c .= s.clients[id.slot]; Info { OK, c.serial, c.ticket != 0, c.ready, c.cancelling }
}
fn flight(s: const Service&, ticket: u64) -> i64 {
    if ticket == 0 { return -1; }
    for i in s.limits.inflight { if s.flights[i].ticket == ticket { return i; } } -1
}
fn start(s: Service&, id: Id, request: lab_net_http::Request, options: lab_net_http::Options = lab_net_http::Options {}) -> i32 {
    if !valid(s, id) { return STALE; }
    let c .= s.clients[id.slot];
    if c.ticket != 0 || c.ready { return BUSY; }
    let bytes = request.url.len + request.method.len + request.headers.len + request.body.len + request.ca_file.len;
    if request.url.len == 0 || request.method.len == 0 || bytes > s.limits.request_bytes || options.cancel.id != 0 ||
        options.timeout_ms < 1 || options.timeout_ms > 2147483647 || options.connect_timeout_ms < 1 || options.connect_timeout_ms > 2147483647 ||
        options.max_body_bytes < 0 || options.max_header_bytes < 0 { return INVALID; }
    if s.active == s.limits.inflight || s.next_ticket == 0xFFFFFFFFFFFFFFFF || c.serial == 0xFFFFFFFFFFFFFFFF { return LIMIT; }
    var index: i64 = -1;
    for i in s.limits.inflight { if s.flights[i].ticket == 0 { index = i; break; } }
    assert(index >= 0);
    let token = lab_io_cancel::create(); if token.id == 0 { return LIMIT; }
    s.next_ticket++; c.serial++; c.ticket = s.next_ticket; c.cancelling = false;
    s.flights[index] = Flight { c.ticket, id, token }; s.active++; s.counters.submitted++;
    var bounded = options; bounded.cancel = token;
    bounded.max_body_bytes = min(options.max_body_bytes, s.limits.body_bytes);
    bounded.max_header_bytes = min(options.max_header_bytes, s.limits.header_bytes);
    qput(Job { ticket: c.ticket, client: id, serial: c.serial, options: bounded,
        url: request.url, method: request.method, headers: request.headers, body: request.body, ca_file: request.ca_file }); OK
}
fn cancel(s: Service&, id: Id) -> i32 {
    if !valid(s, id) { return STALE; }
    let c .= s.clients[id.slot]; if c.ticket == 0 { return NOT_READY; }
    let index = flight(s, c.ticket); assert(index >= 0);
    assert(lab_io_cancel::request(s.flights[index].token)); c.cancelling = true; OK
}
fn get(s: Service&, id: Id, url: const u8[:], options: lab_net_http::Options = lab_net_http::Options {}) -> i32 {
    start(s, id, lab_net_http::Request { url: url }, options)
}
fn discard(s: Service&, id: Id) -> i32 {
    if !valid(s, id) { return STALE; }
    let c .= s.clients[id.slot]; if !c.ready { return NOT_READY; }
    let buffer = c.buffer;
    assert(lab_buffer_indexed::truncate(s.storage, buffer, 0) == lab_buffer_indexed::OK);
    s.clients[id.slot].ready = false; s.clients[id.slot].body = 0; s.clients[id.slot].headers = 0; s.clients[id.slot].error = 0; OK
}
fn close(s: Service&, id: Id) -> i32 {
    if !valid(s, id) { return STALE; }
    if s.clients[id.slot].ticket != 0 { cancel(s, id); }
    let buffer = s.clients[id.slot].buffer;
    assert(lab_buffer_indexed::close(s.storage, buffer) == lab_buffer_indexed::OK);
    s.clients[id.slot].open = false; s.clients[id.slot].ready = false;
    s.clients[id.slot].ticket = 0; s.clients[id.slot].cancelling = false; OK
}
// Internal queue receiver. Closing/reusing a client never drops its Flight:
// its token stays owned until the worker's completion is consumed here.
fn receive(s: Service&, result: const Completed&) {
    let index = flight(s, result.ticket);
    if index < 0 { s.counters.discarded++; return; }
    let owner = s.flights[index].client;
    if owner.slot != result.client.slot || owner.generation != result.client.generation { s.counters.discarded++; return; }
    lab_io_cancel::destroy(s.flights[index].token); s.flights[index].ticket = 0; s.active--; s.counters.completed++;
    if !valid(s, result.client) { s.counters.discarded++; return; }
    let c .= s.clients[result.client.slot];
    if c.ticket != result.ticket || c.serial != result.serial { s.counters.discarded++; return; }
    c.ticket = 0; c.ready = true; c.status = result.response.status;
    c.code = if c.cancelling { lab_net_http::CANCELLED } else { result.response.code };
    c.cancelling = false; c.body = 0; c.headers = 0; c.error = 0;
    if c.code == lab_net_http::CANCELLED { return; }
    let buffer = c.buffer;
    let total = result.response.body.len + result.response.headers.len + result.response.error.len;
    if total > s.storage.limits.bytes || lab_buffer_indexed::ensure(s.storage, buffer, total) != lab_buffer_indexed::OK {
        s.clients[result.client.slot].code = lab_net_http::LIMIT; s.counters.storage_refused++; return;
    }
    assert(lab_buffer_indexed::append(s.storage, buffer, result.response.body) == lab_buffer_indexed::OK);
    assert(lab_buffer_indexed::append(s.storage, buffer, result.response.headers) == lab_buffer_indexed::OK);
    assert(lab_buffer_indexed::append(s.storage, buffer, result.response.error) == lab_buffer_indexed::OK);
    s.clients[result.client.slot].body = result.response.body.len;
    s.clients[result.client.slot].headers = result.response.headers.len;
    s.clients[result.client.slot].error = result.response.error.len;
}
fn poll(s: Service&, maximum: i64 = 64) -> i64 {
    if s.code != OK || !s.running || maximum <= 0 { return 0; }
    var count: i64 = 0;
    while count < maximum { let result, available = qpoll<Completed>(); if !available { break; } receive(s, result); count++; }
    count
}
fn take(s: Service&, id: Id) -> Result, i32 {
    if !valid(s, id) { return Result { id, 0, lab_net_http::Response { code: 0, status: 0, body: [], headers: [], error: [] } }, STALE; }
    let c .= s.clients[id.slot];
    if !c.ready { return Result { id, c.serial, lab_net_http::Response { code: 0, status: 0, body: [], headers: [], error: [] } }, NOT_READY; }
    let body, bc = lab_buffer_indexed::read(s.storage, c.buffer, 0, c.body);
    let headers, hc = lab_buffer_indexed::read(s.storage, c.buffer, c.body, c.body + c.headers);
    let error, ec = lab_buffer_indexed::read(s.storage, c.buffer, c.body + c.headers, c.body + c.headers + c.error);
    assert(bc == 0 && hc == 0 && ec == 0);
    let result = Result { id, c.serial, lab_net_http::Response { c.code, c.status, body[..], headers[..], error[..] } };
    discard(s, id); return copy(result), OK;
}
fn stats(s: const Service&) -> Stats {
    var result = s.counters; result.inflight = s.active; result.workers = s.workers.len;
    for c in s.clients { if c.open { result.clients++; if c.ready { result.ready++; } } }
    let storage = lab_buffer_indexed::stats(s.storage);
    result.payload_bytes = storage.logical; result.arena_bytes = storage.high_water; result
}
// Cancels every outstanding Flight (including closed clients), queues one stop
// per worker, joins, then drains completions and releases all owned resources.
fn shutdown(s: Service&) {
    if !s.running { return; }
    for i in s.clients.len { if s.clients[i].open { close(s, Id { i, s.clients[i].generation }); } }
    for i in s.limits.inflight { if s.flights[i].ticket != 0 { lab_io_cancel::request(s.flights[i].token); } }
    for i in s.workers.len { qput(Job { stop: true }); }
    for worker_id in s.workers { thread_wait(worker_id); }
    poll(s); assert(s.active == 0); s.workers.resize(0); s.running = false;
}
