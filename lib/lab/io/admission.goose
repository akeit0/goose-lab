// Host-owned bounded demand; round-robin domains, FIFO within each domain.
namespace lab_io_admission;
import std;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2;
let STALE: i32 = 3; let BUSY: i32 = 4; let EMPTY: i32 = 5;
struct Limits { domains: i64 = 2, pending: i64 = 128 }
// key belongs to the caller's bounded request store. This queue owns no payload,
// worker, token or Service. Tickets are valid only within this Queue's lifetime.
struct Demand { ticket: u64 = 0, domain: i64 = -1, key: u64 = 0 }
struct Stats { pending: i64 = 0, queued: i64 = 0, accepted: i64 = 0, cancelled: i64 = 0 }
struct Queue { code: i32 = OK, limits: Limits = Limits {}, cursor: i64 = 0,
    next_ticket: u64 = 0, entries: Demand[128] = [Demand {}; 128], counters: Stats = Stats {} }
fn create(limits: Limits = Limits {}) -> Queue {
    if limits.domains < 1 || limits.domains > 8 || limits.pending < 1 || limits.pending > 128 { return Queue { code: INVALID }; }
    Queue { limits: limits }
}
fn enqueue(s: Queue&, domain: i64, key: u64) -> Demand, i32 {
    if s.code != OK || domain < 0 || domain >= s.limits.domains { return Demand {}, INVALID; }
    var slot: i64 = -1;
    for i in s.limits.pending {
        let d = s.entries[i];
        if d.ticket != 0 && d.domain == domain && d.key == key { return Demand {}, BUSY; }
        if d.ticket == 0 && slot < 0 { slot = i; }
    }
    if slot < 0 || s.next_ticket == 0xFFFFFFFFFFFFFFFF { return Demand {}, LIMIT; }
    s.next_ticket++; let d = Demand { s.next_ticket, domain, key }; s.entries[slot] = d;
    s.counters.pending++; s.counters.queued++; return d, OK;
}
// No mutation on selection or shared-capacity refusal. Pass an eligible mask to
// skip domains blocked on their own service limits. The caller polls all owners
// and stops this admission pass on a shared native LIMIT.
fn peek(s: const Queue&, eligible: u64 = 255) -> Demand, i32 {
    if s.code != OK { return Demand {}, INVALID; }
    for step in s.limits.domains {
        let domain = (s.cursor + step) % s.limits.domains;
        if (eligible & ((1 as u64) << domain)) == 0 { continue; }
        var first = Demand {};
        for i in s.limits.pending {
            let d = s.entries[i];
            if d.ticket != 0 && d.domain == domain && (first.ticket == 0 || d.ticket < first.ticket) { first = d; }
        }
        if first.ticket != 0 { return first, OK; }
    }
    return Demand {}, EMPTY;
}
fn find(s: const Queue&, ticket: u64) -> i64 {
    if ticket == 0 { return -1; }
    for i in s.limits.pending { if s.entries[i].ticket == ticket { return i; } } -1
}
// Call only after the selected request was admitted by its protocol Service.
// Removal does not represent native completion or grant a native credit.
fn accept(s: Queue&, ticket: u64) -> i32 {
    if s.code != OK { return INVALID; }
    let slot = find(s, ticket); if slot < 0 { return STALE; }
    s.cursor = (s.entries[slot].domain + 1) % s.limits.domains;
    s.entries[slot] = Demand {}; s.counters.pending--; s.counters.accepted++; OK
}
fn cancel(s: Queue&, ticket: u64) -> i32 {
    if s.code != OK { return INVALID; }
    let slot = find(s, ticket); if slot < 0 { return STALE; }
    s.entries[slot] = Demand {}; s.counters.pending--; s.counters.cancelled++; OK
}
fn stats(s: const Queue&) -> Stats { s.counters }
