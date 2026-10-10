# Geometric runs and fixed chunks in Goose

This experiment asks whether existing Goose slice pools can avoid relocation
copying while retaining independently lived buffers. It compares a geometric
contiguous run with a linked list of fixed-size chunks on the same deterministic
workload. Both implementations use only `std` and `os` in
[`buffer_storage.goose`](../../tools/experiments/runtime/buffer_storage.goose).

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
comparison also records a geometric control. Results go to a new directory
under the first build's ignored `experiments/`; `--output` selects another new
directory. The manifest stores revisions/diffs, compiler and executable hashes,
copied sources, native C configuration, commands, raw CSV, checkpoints,
percentiles and sampled process peaks. It refuses to overwrite existing results.

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

CSV separates logical bytes, retained capacity, pool high-water, free bytes and
largest free run. Chunk descriptors carry a slice, stored offset and next index;
each buffer also needs head/tail indices. A free-slot list allows descriptor reuse
without moving payload. Metadata is counted in live and high-water slots, not
native bytes. Both modes share a binary containing the fixed 4096-slot table;
process RSS cannot isolate the metadata overhead of this representation.

The table bound and 128 MiB pessimistic allocation envelope are experiment
policies. The runner checks them before creating a record or starting a program;
the Goose entry point checks them as well. They do not implement transactional
runtime allocation failure. Offset fields preserve the workaround documented in
the [pool contract experiment](pool-runtime.md).

## Interpretation for Goose

On Windows/MSVC Release, lab `ead001f` and the clean compatible fork
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
table or pooled tree is an appropriate next comparison using existing Goose.

This tests independent buffer storage and lifetimes, not text edits, Undo,
generation-checked public handles, contiguous-consumer materialization,
recoverable allocation, OS-memory release or long-session RSS stability.
It provides no requirement for general move or independent dynamic stacks by
itself. Proposals need evidence of the remaining cost after library alternatives
have been compared.
