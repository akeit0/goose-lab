# Geometric runs, linked chunks and indexed buffers in Goose

This experiment asks whether existing Goose slice pools can avoid relocation
copying while retaining independently lived buffers. It compares a geometric
contiguous run with a linked list of fixed-size chunks on the same deterministic
workload. The two controls use only `std` and `os` in
[`buffer_storage.goose`](../../tools/experiments/runtime/buffer_storage.goose).
The third mode exercises the reusable
[`lab.buffer.indexed`](../buffer/indexed.md) library through
[`indexed_buffer.goose`](../../tools/experiments/runtime/indexed_buffer.goose).
It owns a Store with a single grow-only byte arena and a library chunk freelist;
the controls use the runtime slice pool. All three use the same selected compiler.

The normal validation target is the upstream-tracking compatible fork. Do not
build and rerun a second upstream checkout routinely: use an upstream-only minimal
probe when a specific fork difference needs investigation. The runner accepts
multiple explicit builds for that occasional investigation.

## Reproduce

```text
cmake -S tools/experiments/runtime -B build-pool-fork -DGOOSE_SOURCE_DIR=/path/to/compatible/goose
cmake --build build-pool-fork --config Release --parallel
ctest --test-dir build-pool-fork -C Release --output-on-failure
python tools/buffer_storage_experiment.py --build build-pool-fork
python tools/buffer_storage_experiment.py --build build-pool-fork --documents 64 --rounds 48 --chunk-bytes 1024 --chunk-bytes 4096 --chunk-bytes 16384
```

Defaults are 3/16/64 buffers, 256-byte steps, 64 rounds, 4096-byte chunks, all
three workloads and three independent processes per case. Each chunk-size
comparison records all three policies: 81 default processes. `--mode` selects
one or more of `geometric`, `chunked`, `indexed`; selecting `--mode chunked`
and `--mode indexed` focuses on the directory comparison. Results go to a new directory
under the first build's ignored `experiments/`; `--output` selects another new
directory. The manifest stores revisions/diffs, compiler and executable hashes,
copied sources, native C configuration, commands, raw CSV, checkpoints,
percentiles and sampled process peaks. Schema 2 also records the indexed program's
hash, copied library/contract sources, and reserved directory/freelist capacity.
It refuses to overwrite existing results.

## Equal work and independent lifetimes

| Workload | Operations |
| --- | --- |
| `uniform` | Every buffer appends `step` bytes each round |
| `mixed` | Buffer `i` appends `step * (i % 4 + 1 + round % 2)`; buffer sizes remain different and requests alternate |
| `churn` | The mixed growth phase, close even-numbered buffers, then reopen those slots for `max(1, rounds / 2)` rounds; odd-numbered buffers remain live |

After initial growth and reopening, the experiment reads 64 deterministic
positions per live buffer, using `(sample * 7919 + buffer * 101) % used_bytes`.
Cleanup closes even-numbered buffers and then odd-numbered ones rather than
following stack order. A final full-pool allocation must reuse the entire freed
storage without increasing high-water and must be initialized to zero.
The library instead fills its freed chunk slots through new buffer IDs, checks
the whole arena and closes them. Reuse work is excluded from the trace counters
in every policy. Old IDs must remain invalid when indexed slots are reopened.

Every buffer has a distinct byte pattern. Reopening changes its pattern; full
payload and unused-capacity checks detect stale contents and interference with
surviving buffers. Verification runs after growth/reopening and after each close.
The Python runner independently computes every row's expected logical length,
capacity policy, allocation/free counts, initialization volume, metadata-slot
count and address visits. Missing rows, different logical work or failed cleanup
cannot become a successful result. The CTest fixture also checks rejected input,
truncated logs and refusal to overwrite a record.

## What is measured

The geometric policy requests `max(required, old_capacity * 2)`. The chunk policy
keeps every allocated chunk at `chunk_bytes`; appends can fill the tail and then
allocate multiple chunks. Neither policy materializes a whole buffer for a
contiguous consumer. `moved_capacity_bytes` is inferred from changed run offsets
and old capacity. Chunks never relocate existing payload. `zeroed_bytes` counts
the logical initialization volume of all newly allocated capacity, including
reopening; it is not physical stores or committed pages.

Allocator durations sum only the `alloc_slice`, `realloc_slice` or `free_slice`
calls. Slot management, policy computation, payload checks/writes, range sorting
and CSV output are outside those timers. An `append_alloc` row may aggregate
multiple calls; use `alloc_calls` for the call count. A reserved append has no
allocator duration. `read_probe` times addressing, counters and value assertions,
and is reported separately. Its few samples are not a tail-latency study.

Indexed `append_library`, `close_library` and `reuse_library` rows time full
library operations, including bookkeeping and payload writes where applicable.
They are deliberately distinct from allocator-only control rows. Their logical
allocation/release counters count arena chunk slots, not native pool calls.
Compare deterministic copying/address visits on equal work; these different
operation timers do not justify an allocator speed ranking.

CSV separates logical bytes, retained capacity, pool high-water, free bytes and
largest free run. Chunk descriptors carry a slice, stored offset and next index;
each buffer also needs head/tail indices. A free-slot list allows descriptor reuse
without moving payload. Metadata is counted in live and high-water slots, not
native bytes. Both modes share a binary containing the fixed 4096-slot table;
process RSS cannot isolate the metadata overhead of this representation.

The indexed Store is in a separate binary. Its 32,768 reserved directory entries
and 4,096 freelist entries consume 147,456 raw `i32` entry bytes, excluding buffer
fields, length headers and native padding. Live/peak chunk slots remain in the
CSV; the reserved entry counts are separate manifest metadata. Direct lookup
removes chain traversal by paying that fixed metadata cost, including at small
buffer counts. Both binaries remain headless and need no native lab services.
The separate [library qualification](../buffer/indexed.md#validation) measures
the full fixed Store layout as 148861 bytes on Windows x64/MSVC, including fields,
length headers and the tail header. It also runs the default 4096-chunk/16 MiB
arena to saturation and 810000 flat-model operations at three optimization levels.
These checks extend correctness coverage without changing this trace's timers.

The table bound and 128 MiB pessimistic allocation envelope are experiment
policies. The runner checks them before creating a record or starting a program;
the Goose entry point checks them as well. Indexed requests also must fit the
library's 512 entries and 2 MiB per buffer. The library guarantees whole-request
quota refusal, independently checked by its contract; OS allocation failure is
still fatal. Control offset fields preserve the workaround documented in
the [pool contract experiment](pool-runtime.md).

## Interpretation for Goose

The three-policy record used clean lab `2e523e0` and the clean compatible fork
`c2ecb4421facdc6476214606b67488df93eaa033` on Windows/MSVC Release. The default
81 processes and the 81-process 48-round 64-buffer chunk-size comparison all
passed the independent oracle, payload/spare-byte assertions and cleanup/reuse.
They ran on one toolchain. Ignored manifests are
`local/references/buffer-storage/indexed-library-run/results.json` and
`local/references/buffer-storage/indexed-library-48-run/results.json`.

For the default 64-buffer mixed workload, the indexed library and linked control
both retain 3,145,728 payload/capacity bytes and 768 peak chunk slots, with zero
payload relocation. Their 4,096 reads perform 4,096 and 26,219 directory/chain
visits respectively. With close/reopen, this becomes 8,192 versus 47,437 visits
for 8,192 reads; both remain at 768 peak chunk slots and fully reuse the arena.
The library adds 147,456 raw fixed directory/freelist bytes per Store, so reduced
traversal alone is not a total-memory or speed result.

For 64 mixed buffers at 48 rounds, logical payload is 2,359,296 bytes:

| Chunk bytes | Retained payload capacity/high-water (linked and indexed) | Peak chunk slots | Linked visits for 4,096 reads | Indexed visits |
| ---: | ---: | ---: | ---: | ---: |
| 1,024 | 2,359,296 | 2,304 | 74,732 | 4,096 |
| 4,096 | 2,490,368 | 608 | 20,320 | 4,096 |
| 16,384 | 2,883,584 | 176 | 6,795 | 4,096 |

Direct indexing removes the traversal penalty as chunks become smaller. Smaller
chunks still require more allocations, directory slots and close operations;
metadata reservations remain fixed in this bounded library. The geometric
control retains 3,145,728 capacity bytes at a 3,244,032-byte pool high-water,
with 3,088,384 inferred moved-capacity bytes. This is evidence for a library
representation alternative using existing Goose, not a requirement for a new
allocator, move operation or independent dynamic stack.

The historical two-policy record on Windows/MSVC Release, lab `ead001f` and fork
`77653e48f3e3db0853f439014ce58e80df3de41d` completed the default 54 processes
on one toolchain: 3/16/64 buffers, uniform/mixed/churn, both policies and three
repeats. Every row passed the independent oracle and payload/lifetime assertions.
The ignored record is `local/references/buffer-storage/current-fork-run/results.json`.

For 64 mixed buffers, both policies retained 3,145,728 bytes of payload/capacity:

| Policy | Pool high-water bytes | Inferred moved capacity bytes | Peak metadata slots | Address visits for 4,096 reads |
| --- | ---: | ---: | ---: | ---: |
| Geometric | 3,244,032 | 3,088,384 | 0 | 4,096 |
| 4,096-byte linked chunks | 3,145,728 | 0 | 768 | 26,219 |

With closing and reopening, chunk metadata still peaked at 768 slots, while
address visits grew to 47,437 for 8,192 reads; geometric addressing used 8,192
visits and inferred relocation reached 3,719,168 bytes. These deterministic
counters establish the copying/addressing tradeoff, not a platform speed ranking.

Compare copying, capacity and high-water with metadata and addressing together.
Smaller chunks can reduce unused capacity while increasing allocator calls,
descriptors, cleanup work and linked-list traversal. Larger chunks reverse that
tradeoff. The linked-list lookup cost is a representation choice: an indexed
table now supplies the direct-lookup comparison using existing Goose. A pooled
tree remains the next comparison for edit sharing and independent Undo.

This trace tests append storage and independent lifetimes. The indexed library's
separate contract also covers generation-checked handles, overwrites, shrinking,
owned export and quota refusal. Neither is a text-edit/Undo, timed contiguous
consumer, recoverable OS allocation, OS-memory release or long-session RSS study.
It provides no requirement for general move or independent dynamic stacks by
itself. Proposals need evidence of the remaining cost after library alternatives
have been compared.
