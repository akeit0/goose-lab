# Bounded streams and independent search clients

`lab.io.stream` provides host-owned routing and explicit page credit for a
fixed-size owned payload `P`. `lab.fs.search_clients` applies it to real searches
using `lab.fs.search::Batch`. Link `goose_lab_loop` for search, or
`goose_lab_cancel` for a producer that needs only the stream protocol.

This tests Goose's existing generic structs, isolated workers and typed queues.
No compiler/runtime or native API was added. The protocol keeps cancellation
ownership per request, rather than allocating a new native token per page.

## Queue ownership and ACK routing

There is one `Page<P>` queue per fixed payload type. Exactly one `Service<P>`
may receive it in a program. ID/receipt copies alias that Service's client;
they do not prove identity across owners or owner lifetimes. Do not copy the
Service, manipulate its internal queue types, or use host methods concurrently.
The ownership rule is explicit and is not enforced by the language/API.

Each of at most eight workers owns a different `Ack<P, LaneN>` queue. The host
uses the lane stored in a page receipt to return credit to its producer. These
are distinct instantiated Goose types, including when their byte layouts are
identical. A worker never polls another lane's ACK queue. A ticket and sequence
also reject late ACKs on the same lane. A different payload type uses different
page/ACK queues; the contract runs a synthetic producer and real search together
and holds the synthetic page while real ACK traffic progresses.

Goose `thread_fn` cannot be generic. The search adapter therefore has eight
concrete entry points that call one shared `run<LaneN>` implementation. This is
a bounded static routing method, not runtime-addressed queue instances. Extending
the lane count requires more entry points and routing cases.

One worker processes one request at a time. It sends a nonterminal page and
waits for its exact ACK before producing the next page. The host may poll every
client while retaining one client's page without ACK. Other active workers can
continue, but if all lanes are waiting, queued jobs wait too. Deadlines include
ACK waiting; this is bounded concurrency, not per-client scheduling fairness.

## Host API and lifecycle

The public search owner is `lab_fs_search_clients::Service`; its `.flow` field
is the shared `lab_io_stream::Service<lab_fs_search::Batch>` coordination owner.

| Operation | Contract |
| --- | --- |
| `search_clients::create(Limits)` | Validates 1..64 clients/inflight requests and 1..8 workers, then spawns the lanes. Check `service.flow.code`. |
| `stream::open(flow)` | Returns `Id, code`, reusing closed slots with a new generation. |
| `search_clients::start(service, id, root, query, Options)` | Copies bounded inputs and starts one request. Empty/oversized root/query and caller-owned cancel tokens are rejected before submission. Remaining engine validation errors arrive as terminal pages. |
| `stream::poll(flow, maximum=128)` | Nonblocking routing of at most that many pages across all clients. It does not grant credit. |
| `stream::info(flow, id)` | Reports serial, busy, ready, held and cancelling without polling. |
| `search_clients::take(service, id)` | Returns an owned `Page<Batch>, code`. A nonterminal page becomes held; take does not ACK. |
| `stream::ack(flow, page.receipt)` | Releases a taken page's credit. Wrong generation/ticket/serial/sequence/lane and replayed receipts cannot advance another request. |
| `stream::discard(flow, id)` | Drops a ready page and ACKs it if nonterminal; dropping a terminal sends no ACK. |
| `stream::cancel(flow, id)` | Signals the Flight, clears ready/held state and waits for terminal completion without requiring an ACK. |
| `stream::close(flow, id)` | Invalidates the client immediately and signals its job. Its Flight/token remains owned until terminal receipt. |
| `search_clients::shutdown(service)` | Cancels open/retired requests, sends one stop per worker, joins, drains page/ACK queues and releases every token. Repeated shutdown is harmless. |

Host codes are `OK=0`, `INVALID=1`, `LIMIT=2`, `STALE=3`, `BUSY=4`,
`NOT_READY=5`, `CLOSED=6`. Terminal page codes add `CANCELLED=7`, `TIMEOUT=8`,
`FAILED=9`. Engine detail remains in `page.data.result` using `lab.fs.search`
codes. The search `take` wrapper normalizes terminal `Batch.done` and cancellation/
timeout detail. The generic `stream::take` does not know domain-specific fields.

`take` success means a page was received, not that the search succeeded. A
terminal may contain final hits/issues and needs processing, but no ACK. New
requests are refused while a client is busy or its terminal mailbox is unread.
Consume or discard the terminal first. The adapter does not coalesce replacement
requests and does not automatically ACK during rendering/polling.

Cancellation received before terminal adoption wins over a successful terminal
already queued: its code becomes CANCELLED and payload becomes empty. Close/
reopen cannot adopt the retired generation's pages. Neither operation immediately
releases inflight quota; draining terminal completion does. This bounds repeated
retirement/reopening even when the host stops polling.

A timeout can arrive while a page is ready or held. The terminal replaces that
mailbox and invalidates its receipt. Previously exported owned pages remain
valid values, but their ACK is no longer accepted. Earlier matches are partial
results; dropped or held pages must not be described as a completed search.
The terminal accepts the current sequence or the immediately preceding ACKed
sequence, because a worker may observe Cancel before consuming an ACK the host
has already sent. Ordinary data pages still require the exact next sequence.

```goose
import std;
import os;
import lab.io.stream;
import lab.fs.search_clients;

fn main() {
    var service = lab_fs_search_clients::create();
    assert(service.flow.code == 0);
    let first, fc = lab_io_stream::open(service.flow);
    let second, sc = lab_io_stream::open(service.flow);
    assert(fc == 0 && sc == 0);
    assert(lab_fs_search_clients::start(service, first, ".", "TODO") == 0);
    assert(lab_fs_search_clients::start(service, second, ".", "FIXME") == 0);
    var finished: i64 = 0;
    while finished < 2 {
        lab_io_stream::poll(service.flow);
        for id in [first, second] {
            if !lab_io_stream::info(service.flow, id).ready { continue; }
            let page, code = lab_fs_search_clients::take(service, id);
            assert(code == 0);
            for hit in page.data.hits { print(hit.path, ":", hit.line); }
            if page.done { finished++; print("Search result: ", page.data.result); }
            else { assert(lab_io_stream::ack(service.flow, page.receipt) == 0); }
        }
        sleep_ms(1);
    }
    lab_fs_search_clients::shutdown(service);
}
```

## Bounds, native budgets and copy costs

The host reserves 64 client/mailbox records and 64 Flight records even if configured
for three clients. `P` must be fixed-size and owned; arrays of resizable payloads
need a different representation. For search, each Batch is bounded to 32 hits and
32 issues. Keeping fixed mailboxes makes the protocol easy to model but reserves
space for their full capacities.

On the validated Windows x64 toolchain, generated fixed representations are:

| Value | Bytes |
| --- | ---: |
| Search Service, including 64 mailboxes | 2859463 |
| Search Batch | 44539 |
| Search Page with receipt/status | 44592 |
| Synthetic producer Service | 14663 |

These `sizeof` measurements exclude worker data/native stacks, search text/tasks,
native handles/buffers, queued message allocation and owned exports. Queue
packing copies the fixed page representation, including reserved array entries.
This is not zero-copy transport or a total-memory/throughput comparison.

Without external queue manipulation, each Flight can have at most one unACKed
data page and one terminal, including cancellation/deadline completion. Host
ready/held mailboxes are one per client. Each lane can accumulate at most one
unconsumed ACK per request, and submitted-but-unconsumed Flights are bounded by
`inflight` (default 64). Workers discard residual ACKs between jobs and on exit;
the host drains all ACK lanes after joining. Poll/take alone do not produce credit.
Consumer-retained exports are outside these bounds.

The existing native layer has process-wide quotas of 64 cancel owners, 64 loops,
16 read handles and 16 directory listings. The adapter clamps a valid requested
read parallelism to `min(options.parallel, 16 / workers)`; with eight workers,
each search has at most two reads. This prevents this Service alone from asking
for 8×4 read slots. Other native consumers can still exhaust the shared registry;
their contention is reported as an engine failure, not hidden unlimited capacity.

Each active search keeps its context on the same worker throughout ACK waits.
It closes that context and every child before publishing terminal completion.
Cancellation tokens stay owned by the host until terminal receipt; native
resource closing stays on the worker that created the resources.

`stream::stats` counts clients, active Flights, ready/held mailboxes and attached
workers, plus submitted/completed/received/discarded/replaced/ACK events.
`completed` includes cancelled/retired jobs, and `discarded` counts unadopted
received messages. `replaced` records a terminal superseding a ready/held page.
These are protocol counts, not byte allocation measurements.

## Verification

[Controlled producers](../../tests/stream_contract.goose) cover three distinct
ACK lanes, a valid foreign ACK sent into the wrong lane, duplicate data/altered
serials, stale/replayed receipts, independent progress with two held consumers,
close/reopen, queued-success cancellation, 100 immediate ACK/Cancel races,
timeout of an unread page, client/inflight refusal, discard credit and shutdown
with eight stalled producers plus 56 queued jobs. The 3/16/64 producer traces
contain 332 pages, checked independently per client/sequence/payload.

[Real searches](../../tests/search_stream_contract.goose) exercise held pages,
independent roots, changed generations, non-ASCII queries/columns, CRLF input,
binary/encoding issues, limits, timeout, invalid options, missing roots and
cancel/shutdown during ACK waiting. The [Python fixture](../../tests/stream_fixture.py)
uses flat byte-string `find` and Unicode decoding to calculate the expected
path, offsets, line and column. It checks 92 traced streams and 8258 matches,
including 3/16/64 distinct roots. Cross-client corruption and truncated traces
must be rejected; cross-client completion order is unconstrained.

After each search Service shutdown, the contracts reacquire all 64 cancellation
slots, all 64 context slots, and all 16 read/listing slots, then close them. This
checks retained native handles and token leases, not arbitrary native mallocs.

```text
cmake --build build-core --config Release --target stream_contract search_stream_contract --parallel
ctest --test-dir build-core -C Release -R ^search_stream_contract$ --output-on-failure
python tools/stream_qualification.py --build build-core --output local/stream-run
```

The [qualification runner](../../tools/stream_qualification.py) currently supports
Windows x64/MSVC Release. It snapshots Goose library/stdlib sources, contract/
producer/fixture, native sources and built archives, compiler/source hashes,
link flags and Git state. It rebuilds both contracts at Goose `-O0/-O1/-O2`,
native C `-O2`, with three repeats per level, checks independent oracles and
measures generated fixed layouts. A fresh output directory is required;
failure preserves an incomplete manifest and available logs. One selected
upstream-tracking fork is sufficient for routine validation.

The existing `lab.fs.search_client` and UI integrations keep their single-client
contract. This library is a separately verified alternative. Runtime queue
instances, unbounded lane counts, fair multiplexing of thread-owned search
contexts, dynamic mailbox storage and UI adoption remain separate work.
