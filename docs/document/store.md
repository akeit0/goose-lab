# Shared persistent document Store

`import lab.document.store;` uses namespace `lab_document_store`. A caller owns
one `Store` containing fixed document/history descriptors and one shared Piece
Tree arena. This pure Goose library retains multiple independently editable
documents without module-global storage, native allocation handles or exported
arena references. It reuses `lab.document.piece_tree`; the existing single-document
model and Workbench continue to use their own document owners.

```goose
import lab.document.store;
fn main() {
    var store = lab_document_store::create();
    assert(store.code == lab_document_store::OK);
    let a, ac = lab_document_store::open(store, "one");
    let b, bc = lab_document_store::open(store, "two");
    assert(ac == 0 && bc == 0);
    assert(lab_document_store::replace(store, a, 3, 3, "!") == 0);
    assert(lab_document_store::undo(store, a));
    lab_document_store::collect(store);
    let bytes, code = lab_document_store::contents(store, b);
    assert(code == 0 && bytes == "two");
    lab_document_store::close_all(store);
}
```

## Ownership and operations

IDs contain slot and generation and belong to one Store's lifetime. Use them
only with that Store; they do not enforce cross-Store identity. Copies alias the
same document. Close makes old IDs stale, reopening increments generation, and
exhausted generations retire the slot. Multiple Stores are independent local
owners. Treat all fields, roots and arena offsets as implementation state.

| API | Contract |
| --- | --- |
| `create(Limits)` | Check `store.code` before use |
| `open(store, bytes)` | Return `Id, code`; initial current/saved roots share one text source |
| `contents`, `baseline` | Return fresh owned bytes and code; exports survive collection/close/reuse |
| `size`, `revision`, `dirty`, `selection` | Read per-document state; stale size is -1 and stale revision is 0 |
| `select` | Set cursor/anchor at valid UTF-8/CRLF byte boundaries |
| `replace` | Insert/delete/replace; no-op preserves revision/history; each changed edit is a separate Undo entry |
| `undo`, `redo` | Restore root, selection and revision independently per document |
| `mark_saved(store, id, expected_revision)` | Adopt the current root after successful publication; reject outdated revision/ID |
| `close` | Drop current/saved/history roots; reclaim their unreachable storage on collection |
| `collect` | Retain and remap all live current, saved, Undo and Redo roots together |
| `close_all` | Close every document and collect unreachable text/nodes |
| `stats` | Logical document lengths, physical arena representation and instrumented work counters |

UTF-8 validity, NUL exclusion and CRLF-interior rejection match the snapshot
baseline. Grapheme navigation and typing-group merging are outside this API.
The library is a storage/model experiment, without filesystem jobs or UI services.
The caller owns publication; failed disk writes must not call `mark_saved`.
Adopting a saved root copies no text and requires no new text allocation.

`INVALID`, `LIMIT` and `STALE` distinguish argument, quota and lifetime failures.
Validate text, edit boundaries and document length before mutation. Arena/text/node
preflight may collect once under pressure. A failed allocation request preserves
every document's text, history, selection, revision and saved state, although
collection can change internal numeric roots, representation size and counters.
Node reservation is conservative and can refuse work before the exact remaining
node count is exhausted. Runtime/OS exhaustion is still fatal.

## Representation and costs

Bounds are 64 documents, 256 Undo entries per document, 2 MiB per current text,
64 MiB retained source text, up to 1048576 nodes and a 128 MiB arena length limit.
Defaults reserve at most 131072 nodes and a 96 MiB arena limit. History is
configurable downward. Nodes occupy seven `u64` words each; their growable prefix
precedes packed text words in the single resizable tail. Growing that prefix
moves existing text words. Edits append inserted bytes and persistent nodes;
unchanged document bytes and saved/history roots share existing sources.
No-op detection compares borrowed bytes by traversing Piece spans, without
materializing an owned copy of the replaced range.

Collection marks all retained roots, compacts/remaps nodes, unions reachable leaf
text spans and rewrites compacted text. Dropped Redo, evicted history and closed
documents become reclaimable together. A survivor's saved root can outlive history
eviction. Numeric roots remain internal because collection changes their IDs.

On Windows x64/MSVC the packed fixed `Store` is **1053561 bytes**, including
document/history arrays and the tree header, even with only one empty document.
The snapshot baseline's fixed 64-document table alone is **1059521 bytes**;
its pool/freelist/registry state adds overhead. Lowering the history limit does
not reduce these reserved array capacities. This is a remaining library design
cost, particularly at small document counts.

`current`/`saved` are logical lengths and may refer to the same physical bytes.
`used` is all currently stored node records plus text, including unreachable data
until collection; `arena` includes the reserved node prefix and text-word rounding.
`high_water` is the largest observed arena length. Fixed descriptors, temporary
mark/mapping/root/range arrays and allocator backing granularity are excluded.
These lengths do not measure RSS, committed pages or memory returned to the OS.

The Piece Tree's new metrics separately count inserted source bytes, text bytes
rewritten during collection, text-word bytes moved during node-prefix growth,
node-record writes, collection calls and scanned node records. They exclude owned
exports, implicit runtime relocation/zeroing, metadata-temporary allocation and
allocator bookkeeping. Timing includes these instrumentation increments.

## Verification and equal-work comparison

The [contract](../../tests/document_store_contract.goose) checks real save success/
failure, stale completions, UTF-8/CRLF boundaries, history eviction, Redo truncation,
two Stores, text/arena refusal and reclamation after closing another document.
For 3/16/64 documents it compares 2400 edit/Undo/Redo/select/save/collect/close/reopen
operations per count against independent flat snapshot arrays, checking all state.
Another 600 operations compare three initially 60000-byte documents against the
full-snapshot baseline across Piece boundaries. Both pass at Goose O0/O1/O2.

```text
cmake -S . -B build-core -DGOOSE_SOURCE_DIR=/path/to/compatible/goose -DGOOSE_LAB_GUI=OFF -DGOOSE_LAB_BUILD_TOOLS=ON
cmake --build build-core --config Release --parallel
ctest --test-dir build-core -C Release -R document_store --output-on-failure
python tools/document_store_experiment.py --build build-core --output local/references/document-store/equal-history-run
python tools/document_store_qualification.py --build build-core --output local/references/document-store/qualification-run
```

The [comparison runner](../../tools/document_store_experiment.py) uses the same
32-entry history limit, first-byte edits, Undo/Redo, saved revisions, arbitrary
close of even slots and reopening for both representations. Each document has
a distinct ASCII marker. Three text shapes, 3/16/64 documents and three repeats
produce 54 processes on one compatible upstream-tracking toolchain. Assertions
compare complete payloads before/after retirement and reopening. The independent
Python oracle verifies every row's logical work, history retention, snapshot copy
volume and shared-tree source bytes, including the union retained after collection.
Tree collection runs every eight rounds and after retiring half the documents;
the snapshot implementation frees runs during edits/close and needs no collector.
Snapshot `checkpoint` rows have zero placeholder duration and are excluded from
timing summaries. Compare editing/lifetime costs with collection cost separately.

The Windows/MSVC default run (4096 bytes, 64 rounds, history 32) passed all 54
traces. The following counters include retirement/reopening/cleanup:

| Documents | Snapshot arena high-water | Shared-tree arena high-water | Snapshot copied bytes | Shared inserted bytes | Shared collection copy | Shared prefix-growth moves |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | 421888 | 26744 | 925696 | 20672 | 102972 | 65664 |
| 16 | 2232320 | 180864 | 4915200 | 99328 | 560192 | 500672 |
| 64 | 8916992 | 723456 | 19660800 | 397312 | 2240768 | 2084472 |

All shapes gave the same storage counters on this first-byte trace. At 64
documents, shared inserted/collection/growth bytes total 4722552, versus 19660800
snapshot payload-copy bytes; this still excludes node writes and implicit runtime
copies. Arena savings exclude the approximately 1 MiB fixed descriptors in both
representations. These are representation results, not a total-memory or platform
speed ranking. Ignored records are the directories above, containing revisions,
source snapshots/hashes, binary/compiler hashes, raw output and oracle results.
The qualification runner compiles copied contract/library sources at O0/O2, holds native C
optimization at 2 and probes both generated fixed layouts; CMake tests cover O1.

Existing Goose can express shared persistent state with an explicit owner and
bounded fixed descriptors. This comparison establishes no need for a language
or runtime change. Remaining costs are fixed history metadata, collector work and
text relocation during node-prefix growth. GUI adoption, typing groups, hours of
uptime and OS memory stability remain untested by this experiment.
