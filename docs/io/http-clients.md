# Independently lived HTTP clients

`import lab.net.http_clients;` supplies a caller-owned `Service` with up to 64
logical clients and 1..8 Goose workers. Link `goose_lab_http`. The lifecycle,
routing, mailbox and storage policy is Goose code; HTTP and cancellation use the
existing native libraries. No compiler/runtime change was required.

## One queue owner, independent client lifetimes

Goose selects a typed queue by its message type, not by a runtime instance.
Consequently, **exactly one Service may own this module's Job/Completed queues
in a program**. Pass that Service to every component that needs this protocol.
Creating two independent Services concurrently is unsupported: either poller
could consume the other's result. The API does not enforce this ownership rule.
Do not call its internal worker/queue receiver or manipulate its queue types.

Clients within the Service are independent. Each has a generation-checked ID,
request serial, cancellation intent and one result mailbox. Workers consume a
shared FIFO job queue; any worker can process any client. The receiver routes
owned results by ticket, client generation and request serial. Closing a client
does not stop a worker or drain another client's messages.

`Id` belongs to one Service lifetime. Copies alias that client; they are not
cross-Service identity proofs. Keep one owning Service variable, pass references,
and explicitly shut it down. Copying the Service does not create new workers or
transfer its native token ownership. All Service methods run on the host thread;
workers use only copied messages and thread-safe cancellation tokens.

```goose
import std;
import os;
import lab.net.http;
import lab.net.http_clients;

fn main() {
    assert(lab_net_http::init() == 0);
    var service = lab_net_http_clients::create();
    assert(service.code == lab_net_http_clients::OK);
    let first, fc = lab_net_http_clients::open(service);
    let second, sc = lab_net_http_clients::open(service);
    assert(fc == 0 && sc == 0);
    assert(lab_net_http_clients::get(service, first, "http://127.0.0.1:8000/first") == 0);
    assert(lab_net_http_clients::get(service, second, "http://127.0.0.1:8000/second") == 0);
    // Drive this at the host's existing event/frame boundary.
    while lab_net_http_clients::info(service, first).busy || lab_net_http_clients::info(service, second).busy {
        lab_net_http_clients::poll(service); sleep_ms(2);
    }
    let a, ac = lab_net_http_clients::take(service, first);
    let b, bc = lab_net_http_clients::take(service, second);
    assert(ac == 0 && bc == 0);
    // Each response owns its arrays; inspect response.code and HTTP status.
    print(a.response.status, " ", b.response.status);
    lab_net_http_clients::shutdown(service);
    lab_net_http::shutdown();
}
```

## API and adoption

| Operation | Behavior |
| --- | --- |
| `create(Limits)` | Validates limits and spawns workers. Caller initializes HTTP first. Check `Service.code`. |
| `open(service)` | Returns `Id, code`; reuses closed slots with a new generation. |
| `start(service, id, Request, Options)` / `get(service, id, url, Options)` | Copies borrowed input into an owned queued job. Refuses a busy client or an unread mailbox. |
| `info(service, id)` | Returns `code`, serial, busy, ready and cancelling; does not poll implicitly. |
| `cancel(service, id)` | Signals that client's current Flight. Repeated cancellation is allowed; idle returns `NOT_READY`. |
| `poll(service, maximum=64)` | Nonblocking receipt of at most `maximum` completed messages. Routes all clients, including hidden components. |
| `take(service, id)` | Returns an owned `Result, code`, clears that mailbox and releases its chunks. Does not poll implicitly. |
| `discard(service, id)` | Clears an unread mailbox without exporting its payload. |
| `close(service, id)` | Immediately invalidates the ID, releases mailbox chunks and signals its current job. Does not wait. |
| `stats(service)` | Reports live clients/Flights/mailboxes/workers, submission/completion/discard/refusal counters, stored payload and arena length. |
| `shutdown(service)` | Closes clients, cancels every Flight, sends one stop per worker, joins and drains all completions. Repeated shutdown is harmless. |

Service method codes are `OK=0`, `INVALID=1`, `LIMIT=2`, `STALE=3`, `BUSY=4`,
`NOT_READY=5`, `CLOSED=6`. A successful `take` means a result was obtained, not that
HTTP succeeded: separately inspect `result.response.code` and `.status` from
`lab.net.http`. Result also carries its client ID and serial.

Cancel intent received **before poll adopts the result** wins over a successful
response already queued by a worker. That completion becomes HTTP `CANCELLED`
with empty body/header/error arrays. Cancellation after adoption returns
`NOT_READY`; use `discard` to drop that ready result. A ready result blocks new
requests until taken/discarded. The library does not coalesce replacement jobs.

Close/reopen can reuse a client slot while its old worker is still running.
The old Flight retains its token until completion is consumed. Its result cannot
update the new generation. Closing therefore releases client/mailbox capacity
immediately, but **does not release inflight capacity** until poll/shutdown drains
the completion. This also prevents unbounded retire/reopen submission.

Shutdown waits for cooperative cancellation of active HTTP calls and consumes
already queued jobs before stop messages. Join before shutting down HTTP. A
worker pool gives concurrency, not a per-client progress guarantee: if every
worker is blocked, later jobs wait. Request/connect timeouts remain relevant.

## Bounds and representation costs

Default limits are 64 clients, four workers, 64 inflight jobs, 1 MiB response body,
64 KiB response headers, 1 MiB total request strings/body, and 4096 storage chunks
of 4096 bytes (16 MiB arena). Workers may be configured from 1 to 8. Other limits
may be reduced; requests are bounded before token creation/queue mutation.
Caller-provided response bounds are clamped to the Service bounds. A nonzero
caller cancellation token is rejected: the Service owns one token per Flight.
The existing native token registry also limits total live cancellation owners
across the process to 64. Token-capacity refusal preserves serial/busy state.

Each client has one indexed buffer containing body, headers and error bytes.
The receiver preflights the entire combined payload before appending any part.
If stored-response capacity is exhausted, that client receives HTTP `LIMIT`
with empty arrays; other ready responses remain intact. Taking/discarding/closing
releases chunks for subsequent responses. The arena retains its high-water
length until the Service value itself dies; this is not OS-memory release.

Queue payloads are outside that arena. There can be at most `inflight` submitted
but unconsumed completions, each bounded by the response limits and the existing
HTTP error-string bound. Queued requests are also bounded by inflight count and
`request_bytes`. Native HTTP buffers, worker stacks, queue packing/unpacking and
owned exports add storage/copies. `stats` does not measure these or process RSS.
Stored payload bytes and arena length must not be presented as total memory.

The Service reserves all 64 client/Flight entries regardless of configured
client count. The generated complete Service has a 156188-byte fixed representation
on the validated toolchain, including the indexed Store's 148861 bytes and tail
header. It excludes arena backing, worker storage, typed queues and native HTTP
allocations. The qualification runner measures `sizeof` to check this layout.
Returning owned results copies data; this correctness experiment does not claim
zero-copy transport or rank request throughput.

## Verification and reproduction

The [contract](../../tests/http_clients_contract.goose) and
[loopback fixture](../../tests/http_clients_fixture.py) exercise:

- Three simultaneous clients, server-confirmed blocked transfers, independent
  completion, cancel/close/reopen, queued-success cancellation and duplicate old
  results while a new request is active (same and different generations).
- Independent HTTP success/failure/timeout, 12000-byte binary POST input mutated
  after submission, multi-chunk output and owned exports surviving shutdown.
- Client/inflight/token/mailbox limits, whole-response storage refusal and reuse,
  response-body limits and refused requests preserving serial/busy state.
- Shutdown with one confirmed blocked transfer and 63 queued jobs, all retired
  generations, with zero remaining clients/Flights/mailboxes/workers/payload.
- Twelve lifecycle rounds at each of 3/16/64 clients: 996 requests. A separate
  Python oracle reconstructs generations, serials, cancellation and literal
  expected payloads, checking all 1002 output rows. A corrupted cross-client body
  must be rejected. Ordering of network completions is unconstrained.
- Full native registry reacquisition after every Service shutdown, proving all
  64 token slots are available again (including pinned native leases).

The fixture contacts only loopback. Server barriers establish active transfers;
tests do not infer entry from arbitrary sleep durations. The Python server uses
a backlog of 128 to accommodate the eight-worker Windows connection burst.

```text
cmake --build build-core --config Release --target http_clients_contract --parallel
ctest --test-dir build-core -C Release -R ^http_clients_contract$ --output-on-failure
python tools/http_clients_qualification.py --build build-core --output local/http-clients-run
```

The [qualification runner](../../tools/http_clients_qualification.py) currently
supports Windows x64/MSVC Release CMake builds. It snapshots library/stdlib/native
sources, contract, fixture, native archives and link inputs, records hashes and
Git state, rebuilds Goose `-O0/-O1/-O2` with native C `-O2`, runs three repetitions
per level and measures the fixed Service representation. It refuses an existing
output directory and preserves incomplete records on failure. Use one selected
upstream-tracking compatible fork; no equivalent second checkout run is needed.

This validates a shared-owner library for independently lived HTTP clients.
It does not supply runtime-addressed queue instances, multiple concurrent Service
owners, streaming result acknowledgements or Workbench/API Browser integration.
Search/Git worker adapters still follow their existing single-client contracts.
Those are separate follow-up experiments, not reasons to change Goose based on
this HTTP result alone.
