# Document-scoped requests and result application

The [GUI-free application reducer](../../tools/experiments/document_requests.goose)
composes the existing document Store, HTTP clients, search clients and admission
Queue. Its caller keeps the three resizable owners in separate local variables
and passes borrowed references to each operation. Fixed records hold application
identity, bounded pending payloads, active correlations and derived result panes.
No compiler, native dispatcher or library change is required.

This application experiment lives under `tools/experiments`. It checks whether
existing Goose structures support the complete
pending → running → owned completion → application lifecycle for three documents.
Each document has one HTTP lane and one search lane, with at most one pending
replacement and one active Flight per lane. Request strings and HTTP bodies are
bounded to 512 bytes; each protocol has three clients and two workers.

## Separate identity from resource retirement

| Identity | Check and purpose |
| --- | --- |
| Document slot + generation | Reject exports from a document closed and reopened in the same slot |
| Document revision | Reject pending work or results based on text that has since changed |
| Application request key | Keep only the latest desired request for that document/protocol |
| Protocol client + serial | Correlate native completion with the submitted Flight before exporting it |
| Search page sequence and receipt | Apply each page once, in order, and ACK the correct producer |

Completion reception and application are separate operations. Reception drains
the Service and returns an owned value; application checks document generation,
revision and latest request key again. A completion retained by the caller can
therefore become obsolete after reception. HTTP duplicates are ignored, and
search sequence checks prevent applying an owned page twice. Applying a result
updates its derived pane, leaving text, saved baseline and selection untouched.

Cancellation requests termination but retains the application's Flight
correlation until terminal reception. Polling the Service drains its native
completion and releases its token; application reception then makes the logical
lane available. Closing a document cancels its pending demand and active work,
while persistent protocol clients remain open. Reopening the document can queue
fresh work immediately, but dispatch waits for the old lane to retire.

Keep the reducer and its request-key counter while its documents remain open.
Recreate it only after all bindings close and Flights drain. The contract retains
an old owned HTTP export across this reconstruction, reuses request key 1 and
revision 1, and rejects the export through the new document generation. Replacing
the reducer while keeping the same open documents is outside this experiment.
Call `invalidate` when an edit makes current work obsolete, so producers stop
promptly; the revision guard also catches direct Store edits at dispatch/apply.

## Admission belongs to logical consumers

Six admission domains represent **document × protocol**. A replacement waiting
for one document's cancelled HTTP Flight must not prevent another document's
HTTP request from starting. Using only one FIFO domain per protocol would put
that blocked replacement in front of otherwise eligible consumers.

Dispatch builds an eligibility mask from the six application lanes, drops stale
pending scopes and submits the selected demand through its protocol owner. A
shared native LIMIT leaves valid demand and the admission turn intact. Poll both
Services before retrying. Fair selection remains conditional on eligibility and
available native capacity; it does not guarantee completion times.

The Queue allows seven pending descriptors for six logical lanes. This spare
descriptor permits enqueueing a provisional replacement before removing its old
demand, even when all six lanes have pending work. Refused input preserves the
old request, result pane and Flight. The spare is transactional workspace, not
an additional logical consumer.

## Verification and reproduction

The [contract](../../tests/document_services_contract.goose) and
[Python fixture](../../tests/document_services_fixture.py) run three application
lifetimes with the same protocol Services. A scripted independent document/request
model checks exact identity and adoption traces; a flat file supplies search
positions/previews, and HTTP barriers establish that work is actually active.
Recorded server paths prove superseded, closed and revision-stale pending HTTP
requests never start. Corrupted identity, token-count, page and hit traces must
be rejected.

Cases include replacing all six occupied pending lanes, exhaustion of all 64
native tokens, recovery after freeing capacity, active HTTP replacement,
delayed completion application, direct text edits, held-page cancellation,
close/reopen with both protocols active and duplicate owned exports. Other
documents progress while an obsolete lane is retiring. Before host polling,
two outstanding Flights leave exactly 62 tokens available; all 64 are
reacquired after each lifetime and final shutdown. Each lifetime ends with no
pending demand or Flight, all documents closed and Store collection complete.

```text
cmake --build build-core --config Release --target document_services_contract --parallel
ctest --test-dir build-core -C Release -R ^document_services_contract$ --output-on-failure
python tools/http_clients_qualification.py --build build-core --contract document_services --output local/document-services-run
```

The Windows/MSVC qualification on 2026-10-11 passed O0/O1/O2 with three
repetitions each: 297 HTTP requests, 135 searches, 5184 exported hit rows,
405 applied completions and 234 obsolete/duplicate completions rejected across
27 application lifetimes. Exported hit rows include the duplicate page checked
for rejection. Core CTest passed all 20 checks with manual tools enabled, and
the new target also built in the GUI configuration.

Qualification used one clean compiler checkout,
`71e848d732362a47ee7fe000a3e1601d0196259a`, with native C O2. Source/archive
snapshots, working-tree provenance and complete records remain under ignored
`local/references/document-services/development-run/`.
These checks establish this bounded lifecycle composition. They do not measure
throughput, total application memory, long-session RSS or graphical adoption.
The runner's HTTP Service layout probe excludes the document/search owners and
application records.
