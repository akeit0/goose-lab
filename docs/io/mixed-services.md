# Composing HTTP and search owners

The [composition contract](../../tests/mixed_services_contract.goose) keeps one
HTTP Service and one search Service in separate local variables. Each owns its
resizable storage, workers and protocol queues; helper functions borrow the owner
needed for that operation. No combined resizable App, native dispatcher or
compiler/runtime change is needed.

This tests whether existing Goose ownership and typed queues compose when the
services also share process-wide native resources. It does not create multiple
concurrent owners of the **same** protocol. HTTP still has one Job/Completed owner,
and search has one Job/Packet/ACK owner.

## Lifetimes and shared capacity

The contract repeats three scenarios three times in one process, recreating both
Services between scenarios:

| Scenario | What must remain independent |
| --- | --- |
| Close/reopen HTTP and then shut it down while search holds an unACKed page | The search receipt and owned hits survive, ACK still works, and every remaining result arrives |
| Close/reopen search and then shut it down while HTTP is server-confirmed blocked | Old search IDs/receipts are rejected; HTTP remains busy and later completes normally |
| Exhaust the shared cancel-token registry with both services active | Refusal preserves serial/busy/submission state; freeing one slot admits HTTP, then polling its completion frees the slot for search |

The native cancel registry has 64 slots **per process**, not per Service. Each
submitted Flight keeps its token until the host drains its terminal completion,
even if the native operation has finished. A queued completion is therefore still
part of the capacity budget. Refusal is recoverable: poll completed work and retry
after capacity becomes available. Per-Service client/inflight limits cannot
guarantee admission in the presence of other owners.

Partial shutdown leaves exactly 63 token slots available while the surviving
Service holds one Flight. After both owners shut down, all 64 slots can be
reacquired. Final checks also reacquire all 64 native loops, 16 reads and 16
directory listings while earlier handles remain owned. Shutdown releases those
registries without cancelling the other protocol's active operation.

Search credit remains explicit. Taking a page does not ACK it, so a producer can
stay blocked while HTTP progresses. Cancellation/shutdown must release that wait;
joining a worker must not depend on the consumer ACKing its held page.

## Verification and reproduction

The [Python fixture](../../tests/mixed_services_fixture.py) reuses the HTTP test
server's ready/release barriers and writes two independent flat files. It checks
byte offsets, line/column, previews, client generation/serial, complete hit sets,
HTTP bodies and quota/cleanup accounting. Cross-generation, cross-response,
capacity-accounting and incomplete-trace corruptions must be rejected.
Only loopback HTTP and temporary local files are used.

```text
cmake --build build-core --config Release --target mixed_services_contract --parallel
ctest --test-dir build-core -C Release -R ^mixed_services_contract$ --output-on-failure
python tools/http_clients_qualification.py --build build-core --contract mixed_services --output local/mixed-services-run
```

The existing qualification runner snapshots sources, the companion HTTP fixture,
stdlib, native archives and link definitions. It records Git state and hashes,
builds the contract at Goose O0/O1/O2 with native C O2, and runs three repetitions
per level using one selected compatible compiler. An existing output directory
is refused; incomplete records remain available on failure.

The Windows/MSVC snapshot qualification on 2026-10-11 passed all nine runs:
7776 independently checked search hits, 135 HTTP results, 81 lifecycle/quota cases
and 81 token-quota refusals across 8172 trace rows. The compiler checkout was
`71e848d732362a47ee7fe000a3e1601d0196259a`; the record includes the new working-tree
sources and their hashes. Core CTest passed all 18 checks with manual tools enabled.
Raw records remain under ignored `local/references/mixed-services/development-run/`.

This establishes protocol isolation, owned-result lifetimes, bounded refusal and
recovery for this workload. It does not establish fair admission, long-session
RSS behavior, UI adoption or dynamic queue instances. The runner's 156188-byte
layout measurement is the HTTP Service alone, excluding the search owner,
payload backing, queues, worker stacks and native allocations.

## Fair host admission and repeated reuse

[`lab.io.admission`](../../lib/lab/io/admission.goose) adds an explicit host-owned
Queue of bounded demand descriptors. It has up to eight domains and 128 pending
entries, with round-robin domain selection and FIFO tickets within each domain.
The caller keeps request payloads in its own bounded store and uses `Demand.key`
to find them. The queue owns no worker, native token or protocol Service, and
needs no native target. Its fixed records do not combine resizable Service tails.
The representation reserves all 128 descriptors even with a smaller pending
limit. Enqueue/removal scan at most 128 records; selection scans at most eight
domains times 128 records. This avoids per-demand payload allocation and shifting
survivors, with a deliberate fixed-table cost appropriate to a small bounded set.

Use the operations in this order:

1. `enqueue(queue, domain, key)` retains demand; a duplicate pending domain/key
   returns BUSY, and a full queue returns LIMIT without consuming a ticket.
2. Poll all protocol owners, then `peek(queue, eligible_mask)` selects demand.
   Exclude domains whose own Service cannot currently start work.
3. Submit through the selected Service. On success, `accept(queue, ticket)`
   removes demand and gives the next domain its turn. On shared native LIMIT,
   leave demand and cursor unchanged, stop admission, poll owners and retry.
4. `cancel(queue, ticket)` removes pending demand without changing the turn.
   Cancelling a Flight already admitted is still the protocol Service's job.

Fairness is an admission-order property for eligible domains that follow this
policy. A continually eligible domain with demand gets a turn within at most
`limits.domains` successful admissions. A held search page can still
occupy the only native slot indefinitely; the queue cannot grant capacity,
complete work, impose a deadline or make other native token users cooperate.
Tickets are scoped to one Queue lifetime; keep the owner and cancel obsolete
demand when its external request identity changes.

The [admission contract](../../tests/admission_services_contract.goose) and
[independent fixture](../../tests/admission_services_fixture.py) check 1800
operations against a Python list model across 2/3/8 domains, including eligibility
masks, FIFO order, cancellation, stale tickets, duplicate keys and bounded refusal.
The real workload keeps the same HTTP/search owners alive across reuse cycles.
Four HTTP requests compete with one search for a single free native token slot;
search gets its turn before the HTTP backlog drains. Every cycle also exercises
full-quota refusal, variable HTTP payloads, held-page cancellation, client slot
generation changes, and full native token/loop/read/listing reacquisition.
An exported HTTP body remains owned throughout all cycles.

CTest uses 16 cycles. For longer reuse observations with source/archive snapshots:

```text
cmake --build build-core --config Release --target admission_services_contract --parallel
ctest --test-dir build-core -C Release -R ^admission_services_contract$ --output-on-failure
python tools/http_clients_qualification.py --build build-core --contract admission_services --cycles 128 --repeats 1 --output local/admission-services-run
python tools/http_clients_qualification.py --build build-core --contract admission_services --cycles 512 --levels 1 --repeats 1 --output local/admission-services-long-run
```

The fixture samples the child process's RSS/private bytes through the existing
OS-memory reader every eight completed cycles and at the final cycle. The sample
is taken while a synchronous loopback checkpoint request is active and both
Services have drained their Flights/mailboxes. Samples include live workers,
retained allocations, runtime and native transport state; they are observations,
not a test that the OS returns memory. The record also retains each cycle's arena
lengths and high-water value, checked separately from total process memory.

The Windows/MSVC qualification on 2026-10-11 passed:

| Goose optimization | Cycles in one process | Successful admissions | Independently checked search hits | Elapsed seconds |
| --- | ---: | ---: | ---: | ---: |
| O0 | 128 | 640 | 10240 | 52.67 |
| O1 | 128 | 640 | 10240 | 52.86 |
| O2 | 128 | 640 | 10240 | 52.27 |
| O1 extended | 512 | 2560 | 40960 | 209.41 |

Across these four processes, 896 reuse cycles checked 4480 admissions, 3584 HTTP
results, 71680 flat-model hits and 1792 quota refusals. All native registries were
fully reacquired 900 times, including final shutdown. Queue traces checked 7200
list-model operations. Core contracts and rebuilt experiment smoke checks all
passed, covering 19 CTest cases; the new target also built in the GUI configuration.

The 512-cycle process took 64 memory checkpoints. RSS ranged from 18964480 to
20430848 bytes, and private bytes from 47149056 to 48582656. Private-byte peaks
did not exceed 48582656 in any of the last four 64-cycle windows; the final sample was
48562176. This is a bounded, fluctuating observation over about 3.5 minutes, not
proof of leak-free indefinite operation. HTTP retained arena length never
exceeded 12288 bytes, and search arena high-water stayed at 2108 bytes. Logical
mailboxes/Flights were empty before each checkpoint; worker/runtime/native
allocation retention remains separate from those counters.

Both qualifications used compiler `71e848d732362a47ee7fe000a3e1601d0196259a`.
Immutable source/archive snapshots and complete records remain under ignored
`local/references/admission-services/development-run/` and `extended-run/`.
Records include the new working-tree sources and their hashes. A selected-level
O2 run of the existing HTTP contract also passed its 996-request oracle, checking
that the runner still supports the original contract without an O1 layout input.
