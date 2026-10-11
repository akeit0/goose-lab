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
