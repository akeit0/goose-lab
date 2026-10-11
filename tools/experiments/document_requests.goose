// GUI-free application reducer. Resource owners stay in separate caller locals.
namespace lab_experiment_document_requests;
import std;
import lab.document.store;
import lab.io.admission;
import lab.io.stream;
import lab.fs.search;
import lab.fs.search_clients;
import lab.net.http;
import lab.net.http_clients;

struct Scope { document: lab_document_store::Id = lab_document_store::Id {}, revision: u64 = 0, key: u64 = 0 }
struct Binding {
    open: bool = false, document: lab_document_store::Id = lab_document_store::Id {},
    http: lab_net_http_clients::Id = lab_net_http_clients::Id {}, search: lab_io_stream::Id = lab_io_stream::Id {},
    latest: u64[2] = [0; 2], http_done: bool = false, http_code: i32 = 0, http_status: i64 = 0,
    body: u8[..512] = [], hits: i64 = 0, search_next: u64 = 1, search_done: bool = false, search_code: i32 = 0,
}
struct Pending { ticket: u64 = 0, scope: Scope = Scope {}, first: u8[..512] = [], second: u8[..512] = [] }
struct Flight {
    active: bool = false, scope: Scope = Scope {}, serial: u64 = 0,
    http: lab_net_http_clients::Id = lab_net_http_clients::Id {}, search: lab_io_stream::Id = lab_io_stream::Id {},
    held: bool = false, receipt: lab_io_stream::Receipt = lab_io_stream::Receipt {},
}
struct State {
    bindings: Binding[3] = [Binding {}; 3], pending: Pending[6] = [Pending {}; 6], flights: Flight[6] = [Flight {}; 6],
    queue: lab_io_admission::Queue = lab_io_admission::Queue {}, next_key: u64 = 0,
    admitted: i64 = 0, finished: i64 = 0, superseded: i64 = 0, stale_pending: i64 = 0,
}
struct HttpCompletion { scope: Scope = Scope {}, serial: u64 = 0, code: i32 = 0, status: i64 = 0, body: u8[..512] = [] }
struct SearchCompletion { scope: Scope = Scope {}, page: lab_io_stream::Page<lab_fs_search::Batch> = lab_io_stream::Page<lab_fs_search::Batch> { receipt: lab_io_stream::Receipt {} } }
fn create() -> State {
    // Keep this reducer while its documents stay open. Recreate only after all
    // bindings close and Flights drain; request keys belong to this lifetime.
    // Six logical lanes plus one provisional replacement. Enqueue the new
    // demand before retiring the old one, preserving it if enqueue refuses.
    State { queue: lab_io_admission::create(lab_io_admission::Limits { domains: 6, pending: 7 }) }
}
fn bound(s: const State&, docs: const lab_document_store::Store&, id: lab_document_store::Id) -> bool {
    lab_document_store::valid(docs, id) && id.slot < 3 && s.bindings[id.slot].open &&
    s.bindings[id.slot].document.generation == id.generation
}
fn attach(s: State&, docs: const lab_document_store::Store&, id: lab_document_store::Id,
          http: lab_net_http_clients::Id, search: lab_io_stream::Id) {
    assert(lab_document_store::valid(docs, id) && id.slot < 3 && !s.bindings[id.slot].open);
    s.bindings[id.slot] = Binding { open: true, document: id, http: http, search: search };
}
fn current(s: const State&, docs: const lab_document_store::Store&, scope: Scope, kind: i64) -> bool {
    bound(s, docs, scope.document) && lab_document_store::revision(docs, scope.document) == scope.revision &&
    s.bindings[scope.document.slot].latest[kind] == scope.key && scope.key != 0
}
fn reset_result(s: State&, slot: i64, kind: i64) {
    if kind == 0 { s.bindings[slot].http_done = false; s.bindings[slot].body.resize(0); s.bindings[slot].http_code = 0; s.bindings[slot].http_status = 0; }
    else { s.bindings[slot].hits = 0; s.bindings[slot].search_next = 1; s.bindings[slot].search_done = false; s.bindings[slot].search_code = 0; }
}
fn cancel_flight(s: State&, lane: i64, http: lab_net_http_clients::Service&, search: lab_fs_search_clients::Service&) {
    let f .= s.flights[lane]; if !f.active { return; }
    let code = if lane % 2 == 0 { lab_net_http_clients::cancel(http, f.http) } else { lab_io_stream::cancel(search.flow, f.search) };
    assert(code == 0 || code == lab_io_stream::NOT_READY); f.held = false;
    // Keep the correlation record until terminal receive. Cancellation does not
    // finish the Flight, release its token, or make its logical lane available.
}
fn request(s: State&, docs: const lab_document_store::Store&, id: lab_document_store::Id, kind: i64,
           first: const u8[:], second: const u8[:], http: lab_net_http_clients::Service&, search: lab_fs_search_clients::Service&) -> u64, i32 {
    if kind < 0 || kind > 1 || !bound(s, docs, id) { return 0, lab_io_admission::STALE; }
    if first.len == 0 || first.len > 512 || second.len > 512 || (kind == 1 && second.len == 0) || (kind == 0 && second.len != 0) {
        return 0, lab_io_admission::INVALID;
    }
    if s.next_key == 0xFFFFFFFFFFFFFFFF { return 0, lab_io_admission::LIMIT; }
    let key = s.next_key + 1; let lane = id.slot * 2 + kind;
    let demand, code = lab_io_admission::enqueue(s.queue, lane, key); if code != 0 { return 0, code; }
    if s.pending[lane].ticket != 0 { assert(lab_io_admission::cancel(s.queue, s.pending[lane].ticket) == 0); s.superseded++; }
    s.next_key = key; s.bindings[id.slot].latest[kind] = key; reset_result(s, id.slot, kind);
    s.pending[lane] = Pending { demand.ticket, Scope { id, lab_document_store::revision(docs, id), key }, first, second };
    cancel_flight(s, lane, http, search); return key, 0;
}
fn invalidate(s: State&, id: lab_document_store::Id, http: lab_net_http_clients::Service&, search: lab_fs_search_clients::Service&) {
    for kind in 2 {
        let lane = id.slot * 2 + kind;
        if s.pending[lane].ticket != 0 { assert(lab_io_admission::cancel(s.queue, s.pending[lane].ticket) == 0); s.pending[lane] = Pending {}; }
        s.bindings[id.slot].latest[kind] = 0; reset_result(s, id.slot, kind); cancel_flight(s, lane, http, search);
    }
}
fn close(s: State&, docs: lab_document_store::Store&, id: lab_document_store::Id,
         http: lab_net_http_clients::Service&, search: lab_fs_search_clients::Service&) {
    assert(bound(s, docs, id)); invalidate(s, id, http, search);
    assert(lab_document_store::close(docs, id) == 0); s.bindings[id.slot].open = false;
}
fn dispatch(s: State&, docs: const lab_document_store::Store&, http: lab_net_http_clients::Service&,
            search: lab_fs_search_clients::Service&, maximum: i64 = 6) -> i64 {
    var count: i64 = 0;
    while count < maximum {
        var eligible: u64 = 0;
        for lane in 6 {
            let p = s.pending[lane]; if p.ticket == 0 { continue; }
            if !current(s, docs, p.scope, lane % 2) {
                assert(lab_io_admission::cancel(s.queue, p.ticket) == 0); s.pending[lane] = Pending {}; s.stale_pending++; continue;
            }
            if !s.flights[lane].active { eligible |= (1 as u64) << lane; }
        }
        let d, dc = lab_io_admission::peek(s.queue, eligible); if dc == lab_io_admission::EMPTY { break; } assert(dc == 0);
        let lane = d.domain; let p = s.pending[lane]; let b = s.bindings[p.scope.document.slot];
        assert(p.scope.key == d.key && p.ticket == d.ticket);
        let code = if lane % 2 == 0 { lab_net_http_clients::get(http, b.http, p.first) }
                   else { lab_fs_search_clients::start(search, b.search, p.first, p.second) };
        if code == lab_io_admission::LIMIT { break; } assert(code == 0);
        assert(lab_io_admission::accept(s.queue, d.ticket, eligible) == 0);
        let serial = if lane % 2 == 0 { lab_net_http_clients::info(http, b.http).serial } else { lab_io_stream::info(search.flow, b.search).serial };
        s.flights[lane] = Flight { active: true, scope: p.scope, serial: serial, http: b.http, search: b.search };
        s.pending[lane] = Pending {}; count++; s.admitted++;
    }
    count
}
fn receive_http(s: State&, slot: i64, http: lab_net_http_clients::Service&) -> HttpCompletion, bool {
    let lane = slot * 2; let f = s.flights[lane];
    if !f.active || !lab_net_http_clients::info(http, f.http).ready { return HttpCompletion {}, false; }
    let result, code = lab_net_http_clients::take(http, f.http); assert(code == 0 && result.serial == f.serial);
    assert(result.client.slot == f.http.slot && result.client.generation == f.http.generation && result.response.body.len <= 512);
    s.flights[lane] = Flight {}; s.finished++;
    return HttpCompletion { f.scope, result.serial, result.response.code, result.response.status, result.response.body }, true;
}
fn apply_http(s: State&, docs: const lab_document_store::Store&, value: const HttpCompletion&) -> bool {
    if !current(s, docs, value.scope, 0) || s.bindings[value.scope.document.slot].http_done { return false; }
    let b .= s.bindings[value.scope.document.slot]; b.body = value.body; b.http_code = value.code;
    b.http_status = value.status; b.http_done = true; true
}
fn receive_search(s: State&, slot: i64, search: lab_fs_search_clients::Service&) -> SearchCompletion, bool {
    let lane = slot * 2 + 1; let f = s.flights[lane];
    if !f.active || !lab_io_stream::info(search.flow, f.search).ready { return SearchCompletion {}, false; }
    let page, code = lab_fs_search_clients::take(search, f.search); assert(code == 0 && page.receipt.serial == f.serial);
    assert(page.receipt.client.slot == f.search.slot && page.receipt.client.generation == f.search.generation);
    if page.done { s.flights[lane] = Flight {}; s.finished++; }
    else { s.flights[lane].held = true; s.flights[lane].receipt = page.receipt; }
    return SearchCompletion { f.scope, page }, true;
}
fn apply_search(s: State&, docs: const lab_document_store::Store&, value: const SearchCompletion&) -> bool {
    if !current(s, docs, value.scope, 1) { return false; }
    let b .= s.bindings[value.scope.document.slot]; let p .= value.page;
    if b.search_done { return false; }
    if p.done && p.code != 0 {
        if p.receipt.sequence != b.search_next && p.receipt.sequence + 1 != b.search_next { return false; }
        b.search_done = true; b.search_code = p.code; return true;
    }
    if p.receipt.sequence != b.search_next { return false; }
    b.hits += p.data.hits.len; b.search_next++;
    if p.done { b.search_done = true; b.search_code = p.code; } true
}
fn ack(s: State&, docs: const lab_document_store::Store&, search: lab_fs_search_clients::Service&, value: const SearchCompletion&) -> i32 {
    if !current(s, docs, value.scope, 1) { return lab_io_stream::STALE; }
    let lane = value.scope.document.slot * 2 + 1; let f .= s.flights[lane];
    if !f.active || !f.held || f.scope.key != value.scope.key { return lab_io_stream::STALE; }
    let code = lab_io_stream::ack(search.flow, value.page.receipt); if code == 0 { f.held = false; } code
}
