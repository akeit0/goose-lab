# Independent document experiment

This is a GUI-free research baseline, implemented in
[`tools/experiments/pool_document.goose`](../../tools/experiments/pool_document.goose).
It tests whether existing Goose slice pools can retain independently editable
documents, selections, Undo/Redo and saved state, and measures the cost of that
representation. Workbench still uses its existing single-document editor.

## Reproduce

Use the compatible, explicitly configured toolchain in [toolchain requirements](../toolchain.md):

```text
cmake -S . -B build-core -DGOOSE_SOURCE_DIR=/path/to/compatible/goose -DGOOSE_LAB_GUI=OFF -DGOOSE_LAB_BUILD_TOOLS=ON
cmake --build build-core --config Release --parallel
ctest --test-dir build-core -C Release --output-on-failure
python tools/document_experiment.py --build build-core
```

The runner requires tests and tools enabled, runs the correctness contract first,
and starts a fresh process for each case/repetition. It records nine cases:
3/16/64 pooled documents, and paired one-document snapshot/Piece Tree runs for
short lines, one long line, and Japanese/combining-character/emoji text. Defaults
are 4,096 bytes per document, 64 editing rounds and three repetitions. To inspect
a larger paired case:

```text
python tools/document_experiment.py --build build-core --case snapshot-long-line --case piece-tree-long-line --size 65536 --iterations 128 --repeats 3
```

`--output` must name a new directory. Otherwise results go under the ignored
`build-core/experiments/<UTC timestamp>/`. `results.json` records the hypothesis,
comparison, revisions and dirty state, source/compiler/executable SHA-256 hashes,
build configuration/compiler flags, environment, exact commands, contract result,
raw CSV paths, sampled OS memory and median/p95/p99 by operation. Percentiles use
nearest rank without dropping slow samples. Source copies and tracked diff patches
preserve the experiment when its code is uncommitted. Modified experiment/model
sources newer than their executable require rebuilding first. Revisions describe
the local checkouts, rather than asserting compatibility with current upstream.

## Representation and contracts

A worker-local registry owns one `reusable[]` byte pool and up to 64 fixed-size
document descriptors. Each descriptor holds immutable full-text versions and a
separate saved baseline. The public functions take `{slot,generation}` IDs;
positions are UTF-8 byte offsets. `contents` and `baseline` return owned copies.
Pool slices stay internal. One registry per worker is a deliberate limitation;
this experiment does not establish independent registry instances.

Each successful edit allocates and writes one complete version. Undo and Redo
choose a retained version and restore the edit's selection and revision. Saved
bytes remain available even after dropping redo or evicting history. A no-op edit
does not change revision. There is no typing-group merging. Closing a document
frees every version and its saved run; reopening reuses the slot with a new
generation. Exhausted generations are retired rather than wrapping.

`mark_saved(id, expected_revision)` only adopts a successfully published current
version. It refuses stale IDs and old revision completions. The host remains
responsible for publication and error handling; this API is not an asynchronous
file service. The contract writes a real file atomically, reads it back, and
checks a failed write preserves dirty state. An old completion is rejected after
editing or closing/reusing its document. Adoption may return `LIMIT` even after
disk publication if a new baseline cannot fit: the caller must report that the
disk write succeeded while model adoption failed. Capacity is checked before
releasing the old baseline so failures preserve state.

Limits are 64 documents, 2 MiB per current text, 256 Undo entries and a 64 MiB
pool high-water budget (configurable downward). The profiler uses 32 Undo entries;
the existing Piece Tree comparison keeps its normal 256-entry limit. Runs with
more than 32 rounds therefore compare different history retention policies; use
at most 32 rounds when equal history length matters. `INVALID`, `LIMIT` and
`STALE` are separate results. Editing boundaries follow the existing UTF-8/CRLF
rules; grapheme navigation remains the caller's responsibility.

Before allocation, the baseline checks whether appending every requested run
fits inside the remaining high-water budget. When it does, no live-range scan
is needed. Otherwise it sorts all live byte ranges and simulates first-fit
placement, including the reusable tail. Two allocations for opening can occupy
different gaps. This enforces the high-water budget before the runtime allocator,
whose exhaustion is not recoverable. Only allocations under budget pressure pay
the O(retained versions log retained versions) library preflight. Sorting
temporary ranges and descriptor storage are outside the byte-pool budget.
This budget does not promise that unrelated process/native allocations cannot fail.

## Correctness and operation sequences

[`multi_document_contract.goose`](../../tests/multi_document_contract.goose) checks:

- Three simultaneously dirty documents; Undo/Redo and selection independent of
  the other two, real publication, saved baseline and saved-revision identity.
- Close A, reopen its slot, reject old edit/search and save-completion IDs;
  retain B and C and reject stale/duplicate close.
- Invalid UTF-8, NUL and CRLF-interior boundaries; document/pool budget refusal
  without editing state; bounded history, redo truncation and reuse after closing
  another document.
- A deterministic 700-operation comparison with the existing document model,
  covering text, baseline, selections, revisions and dirty flags, including history
  eviction and no-op edits.
- 20 rounds of arbitrary-order close/reopen/edit at 3, 16 and 64 documents,
  with Undo/Redo on every live document and zero owned bytes after close-all.

The profiler opens documents, replaces the first ASCII byte in each document,
Undoes/Redoes the change, adopts a saved baseline every eight rounds, then closes
and reopens slots in reverse order and finally closes all. Assertions verify the
final text and cleanup. The one-document Piece Tree case uses the same editing
and saved-state operations. It measures the existing tree, rather than a new
pooled tree or chunked implementation. It does not time switching a GUI tab.

## Interpret the measurements

Snapshot CSV separates current bytes, saved bytes and other retained versions
(`undo_bytes` includes redo). These are distinct owned allocations even when
their text matches. `used_bytes` is their sum; high-water minus used bytes is
free reusable storage. `largest_free_run_bytes` exposes fragmentation. After
close-all, used bytes are zero while high-water stays allocated: reuse and release
to the OS are different outcomes.

`copied_bytes` counts pool payload writes, including inserts and baseline copies;
`zeroed_bytes` counts the logical bytes initialized by `alloc_slice`. Neither
counts runtime allocator bookkeeping, fixed descriptors, exported owned copies
or measurement output. `preflight_scans` counts capacity checks that need the
sorted live-range fallback; observation through `stats` is excluded. Schema 2
adds this counter to the manifest/CSV. Piece Tree `used_bytes` counts its node/text
arena words;
it excludes inline history and temporary collectors. Missing pool/copy counters
are blank, not zero. These measures answer different questions and are not a
total-memory comparison. Operation timing ends before stats/CSV output; whole-run
time includes observation overhead. OS RSS/private bytes are sampled every 10 ms,
so short processes may have missing samples, and sampled peaks can miss spikes.
Runtime reservation/commit counters are not available in this experiment.

Full snapshots make even a one-byte edit copy the complete new text. The growing
range-preflight cost under budget pressure is a library implementation choice,
not proof that Goose's runtime pool itself scales poorly. The next representation comparisons should
be chunked storage and a pooled Piece Tree, using this same correctness oracle
and reporting which costs each removes. Only measured remaining problems justify
runtime allocation/observability or language proposals. No upstream change is
required to run this baseline.

This short experiment does not establish GUI shaping performance, idle waiting,
long-session RSS stability, Linux/macOS behavior, independent search clients or
resource fault-injection coverage. Detailed local measurements belong under
ignored `local/` or build directories; preserve the manifest with any conclusion.
