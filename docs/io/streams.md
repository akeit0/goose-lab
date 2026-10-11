# Bounded streams and independent search clients

`lab.io.stream` provides host-owned routing and explicit page credit for a
fixed-size owned export `P`, carried by bounded byte packets. `lab.fs.search_clients` applies it to real searches
using `lab.fs.search::Batch`. Link `goose_lab_loop` for search, or
`goose_lab_cancel` for a producer that needs only the stream protocol.

This tests Goose's existing generic structs, isolated workers and typed queues.
No compiler/runtime or native API was added. The protocol keeps cancellation
ownership per request, rather than allocating a new native token per page.

## Queue ownership and ACK routing

There is one `Packet<P>` queue per fixed export type. Exactly one `Service<P>`
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

The host reserves 64 small client/mailbox descriptors and 64 Flight records,
even if configured for three clients. A single `u8[>..<]` tail contains only
ready packets' encoded payloads, managed by the [slot arena](../buffer/slot-arena.md).
Poll adopts into a client slot; take copies
its bytes directly to an owned export and clears that slot. Held pages retain only
receipt/status metadata. Discard, cancel, close and terminal replacement also
clear their slot. Empty terminals do not retain stale arena offsets.

Removal leaves a reusable hole and trims unused tail bytes without moving
survivors. Adoption searches for a sufficient hole or tail space; only when those
cannot fit within `clients * 65536` does it compact live payloads. The 64-varied-page
take permutation now moves zero bytes, versus 285768 in the eager-compaction
baseline. A three-client pressure contract checks a 131072-byte compaction when
replacing a smaller consumed page with a maximum-size packet. Owned exports survive
both paths and shutdown. Gap/compaction scans trade bounded descriptor work and
retained holes for fewer survivor copies; arena length is distinct from live bytes.

Each packet payload is at most 65536 bytes, enforced at publication. The default
codec uses Goose `to_bytes([value])` and verified `from_bytes<P[>..]>`, preserving
the fixed representation, including unused array capacities. `P` must be fixed,
owned and supported by those builtins; create rejects an image beyond the bound.
Adapters use `publish_bytes<P>` and `take_packet<P>` for their own bounded codec.
Do not call the default `stream::take` on a domain-specific encoded packet.

Search uses [search_codec](../../lib/lab/fs/search_codec.goose): version byte,
little-endian fields, a 60-byte Batch header, counts up to 32 hits/issues,
16-bit string lengths, and only used path/preview bytes. Its largest encoded
Batch is 44540 bytes. Decode checks version, boolean, counts, string capacities,
truncation and trailing bytes; failure returns an empty Batch. It is a private
in-process format, not a persisted file format or a replacement for search APIs.
The worker encodes through a const Batch reference. The host's owned `Page<Batch>`
API still returns the fixed Batch representation, so its exports are not compact.

The slot-arena qualification measured these Windows x64 fixed representations:

| Value | Bytes |
| --- | ---: |
| Search Service metadata/header, excluding its byte tail | 10195 |
| Search Batch export | 44539 |
| Search Page export with receipt/status | 44592 |
| Synthetic producer Service metadata/header | 10195 |
| Standalone slot arena Store, excluding its byte tail | 1148 |
| Search Packet header including the runtime tail header | 69 |
| Queue image prefix, before payload bytes | 61 |

The eager-compaction Service header was 10047 bytes; slot storage and counters
add 148 bytes. The original fixed-mailbox Service reserved 2859463 bytes. The current owner starts
with zero retained payload bytes; search live ready payloads are bounded by
`clients * 44540`, its arena including holes by `clients * 65536`, and held payloads
live in caller-owned exports. Queue images
are `61 + encoded.len` bytes, versus the old fixed 44592 bytes per search Page.
A maximum-capacity Batch produces a 44601-byte image, nine bytes larger than the
old representation; reduction depends on occupancy and actual string lengths.

These measurements exclude allocator/node overhead, worker data/native stacks,
search text/tasks, native handles/buffers, spare runtime stack capacity and owned
exports. Encoding, queue packing, receipt routing, decoding and arena compaction
still copy data. This is not zero-copy transport or a total-memory/throughput
comparison. Arena length returning to zero does not prove process RSS decreases.

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
Byte counters add received queue-image bytes (including stale packets), current/
peak live payload, exported encoded bytes and bytes moved by compaction (the
existing `shifted_bytes` field). Slot-arena counters add current/peak arena bytes,
bytes written into retained gaps, compaction calls and gap/compaction descriptor visits.
They exclude encoder/decoder temporaries, fixed owned exports and allocator/RSS
measurements. The Python oracle calculates exact 3/16/64 search queue bytes from
flat-file paths/previews plus message headers, and rejects a corrupted counter.

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
path, offsets, line, column, preview and issue detail. It checks 92 traced streams and 8258 matches,
including 3/16/64 distinct roots. Codec checks round-trip the maximum Batch,
reject every truncated prefix of a Unicode example and malformed headers/lengths,
and compare its exact encoded bytes with independent Python `struct.pack`.
Cross-client corruption and truncated traces
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
link flags and Git state. It rebuilds the stream, search and slot-arena contracts at Goose `-O0/-O1/-O2`,
native C `-O2`, with three repeats per level, checks independent oracles and
measures generated fixed layouts. A fresh output directory is required;
failure preserves an incomplete manifest and available logs. One selected
upstream-tracking fork is sufficient for routine validation.

The original fixed-mailbox baseline qualification at lab `30f69f18373081e14277ade581c8e113890a957a`
and fork `c2ecb4421facdc6476214606b67488df93eaa033` passed all nine paired runs
(`-O0/-O1/-O2`, three repeats each), or 18 contract processes. Independent
oracles checked 2988 producer pages, 828 real streams and 74322 flat-file
matches; the lifecycle contracts completed 900 immediate ACK/Cancel races.
All runs also passed bounds, typed-queue isolation and native registry
reacquisition. Compiler, generated C/binaries, archives and 142 snapshot files
were hash-checked; both source checkouts were clean. That baseline measured
2859463 fixed search Service bytes and 14663 fixed synthetic Service bytes. The main Windows/MSVC Release build passed all 27 CTest checks in
90.26 seconds. Raw records and snapshots remain under ignored
`local/references/stream/qualification-run/`; the commands above reproduce the
public contract without those local records.

The compact qualification at clean lab
`5ce2a9b10aa3eda6a171f8defe17decab6f46676` and the same clean fork passed
all nine paired runs (18 processes), again checking 2988 producer pages,
828 real streams, 74322 matches and 900 ACK/Cancel races. It also checked
every match preview, issue detail, codec's independent golden image, maximum
Batch round-trip, malformed/truncated decode rejection and the 64-payload
compaction model. Compiler, generated C/binaries, native archives and 143
snapshot files were hash-checked. The layout probe confirmed the 61-byte queue
prefix and the current fixed headers listed above.

For the complete 3/16/64-search traces, all nine runs measured these queue
image sizes; scheduling changes the retained/shifted byte peaks:

| Clients | Messages | Fixed Page equivalent bytes | Compact queue bytes | Peak retained bytes | Shifted bytes |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | 15 | 668880 | 22098 | 2300..6900 | 0..6980 |
| 16 | 80 | 3567360 | 119008 | 11500..16484 | 49810..118132 |
| 64 | 320 | 14269440 | 481792 | 16548 | 270410..370544 |

The fixed equivalent is the same message count times the original Page's
44592-byte representation, not a second toolchain run or a throughput estimate.
For the 64-client sparse fixture, queue images decrease by 96.6%; encoded exports
still copy 462272 bytes and compaction adds the shifted bytes above. Maximum-size
packets have the overhead described earlier. The main Windows/MSVC Release
build passed all 27 CTest checks in 91.64 seconds. Raw records and snapshots stay
in ignored `local/references/stream/compact-qualification-run/`; reproduction
uses the same public commands above.

The slot-arena qualification at clean lab
`aeaefb23ca5f68433fc90f12f1e90bf51ae0a4d5` and the same clean fork passed
all nine groups of three contracts (27 processes): Goose O0/O1/O2, three repeats
each. Independent models checked 243000 variable-value operations, 2430 flat-byte
checkpoints and 59013 quota refusals, alongside the same 2988 producer trace pages,
828 search streams, 74322 matches and 900 ACK/Cancel races. All runs passed native
registry reacquisition, maximum arena reuse, owned exports and pressure/hole reuse.
Compiler, nine generated C/binary pairs, native archives and 147 source snapshots
were hash-checked; fixed layouts match the table above.

| Clients | Queue bytes | Peak live bytes | Peak arena bytes | Moved bytes | Gap/compaction descriptor visits |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | 22098 | 4600..6900 | 4600..6900 | 0 | 48..63 |
| 16 | 119008 | 14056..16484 | 14056..16484 | 0 | 2512..3136 |
| 64 | 481792 | 16100..16548 | 16100..16548 | 0 | 37568..47104 |

The queue codec and exact queue-byte totals remain the same. These complete-search
traces require neither retained-gap writes nor pressure compaction; they do not
show a hole-reuse workload. The controlled 64-varied-page permutation moves zero
bytes instead of 285768. The three-client pressure case moves 131072 bytes once,
then holds both outer pages while middle-page updates reuse 98304 bytes without
additional moves. At its sparse midpoint the arena is 196608 bytes for 163840 live
bytes: the retained 32768-byte hole is an explicit tradeoff. The 64-search trace
replaces the earlier 270410..370544 moved bytes with descriptor visits; timing is
not qualified as a throughput improvement. Clear scans and implicit runtime copies
are outside those visit/move counters.

During integration the main Windows/MSVC Release suite passed all 28 CTest checks
in 90.67 seconds. The final stream/slot-arena focused rerun passed both checks in
10.85 seconds after adding the held-neighbor reuse case. Raw records remain in
ignored `local/references/stream/slot-arena-reuse-run/`; the runner above reproduces
the current contracts using a new output directory.

The existing `lab.fs.search_client` and UI integrations keep their single-client
contract. This library is a separately verified alternative. Runtime queue
instances, unbounded lane counts, fair multiplexing of thread-owned search
contexts, alternative arena reuse strategies and UI adoption remain separate work.
