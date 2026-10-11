# Useful storage and lifetime patterns in Goose

The experiments in goose-lab point to a useful design starting point: give each
resource one explicit owner, keep logical objects in small indexed records, and
choose payload storage according to the operations and lifetimes it must support.
Goose's single resizable tail can hold shared storage for independently lived
objects. Independence does not require a separate resizable value per object.

This guide collects patterns demonstrated by the current libraries and samples.
It separates representation/correctness evidence from speed or total-memory
claims. The linked guides contain bounds, contracts and reproduction commands.
The [language comparison](goose-language-comparison.md) explains the design shift
from independently allocated objects to explicit Stores and logical identities,
and separates language guarantees from application policy.

## Choose storage by the work

| Requirement | Useful representation | Work it avoids | Cost to include |
| --- | --- | --- | --- |
| Small or short-lived contiguous data | Owned byte array / geometric contiguous run | Chunk traversal and flattening for contiguous consumers | Growth can relocate retained capacity; middle edits and snapshots copy bytes |
| Independent append/write/truncate buffers with random reads | [Indexed chunks](buffer/indexed.md) in one owner | Relocation of existing payload during library chunk growth; linked-chain traversal on scalar reads | Fixed directories, chunk slack, initialization, owned export copies |
| Small bounded sets of replaceable variable values | [Slot arena](buffer/slot-arena.md) with hole reuse and deferred compaction | Moving survivors on every removal; large chunk-directory reservations | Retained holes, bounded table scans and occasional compaction |
| Middle edits with retained Undo/Redo and saved versions | [Persistent piece tree](document/store.md) in a shared owner | Full-text copying for each history entry; unchanged spans/nodes can be shared | New nodes, retained source bytes, collection and prefix-growth moves |
| Short-lived, sparsely populated result pages | [Compact packets and ready-payload arena](io/streams.md) | Serializing unused fixed-array capacity and reserving a full payload per mailbox | Encode/decode/export copies, retained holes and pressure compaction |
| Cooperative admission across owners sharing a native quota | [Bounded demand descriptors](io/mixed-services.md#fair-host-admission-and-repeated-reuse) with domain turns and FIFO tickets | Copying request payloads during refusal/retry; combining unrelated owners | 128 reserved records, bounded scans, explicit eligibility and completion polling |
| A few unrelated resizable subsystems | [Separate local owners](goose-feedback.md#composing-document-and-git-pages) plus borrowed references | Combining unrelated storage into one arena | Caller coordinates lifetime and passes each owner explicitly |
| Small entity sets with optional components | [Generation IDs and dense maps](ecs.md), with typed AoS stores or explicit SoA columns | Per-entity allocation and searching all entities for each component | Fixed capacity, map repair on swap-removal and deferred structural changes |

These choices compose. HTTP clients use indexed storage for variable result
bytes; a document Store uses persistence for history; a stream Service retains
only encoded ready pages. An append buffer does not acquire text-edit or Undo
semantics just by using chunks. Persistence is useful when old versions must
survive; it adds work when they do not.

## One owner, many logical lifetimes

An array cannot own independently resizable Document values. A reusable
alternative is a bounded table of descriptors plus one growable payload tail.
Descriptors hold lengths, indices, roots, status and generations; the tail holds
the bytes or node records. Closing one logical object releases its storage for
reuse or collection while preserving the others.

Keep indices relative to the owner rather than retaining references into arrays
that may move. A chunk directory maps byte offsets to chunk slots. Tree children
and roots are numeric indices; collection remaps them. A compact mailbox records
a byte offset; compaction updates remaining offsets. Each representation has its
own invalidation rule. Numeric indices alone do not make relocation safe.

Borrow slices for synchronous work. Return an owned export when callers must
retain data across mutation, close or shutdown. Avoid materializing a whole
buffer just to inspect a small range. At a contiguous file/native/queue boundary,
account for the copy required by that boundary.

When the caller already owns the destination, an output-reference API such as
`slot_arena::append_to` copies directly into that destination. This avoids an
intermediate owned array and an additional explicit copy when building another
resizable value. It does not remove the destination copy or its growth cost.

Logical identity and byte placement can be separate layers. The stream owns
generation/serial checks; its slot arena only manages caller-assigned indices.
This keeps lifetime checks at the service boundary without duplicating them in
each internal storage record. Direct users must provide their own stale-ID policy.

Resource ownership remains a convention in these APIs. Copying an integer native
handle aliases the same resource; explicitly copying a Store or Service does not
establish a second valid resource owner. Keep create/use/close in the designated
owner, and route IDs back to it. See [indexed ownership](buffer/indexed.md#ownership-and-api)
and [architecture](architecture.md).

## Indexed chunks for independent byte buffers

[`lab.buffer.indexed`](../lib/lab/buffer/indexed.goose) combines per-buffer chunk
directories, one byte arena and a library freelist. Scalar addressing uses the
directory entry at `offset / chunk_bytes` and the offset within that chunk.
Appending another chunk does not relocate the buffer's already stored payload;
closing or truncating returns complete chunks for reuse. Range operations walk
spans rather than starting a linked-chain scan for every byte.

This is useful for independently growing results or binary buffers when direct
reads matter. It trades lookup work for metadata: the current bounded Store
reserves 64 directories of 512 entries and 4096 freelist entries, or 147456 raw
entry bytes. Its measured fixed representation is 148861 bytes on Windows
x64/MSVC, even for one empty buffer.

Chunk size controls slack and operation count. In the equal-work 64-buffer,
48-round mixed trace, 1024/4096/16384-byte chunks retain 2359296/2490368/2883584
payload-capacity bytes for 2359296 logical bytes. Smaller chunks require more
slots and allocation/cleanup work. In the default mixed trace, 4096 random reads
require 4096 directory visits versus 26219 linked-chain visits, with equal
payload capacity. This establishes an addressing tradeoff, not a throughput
ranking. See the [storage comparison](experiments/buffer-storage.md).

The arena may itself be backed by movable Goose runtime storage. Avoiding
library payload relocation does not establish zero physical copies or OS memory
release. Owned range exports still copy the requested bytes.

## Persistent piece trees for editing and versions

[`lab.document.piece_tree`](../lib/lab/document/piece_tree.goose) is a persistent
AVL tree over source-byte spans. Leaves describe spans; branches retain byte and
newline totals, height and leaf count. Offset and line lookup descend using these
aggregates instead of scanning the whole document. Bounded leaves limit the
local scan needed after descending. Adjacent contiguous source spans can merge.

An edit appends inserted bytes and builds replacement paths with split/join and
balancing. Unchanged subtrees and source bytes remain shared. Current text,
saved baseline and Undo/Redo can therefore retain roots instead of full text
copies. Identical replacement detection traverses spans against borrowed input
without exporting the replaced range.

The [document Store](document/store.md) applies the same idea to many documents:
fixed descriptors/history records refer to one shared tree arena. A successful
save adopts the appropriate saved root after checking the expected revision;
failure or a stale completion must not mark newer edits saved. A saved root may
outlive the Undo entry that originally introduced it.

Collection must include **every live root**: current, saved, Undo and Redo for
every open document. It marks and compacts nodes, remaps roots/children, unions
reachable source spans and rewrites retained text. Closing documents, evicting
history and dropping Redo make storage reclaimable. Exposing raw roots outside
the owner would let collection silently invalidate callers.

The single-tail representation packs seven-word node records before text words.
Increasing the reserved node prefix moves existing text words. Each node record
occupies 56 bytes; arena length includes reserved node capacity and text-word
rounding. Cheap history sharing still pays for node creation, collection,
prefix growth and contiguous exports. Measure them separately.

With 64 initially 4096-byte documents, 64 rounds and equal 32-entry history,
the recorded shared-tree arena high-water was 723456 bytes versus 8916992 for
snapshots. Inserted/collection/prefix-growth byte work totaled 4722552 versus
19660800 snapshot payload-copy bytes. The tree count excludes node writes and
implicit runtime copying; both implementations also reserve roughly 1 MiB of
fixed document/history metadata. These first-byte-edit traces demonstrate
sharing, not a general edit-speed or total-memory result. See the
[equal-history comparison](document/store.md#verification-and-equal-work-comparison).

UTF-8 storage positions, CRLF boundaries and user editing units are separate
contracts. The editor's grapheme accessor reads through the tree with at most
four scratch bytes instead of flattening a document; preceding Unicode context
can still require a longer scan. The shared Store's byte-range API does not
provide the editor's typing groups or grapheme navigation. See
[text boundaries](ui/text-foundation.md#editing-boundaries).

## Compact transport for sparse bounded data

A fixed-capacity array reserves its representation even when little is used.
The default `to_bytes` packet codec preserves that capacity. When typical queue
messages use few entries or short strings, a domain codec can encode counts,
lengths and actual bytes, while the public API continues to return owned values.
Keep decode validation complete and reject malformed images without a partial
result. Search checks its codec against an independent Python byte layout.

The [stream Service](io/streams.md) keeps small mailbox records and one arena
containing only encoded **ready** payloads. Taking a page exports its bytes and
clears its slot; a held page retains only receipt/status metadata. The original
arena shifted later bytes on every removal. The current
[slot arena](buffer/slot-arena.md) reuses holes and compacts only when a put cannot
fit a hole or remaining tail within its bound. Its 64-varied-page take permutation
moves zero bytes versus 285768 previously. The cost moves to retained holes,
bounded descriptor scans and occasional compaction: a pressure case moves two
65536-byte survivors once to fit a larger replacement. Logical bytes and arena
length must therefore be measured separately.

Current fixed search Service storage is 10195 bytes, versus 2859463 in the original
fixed-mailbox implementation, excluding the payload tail and caller-owned exports.
Slot storage and work counters add 148 bytes over the eager-compaction header. The
64-client sparse trace transported 481792 queue-image bytes versus a 14269440
fixed-Page equivalent, a 96.6% reduction. The equivalent uses the same message
count times the old fixed Page size; it is not a second throughput run.
That baseline additionally shifted 270410..370544 bytes across repeats. Current
slot storage moves zero bytes on that trace, with 37568..47104 gap-search
descriptor visits; the fixture does not exercise retained-gap writes. The
controlled held-neighbor case separately verifies 98304 reused bytes without
additional survivor moves. Retaining the queue codec keeps queue-byte totals
unchanged. A
maximum-size encoded Batch makes its queue image nine bytes larger than the
old fixed Page. Compact transport depends on occupancy, not just the type name.

## Generation, request identity and credit are separate

| Field or mechanism | What it protects |
| --- | --- |
| Slot + generation | A closed/reused logical object cannot adopt an old result |
| Request serial / expected revision | A newer request or edit cannot be overwritten by an older completion |
| Flight ticket | A particular submitted job and its retained resources |
| Page sequence + worker lane | Ordering and credit for the correct producer |
| Cancellation | Cooperative termination intent; identity checks still reject stale completions |

IDs are scoped to one owner and lifetime; equal IDs from two Stores are not proof
of shared identity. Closing a client invalidates its generation immediately,
but the submitted job still owns an inflight slot and cancel token until terminal
completion. Keep that retired Flight record so repeated close/reopen cannot
bypass resource limits. Generation exhaustion retires a slot rather than wrapping.
See [HTTP client lifecycle](io/http-clients.md) and [stream lifecycle](io/streams.md).

Typed queues are a routing tool. `Packet<P>` separates payload protocols;
`Ack<P, LaneN>` gives each bounded worker a distinct ACK queue despite identical
byte layouts. Exactly one Service per packet type receives that queue in a
program. Eight concrete `thread_fn` entry points call a shared generic lane
implementation because the thread entry point itself cannot be generic.
This is a useful static pattern, with explicit lane count and owner limits.

Different protocols can keep separate owner variables and borrow each through
their APIs. The [HTTP/search composition contract](io/mixed-services.md) checks
both shutdown directions, close/reopen, held exports and recovery from their
shared native cancel-token quota. Queue isolation does not isolate native
capacity: a Flight holds its token until its completion is drained, and every
owner contributes to the same 64-slot process limit. Treat admission refusal as
recoverable without advancing request identity; poll completions before retrying.
This supports separate protocol owners, while one owner per identical protocol
remains the rule.

When owners share a native quota, keep admission policy in a small separate
fixed-record owner. [`lab.io.admission`](io/mixed-services.md#fair-host-admission-and-repeated-reuse)
holds bounded demand keys, rotates among eligible domains after successful
admission, and keeps FIFO order within each domain. Request payloads and Flights
remain owned by their existing stores and Services. Shared-capacity refusal
preserves the selected turn until polling frees capacity; a caller skips domains
blocked by their local limits using an eligibility mask. Acceptance checks the
selected ticket with the same mask, refusing queued demands out of turn without
mutating the owner. Selection needs one bounded table scan and no extra index.
This verifies admission order without claiming equal completion time or
manufacturing native credits.

Choose admission domains by the independently eligible consumer. The
[document-scoped experiment](io/document-services.md) uses six domains for three
documents and two protocols, so a cancelled Flight awaiting retirement cannot
block another document's demand for the same protocol. A spare pending descriptor
allows provisional enqueue before removing the previous request, preserving it
on refusal even when every logical lane is occupied.

Resource reception and application adoption can have different lifetimes. Export
an owned completion correlated with its Flight, then check document generation,
revision and latest application request key when applying it. Cancellation does
not replace these checks: a result already received may still become obsolete.
Keep the request-key owner while its documents remain open, and track page
sequence separately to reject duplicate application without granting credit.

Give each producer one unACKed data page. Polling or taking does not grant
credit; explicit ACK/discard does. Keeping a page can stall that producer while
other active lanes progress. If every lane waits, queued jobs wait too. This
provides bounded buffering, not per-client fairness or unbounded concurrency.

Cancel and join workers before draining their final traffic and destroying
host-owned tokens. Thread-owned native contexts close on their worker before
terminal publication. Bound workers and logical clients against process-wide
native handle quotas; eight workers do not each receive an independent global
read budget. Exported owned values remain valid after Service shutdown.

## Reduce work before changing storage machinery

An immutable variable-size plan can stay in one owner and serve many borrowed
inputs. The [regex experiment](experiments/regex-ecs-server.md#regex-reuse-the-upstream-engine)
compiles once per batch, borrows capture slots during callbacks and copies bytes
only when retaining an export. The same compiled plan parses commands for a
bounded TCP server whose connection buffers and game World remain separate.
No plan or native socket becomes a hidden per-entity owning object. The server
retains only the unsent response suffix when output capacity is needed again.
It checks another connection's progress while a real kernel write is blocked,
then verifies every response byte after reads resume; finite buffer limits alone
do not establish that behavior.

Dense component storage also separates identity from placement. The
[ECS game](experiments/regex-ecs-server.md#ecs-dense-components-stable-logical-ids)
uses generation IDs, sparse row lookup and swap-removal. Query passes defer
deletion until traversal ends, so a moved row cannot be skipped during the same
pass. Movement visits only entities with Velocity; collision order is defined
by logical slot rather than dense row order. These properties are checked against
a dictionary model. The current 64-entry fixed World costs 7310 generated bytes even when
its configured logical capacity is three, and its collision scan is quadratic.

The [line transport](io/line-server.md) reserves response space before invoking
application code, retains unsent bytes and bounds draining with a caller-supplied
monotonic clock. The [arena client](apps/arena.md) parses into a fixed pending
snapshot and publishes it only after a complete, validated END frame. Network
progress and application-state adoption are separate operations; neither stores
a borrowed view after its call ends.

Star Race's offline and versus modes use the same pure rules and fixed view
schema. The network controller owns a bounded history of numbered movement
steps; it drops acknowledged steps and replays the rest after authoritative
correction. The server pushes state independently of requests and admits at most
one pending state packet per peer, skipping busy peers until newer state can be
sent. These are sample policies, not ECS or transport responsibilities. Owned
copies are deliberate where values must survive later ticks or callbacks;
mutable component access uses an explicit borrow rather than copying the value
returned by a reference accessor. See [mode and communication contracts](apps/arena.md).

The same principle applies outside arenas. Compare a no-op edit against borrowed
spans, query aggregates or accessors instead of flattening, and retain only the
layouts needed by the viewport. Immutable generated Unicode tables avoid runtime
data loading in ordinary builds; a small streaming state handles contiguous
scans. See [text foundation](ui/text-foundation.md).

For rendering, exact scene bytes plus resource/revision identities allow the
renderer to skip unchanged uploads/render passes and on-demand presentation.
This does not stop CPU polling or frame construction. Cache invalidation and
native/GPU lifetimes are part of the pattern, not optional details around it.
The recorded submission/presentation counters establish skipped work, not desktop
GPU utilization. See [unchanged frames](ui/text-foundation.md#unchanged-frames).

## Make the cost and contract reviewable

Preflight the whole request before publishing or changing payload. Validate sizes,
encoding and all relevant quotas together. An indexed-buffer refusal preserves
payload and allocation counters. A document refusal preserves logical state,
but its preflight may collect/remap internal storage. State exactly which promise
the API makes. Library quota errors do not make OS/runtime OOM recoverable.

Track logical bytes, retained capacity/arena length, fixed metadata, exports,
collection/relocation/compaction work and native resources separately. A lower
arena length or reused freelist does not establish lower RSS. A bounded object
table is not small merely because the caller selects three of its 64 slots.
Measure generated layout rather than guessing from live entry count.

Use an independent flat model and equal logical work/history for representation
comparisons. Exercise different object sizes, non-LIFO close, immediate slot
reuse, stale completions, quota refusal, held exports and shutdown with stalled
workers. Reacquiring native registry slots after shutdown checks handle leases;
it does not account for every allocator. Snapshot sources and compiler/binary
hashes when recording optimization-level qualification. Routine checks use one
upstream-tracking compatible fork; investigate a specific fork difference with
a focused probe rather than duplicating every suite.

The reusable indexed buffer, slot arena, shared document Store, HTTP clients and bounded
streams demonstrate these structures with existing Goose. Workbench adoption of
the multi-document Store and multi-client services is separate from their library
contracts. Dynamic queue instances, fair multiplexing, smaller fixed history
metadata, collector/compaction latency and long-session OS memory remain useful
follow-up questions when a concrete workload needs them.
