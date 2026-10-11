# Why these patterns work in Goose

Goose works well in these experiments because storage ownership, logical identity
and asynchronous retirement are handled at separate layers. One explicit Store
can hold many independently lived objects; small records identify those objects;
isolated workers exchange owned messages. The language's placement and lifetime
rules fit this representation, while the libraries supply reuse, history,
resource accounting and result-adoption rules.

This is an explanation of demonstrated designs, not a cross-language benchmark.
C++, Rust, Go and Zig can implement the same arenas, piece trees and message
protocols. The difference is which representations their ordinary containers
make convenient, which rules the language checks, and which policies the
application must express. [Measured costs](goose-patterns.md) and
[qualification coverage](validation.md) remain separate evidence.

## Different starting points for ownership

| Language | A useful starting representation for several live documents | Where lifetime work appears |
| --- | --- | --- |
| C++ | A container of documents owning vectors/strings, or `unique_ptr<Document>` for separately placed objects | RAII can attach cleanup to an owner; vector reallocation invalidates interior references. Explicit arenas and stable IDs are also available. [Vector rules](https://eel.is/c++draft/vector.capacity), [unique ownership](https://eel.is/c++draft/unique.ptr) |
| Rust | A container of `Document { text: Vec<u8>, ... }`; `Box` when separate placement is useful | Moves and `Drop` express ownership; borrowing checks lifetime and mutable exclusivity. `Arc` adds shared ownership when needed, with synchronization for shared mutation. [Ownership](https://doc.rust-lang.org/book/ch04-01-what-is-ownership.html), [borrowing](https://doc.rust-lang.org/book/ch04-02-references-and-borrowing.html), [Vec](https://doc.rust-lang.org/std/vec/struct.Vec.html), [Arc](https://doc.rust-lang.org/std/sync/struct.Arc.html) |
| Go | Document records with slices, possibly reached through pointers/maps | Slices can share backing arrays; assignment does not copy their payload. GC manages unreachable heap memory, with a CPU/memory tradeoff. Application close/cancellation and stale-result rules still need explicit behavior. [Slice semantics](https://go.dev/ref/spec#Slice_types), [GC guide](https://go.dev/doc/gc-guide) |
| Zig | Document records with buffers managed through a caller-selected allocator | Allocation strategy, ownership and cleanup are explicit; valid pointer/slice lifetimes remain the programmer's responsibility. An arena or fixed buffer can be selected when it fits the workload. [Memory and ownership](https://ziglang.org/documentation/master/#Memory) |
| Goose | Fixed document descriptors referring to shared payload/history storage in an explicit Store | Placement and reference-root rules check memory lifetime; the Store manages logical open/close, generation IDs and storage reuse. Native close and asynchronous retirement are explicit. [Validated specification](https://github.com/akeit0/goose/blob/71e848d732362a47ee7fe000a3e1601d0196259a/docs/goose_spec.md), §§3.4, 4, 5.4, 9, 11.2 |

These are possible starting points, not mandatory styles or performance rankings.
RAII does not require one allocation per object, Rust does not require `Arc` for
concurrency, and a GC language can use bounded arrays and explicit storage pools.
The comparison below asks how to carry an existing design into Goose.

## Separate physical storage from logical objects

A C++ vector or Rust Vec is an owner of separately placed element storage. A
record can contain several such owners, and its elements can own more vectors.
That makes a container of independently growing document buffers straightforward;
stable interior references are a separate requirement. C++ vector reallocation
invalidates them, while Rust constrains borrowing around mutation.
[C++ rules](https://eel.is/c++draft/vector.capacity),
[Rust representation](https://doc.rust-lang.org/std/vec/struct.Vec.html) and
[borrowing rules](https://doc.rust-lang.org/book/ch04-02-references-and-borrowing.html)
describe these mechanisms.

Goose stores values inline. A resizable part must be the tail of its containing
value, and array elements cannot themselves be resizable. Immutable variable-size
records are a different case: Goose can store them inline in a sequential array.
The restriction concerns independent ongoing growth, not the ability to represent
nested data. See the [specification](https://github.com/akeit0/goose/blob/71e848d732362a47ee7fe000a3e1601d0196259a/docs/goose_spec.md),
§§3.3–3.4.

For resident editable documents, place logical records in a bounded table and
put their payload in one Store. Each record holds roots, lengths, selection,
history and generation. Closing A releases its chunks or drops its roots while
B continues to use the same Store. Independent logical lifetime is implemented
by the Store's operations; it need not correspond to a separately resizable
language value for every document.

Two unrelated payload owners can remain separate caller locals. The document
Store, HTTP Service and search Service each keep their own resizable tail; a
fixed coordinator borrows them. This preserves separate budgets and APIs without
combining their storage. The [document-scoped contract](io/document-services.md)
demonstrates three documents and six request lanes with this composition.

## Allocation freedom becomes representation work

Goose's normal grow-only arrays grow in place within compiler-assigned data-stack
regions. Existing references survive that growth. Fresh results are constructed
at their destination; copying an already constructed payload is a different
operation. Fixed-size values, including large bounded arrays, can still copy
implicitly. See the [specification](https://github.com/akeit0/goose/blob/71e848d732362a47ee7fe000a3e1601d0196259a/docs/goose_spec.md),
§§4.1–4.3, 5.1 and 10.

This removes the need to choose a general allocator for each ordinary Goose
container. It leaves important storage decisions visible in libraries:

Compiler-assigned regions separate independently resizable local owners, and
scope exit releases their scoped storage through stack restoration. Closing one
logical object inside a longer-lived Store is a different operation: its bytes
must be reusable or collectible while the region's owner remains alive. This
is where the descriptor table, freelist and live-root set do useful work.

| Workload | Representation used here | Why it fits | Remaining work |
| --- | --- | --- | --- |
| Independently growing byte results with random reads | [Indexed chunks](buffer/indexed.md) | Reuse complete chunks; directory lookup reaches a chunk directly | Reserved directories, slack, range traversal and owned export copies |
| Small replaceable variable values | [Slot arena](buffer/slot-arena.md) | Reuse holes and compact only under pressure | Bounded scans, retained holes, compaction and offset repair |
| Edits with saved/Undo versions | [Persistent piece tree](document/store.md) | Share unchanged spans and tree paths across live roots | New nodes, source bytes, collection and prefix growth |
| Variable contiguous runs | [Reusable slice pools](experiments/pool-runtime.md) | Reuse runs inside one typed region | Run growth can copy to a different location; old views can name reused data |
| Sparse result pages | [Compact packets](io/streams.md) | Transport used fields and keep ready payloads in shared storage | Codec validation, encoding/export copies and credit bookkeeping |

These data structures are familiar in other systems languages. Goose makes them
useful ways to express independent lifetime within its inline storage model.
Their efficiency comes from the chosen operations: sharing unchanged history,
avoiding repeated survivor shifts, addressing chunks directly and transporting
used fields. The language supplies a compatible storage and construction model;
it does not select the optimal representation automatically.

An arena is also a useful explicit choice in Zig; its allocator interface gives
the caller control over that choice. Goose instead supplies its data-stack and
typed reuse mechanisms as language/runtime facilities. Both approaches still
need workload-specific placement and release policies.
[Zig allocator guidance](https://ziglang.org/documentation/master/#Choosing-an-Allocator).

Goose's lack of a general user heap does not mean the entire process has no
allocations. Address regions, queue storage, worker stacks and native HTTP/font/
graphics libraries consume memory. Returning storage to a freelist or reducing
an arena's logical length does not establish lower RSS. Library quotas also
do not make runtime/OS memory exhaustion recoverable.

## Persistence shares versions, not whole document copies

A piece tree's main saving comes from its algorithm. Current text, saved text,
Undo and Redo retain roots into shared spans and nodes. An edit constructs the
changed paths; it does not require copying every unchanged byte for each version.
That benefit can be obtained in all the languages compared here.

An implementation using reference-counted node ownership or GC can involve its
memory manager in keeping shared nodes alive. The Goose
[document Store](document/store.md) uses indexed roots in one owned arena and
performs library collection over current, saved, Undo and Redo roots for every
open document. It repairs indices during compaction. This is collection of a
known library representation with an explicit live-root set; Goose does not
automatically trace arbitrary application objects.
[Reference-counted ownership](https://doc.rust-lang.org/std/sync/struct.Arc.html)
and [heap tracing](https://go.dev/doc/gc-guide) illustrate the memory-manager
mechanisms being compared.

The root set makes the cost and obligations visible: dropping history or closing
a document makes nodes reclaimable, but collection must preserve every remaining
version. Source-byte retention, new-node writes, collection scans and node-prefix
growth all still cost work. The equal-history experiment compares this tree
representation with whole-text snapshots **within Goose**. It demonstrates
history sharing, not an advantage over Rust's or C++'s possible piece trees.

## Safe references and current identity are different

Rust's ordinary borrowing model constrains overlapping mutable and immutable
access as well as lifetimes. Goose allows aliasing within its isolated program
instance and checks reference roots and valid typed storage instead. Mutable
state is not shared between Goose workers. This is a different set of constraints,
not removal of lifetime checking.
[Rust borrowing](https://doc.rust-lang.org/book/ch04-02-references-and-borrowing.html),
[Goose specification](https://github.com/akeit0/goose/blob/71e848d732362a47ee7fe000a3e1601d0196259a/docs/goose_spec.md),
§§9.1–9.4 and 11.2.

A reference into a Goose reusable slot can remain memory-safe after that slot
is freed and reused: it sees another value of the same type. A slice-pool run
can similarly be reused or copied during growth. The compiler does not promise
that a retained view still denotes the same logical document or result.

The lab therefore uses `(slot, generation)` IDs at object boundaries, and
indices internal to an owner whose compactor/collector repairs them. Generations
reject a closed/reopened slot; Store identity is a caller obligation because
equal IDs from different Stores do not imply the same object. Borrow payload
only during a synchronous operation. Keep an owned export across mutation,
compaction or close. Growth-stable references remain useful where the structure
actually preserves identity and placement.

This distinction also matters with heap ownership or GC: keeping bytes alive
does not prove that a completion belongs to the currently displayed document.

## Isolation narrows the concurrency problem

Rust supports both message passing and shared-state concurrency, with `Send`/
`Sync` expressing transfer and sharing constraints. `Arc` supplies shared
ownership, not synchronization for arbitrary mutation.
[Rust concurrency](https://doc.rust-lang.org/book/ch16-04-extensible-concurrency-sync-and-send.html),
[Arc contract](https://doc.rust-lang.org/std/sync/struct.Arc.html).

A Goose `thread_fn` runs as a separate program instance with its own mutable
storage. Arguments and queue messages must be flat values and are copied across
the boundary. A worker cannot hold an ordinary Goose reference into the host's
document Store. This encourages an explicit request/result protocol and limits
shared-memory coordination inside Goose code. Runtime queue internals and native
libraries can still use synchronization; copied integer native handles can still
alias the same external resource.
[Goose specification](https://github.com/akeit0/goose/blob/71e848d732362a47ee7fe000a3e1601d0196259a/docs/goose_spec.md), §11.2.

Typed routing also has a cost. Queues are selected by message type, rather than
by an arbitrary runtime queue object. Two Services consuming the same protocol
would compete for messages. The current design uses one Service per protocol
and generation/serial routing to many logical clients. Distinct ACK lane types
separate bounded search producers. Isolation supplies the message boundary;
mailboxes, fairness, backpressure and shared native quotas remain library policy.

## Three lifetimes must agree at result application

| Lifetime | What must remain valid | Mechanism in the lab |
| --- | --- | --- |
| Storage | The borrowed memory exists and has the right type | Compiler reference roots; synchronous borrows; owned exports |
| Resource operation | The submitted producer and its leases are accounted for | Flight correlation, cancellation, terminal drain and worker shutdown |
| Application meaning | The result still matches the current document and intent | Document generation, revision, latest request key and page sequence |

Suppose document A starts a search, then the query changes while its first page
is held. The page remains an owned valid value. Cancellation asks the producer to
stop; its Flight remains until terminal reception. Applying the held page later
checks the application scope and rejects its obsolete request key. Another
document can start work through a different eligible admission domain.

The [application experiment](io/document-services.md) implements this with six
document × protocol domains, a provisional descriptor for safe pending
replacement, and separate reception/adoption operations. None of these semantic
rules follows solely from memory safety, RAII, borrowing or GC. The experiment
also keeps the request-key owner while documents remain open; resetting it with
the same document identities could make old keys collide.

## Why the result is useful, and what the evidence says

The useful fit is specific: independently lived logical objects can share explicit
storage; borrowed APIs coordinate separate resizable owners; isolated workers
return owned messages; generations and request scopes preserve current meaning.
This gives Goose libraries a practical way to express document history,
multi-client services and bounded application demand using existing language
features. It makes storage costs and lifecycle transitions reviewable in the
library rather than leaving them implicit in an object graph.

Independent flat/list models, controlled HTTP barriers, held exports, slot reuse
and native registry reacquisition test those transitions. The document-scoped
qualification passes O0/O1/O2 with three repetitions each. These checks support
the bounded workloads described in the linked guides; they do not prove every
Goose program safe or establish a speed/RSS advantage over another language.
No equivalent C++, Rust, Go or Zig application was timed in these experiments.

The tradeoffs remain concrete: fixed tables reserve their maximum representation;
owned queue/export values copy; library collectors must enumerate every live
root; native cleanup and error exits are explicit because Goose has no
destructors. Current protocol routing and lane counts restrict composition.
Arbitrary object graphs, unbounded populations or fine-grained shared mutable
state would need a different design and focused verification. The next useful
comparison is an equal-work implementation of a particular workload, with
history, quotas, payload ownership and cleanup matched across languages.
