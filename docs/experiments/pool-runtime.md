# Goose slice-pool contracts and growth policy

The next question is which independently owned buffer problems existing Goose
already solves, and which require a library, compiler or runtime change. This
experiment isolates slice pools from document history, capacity preflight, GUI,
FFI adapters and fork-only module APIs. It is a separate CMake project using
[`pool_runtime.goose`](../../tools/experiments/runtime/pool_runtime.goose), which
imports only `std` and `os`. The same source runs on explicitly selected upstream
and fork checkouts without changing those checkouts.

## Reproduce on the compatible toolchain

Routine validation uses one upstream-tracking fork, as described in
[toolchain requirements](../toolchain.md). A separate upstream build is only
needed to investigate a specific difference. Multiple explicit builds remain
supported for those focused comparisons; the recorded two-revision example below
is a historical measurement, not a requirement to repeat both every time.

```text
cmake -S tools/experiments/runtime -B build-pool-fork -DGOOSE_SOURCE_DIR=/path/to/lab-toolchain
cmake --build build-pool-fork --config Release --parallel
ctest --test-dir build-pool-fork -C Release --output-on-failure
python tools/pool_runtime_experiment.py --build build-pool-fork
```

Optional native modules and JIT are disabled. No renderer or lab adapter is linked.
Each project registers four pool checks: runtime semantics, the descriptor diagnostic,
isolated reservation exhaustion, and a runner/accounting smoke check, plus the
[buffer storage comparison](buffer-storage.md). This validates the selected revision,
not arbitrary future upstream versions or the whole Workbench on upstream.

The runner runs correctness and diagnostic probes before timing. Defaults are
3/16/64 buffers, 256-byte appends, 64 rounds and three independent processes per
case. All growth interleaves buffers. Modes are exact requested capacity and
geometric capacity (`max(required, old_capacity * 2)`). To expose unused capacity
at a non-power-of-two endpoint, run `--documents 64 --rounds 48` as well. Total
logical append work is identical between modes. Release order is reversed and
a final full-pool allocation verifies reuse and zero initialization.

`--output` names a new directory; default results are under the first build's
ignored `experiments/<UTC timestamp>/`. The manifest contains fixed revisions,
dirty state/diffs, compiler/program/source hashes, copied sources, C flags and
environment, exact commands, contracts, diagnostic logs, raw CSV and operation
percentiles/totals. Local measurements belong under ignored `local/` or builds.
The trace's pessimistic sum of requested capacities is limited to 128 MiB to
stay below the selected default 256 MiB runtime reservation; this is a finite
test envelope, not a recoverable-allocation API. Custom smaller reservation builds
need a correspondingly smaller envelope.

## Semantics verified

- Growth that relocates preserves old payload and initializes gained bytes to zero.
- Other buffers remain unchanged during interleaved growth.
- A view made before relocation keeps its old range. It does not follow the buffer.
  A later allocation can zero and overwrite that range, and the old view observes
  those new values. The same applies to a closed and reused run.
- Adjacent freed runs merge; fragmented free space may be larger in total than a
  request while no one run satisfies it. The test frees two separated 16-byte
  holes and requests 32 bytes; high-water must grow. After merging, space is reused.
- Freeing all runs does not shrink the pool high-water length. Allocation can reuse
  that storage, with default initialization, without growing it again.

These establish memory/type validity rather than document identity. Generation
IDs remain a library responsibility when old asynchronous results must be rejected.
No assertion expects an old pool slice to become invalid after freeing its run.

## Compiler constraint captured separately

[`index_of_descriptor.goose`](../../tools/experiments/runtime/index_of_descriptor.goose)
is an intentionally rejected minimal example. A slice returned by `alloc_slice`
can immediately be passed to `index_of`, but a slice read from a global descriptor
may be attributed to more than one eligible global byte array, including the
`argv_text` storage used by `args()`. The recorded compilers refuse `index_of`
on that read with a pool-root diagnostic. `realloc_slice`/`free_slice` can still
operate on descriptor slices using their runtime origin check.

The positive trace records the numeric offset immediately after allocation or
reallocation, when the checker still knows the pool. It adds one field and an
update to each relocation. The diagnostic test preserves the rejected form and
checks its specific reason. If a future compiler accepts it, investigate that
change and update the expected contract explicitly.

This is material for a pool-provenance representation or analysis improvement.
It is not evidence that descriptors cannot hold buffers, or that arbitrary move
or independent dynamic stacks are necessary. A pool-qualified slice type and a
range-checked index query are possible comparison points, not implemented APIs
or a decided language proposal.

## Reservation exhaustion is a different failure

[`reservation_exhaustion.goose`](../../tools/experiments/runtime/reservation_exhaustion.goose)
is compiled separately with a 1 MiB `GS_STACK_RESERVE`. A single 2 MiB request
terminates with `invalid slice length`; two live 768 KiB runs exceed the pool's
aggregate reservation and terminate with `data stack overflow`. The fixture runs
both as isolated children and requires nonzero exits and their specific diagnostics.
Neither allocation returns a failure value to its caller. The measurement manifest
records those classified failures, the executable hash and reservation setting. This observes the selected
runtime's reservation boundary, not general OS-memory exhaustion or preserved
application state after failure. A `try`-allocation proposal would still need
an implementation and tests for preserving the old run on failed reallocation.

## Measurements and interpretation

CSV separates logical payload, allocated capacity, pool high-water, free storage
and largest free run. Logical payload plus unused buffer capacity differs from
free storage between runs. `moved_capacity_bytes` is inferred from changed run
offsets and old allocated length; it describes the payload moved by this runtime
implementation, not an instrumentation counter or total process copying.
`zeroed_growth_bytes` counts gained elements' initialization volume, not physical
stores or page commitment. `application_write_bytes` records explicit appends.
Counters cover the growth workload; local contract pools and the reuse probe are
excluded. OS peaks are sampled through the existing optional memory helper.

Reallocation duration includes the capacity-policy decision, origin check and
runtime call. It ends before updating metadata, checking payload, filling appended
bytes, collecting stats or writing CSV. Appending within reserved capacity calls
no allocator and has a blank duration. Compare allocation counts and summed call
times alongside percentiles: a geometric call can move more bytes at once while
performing far fewer calls. Short calls are limited by timer resolution. Process
wall time includes validation and observation and is not an allocator-only measure.

Compare buffer lifetimes and storage fields across revisions before interpreting
timing differences. Equal placement/copy counters show the same observable trace,
not equivalence of the compilers in general. A growth-policy reduction in copying
is a library-policy result obtainable with existing Goose. Unused capacity and
high-water retention remain tradeoffs; measure several stopping points and mixed
buffer sizes before deciding a policy is universally preferable.

## Recorded example: 2026-10-11

Windows 11 x64 / MSVC Release, with fork
`a6e8543a1017724d8da784585927264f9e324aa2` and upstream
`35368105e3d50341b79a4cb873cc0261e82dfa42`, both clean checkouts. These are the
selected local revisions, not a claim about the latest remote versions. All four
CTest checks passed on each. The default trace (36 processes) and the 64-buffer,
48-round trace (12 processes) produced identical non-timing CSV fields between
the two revisions at every corresponding operation.

Each buffer appends 256 bytes per round. The figures below describe the growth
endpoint for 64 buffers; each configuration was repeated in three fresh processes.

| Rounds | Policy | Logical bytes | Capacity bytes | High-water bytes | Inferred moved capacity bytes | Reallocation calls |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 64 | Exact | 1,048,576 | 1,048,576 | 1,303,040 | 28,641,536 | 4,096 |
| 64 | Geometric | 1,048,576 | 1,048,576 | 1,048,576 | 1,032,192 | 448 |
| 48 | Exact | 786,432 | 786,432 | 958,208 | 16,659,712 | 3,072 |
| 48 | Geometric | 786,432 | 1,048,576 | 1,048,576 | 1,032,192 | 448 |

The reduction in copying and allocation calls needs only a capacity policy in
existing Goose. At 48 rounds, geometric growth retains 262,144 bytes of unused
capacity and has a larger high-water footprint than exact growth. This is a
tradeoff rather than a universal winner. Freeing/reusing storage, compiler
provenance rejection and fatal reservation exhaustion were independently checked
on both revisions. These results do not establish OS-memory release or
recoverable allocation.

## Next investigations for Goose

| Question | Next comparison | Evidence needed for a proposal |
| --- | --- | --- |
| Can existing storage avoid relocation costs? | Fixed chunks versus geometric runs; then pooled persistent trees with the document oracle | Payload copying, retained capacity, addressing/metadata and authoring burden at equal logical work |
| Can failures be handled without allocator duplication? | Bounded wrapper versus runtime query/try-allocation prototype | Preserved old runs and data, classified failure, library bookkeeping and rejection cost |
| Can pool belonging be expressed naturally? | Stored offsets versus a compiler/type/query experiment | This rejected minimal source, accepted counterpart and extra metadata/checks each needs |
| Is releasable independent storage necessary? | Repeated growth/free, mixed sizes, high-water and actual commit | OS/runtime retention that capacity policy and chunks cannot resolve |

Keep runtime/language proposals separate from application features. This experiment
does not test Undo, endpoint isolation, fault-injected native cleanup, exact runtime
reservation/commit, recoverable allocation, long-session RSS stability or portability
outside the measured platform.
