# Validation

The supported validation configuration is Windows x64, MSVC Release with the
compatible Goose fork described in [toolchain requirements](toolchain.md).
Other platforms have not been validated.

The separate [pool runtime experiment](experiments/pool-runtime.md) builds a
standard-module-only probe against an explicitly selected upstream or fork
checkout. Its four checks cover pool semantics, a recorded compiler diagnostic,
isolated reservation exhaustion and the measurement runner; they are separate
from the main configuration below. It also registers the
[buffer storage comparison](experiments/buffer-storage.md). Routine checks use
one upstream-tracking compatible fork; a separate upstream run is reserved for
investigating a relevant difference.

```text
cmake -S . -B build -DGOOSE_SOURCE_DIR=/path/to/compatible/goose
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure

cmake -S . -B build-core -DGOOSE_SOURCE_DIR=/path/to/compatible/goose -DGOOSE_LAB_GUI=OFF
cmake --build build-core --config Release --parallel
ctest --test-dir build-core -C Release --output-on-failure
```

With samples and tests enabled, the GUI configuration registers 28 checks and
the GUI-free configuration registers 15. Enabling manual tools adds the
`document_experiment_smoke` and `document_store_experiment_smoke` checks. Tests use loopback HTTP/TLS fixtures,
temporary Git repositories and temporary files. Python fixtures do not contact
public services. The checked-in TLS key is only a localhost test fixture.

Coverage includes cancellation races/lifetimes, JSON corpora, Unicode 17 grapheme
boundaries, process streams, atomic writes, watches, Git models and application
interaction. UI checks exercise DPI scales, selection/caret behavior, IME events,
modals, tree views, resource cleanup and rendering screenshots. Headless rendering
still requires a working GPU/backend; it is not a software renderer.

| Check sources | Main coverage |
| --- | --- |
| [Utility contract](../tests/utils_contract.goose) | Piece-tree edits against a flat-string oracle, live-root collection, Unicode boundaries and pure utilities |
| [Indexed buffer contract](../tests/indexed_buffer_contract.goose) | 3/16/64 independent buffers, flat-array oracle, multi-byte writes, stale IDs, two Stores, whole-request refusal, owned exports and 4096-chunk saturation/reuse |
| [Slot arena contract](../tests/slot_arena_contract.goose), [flat Python model](../tests/slot_arena_fixture.py) | 27000 variable-value operations at 3/16/64 slots, all payloads checked after each operation, holes/overlap/compaction, unchanged refusal, owned exports and 4 MiB saturation/reuse |
| [Persistent document Store](../tests/document_store_contract.goose) | Explicit owners, shared current/saved/Undo/Redo roots, 3/16/64 flat-model comparison, cross-piece edits, collection/remapping, stale IDs and failure preservation |
| [Independent document contract](../tests/multi_document_contract.goose) | 3/16/64 pooled documents, independent Undo/selection/saved state, actual save success/failure, stale generations, budgets and 700-operation model comparison |
| [HTTP fixture](../tests/http_fixture.py), [native cancellation](../tests/cancel_contract.c) | TLS/redirect/byte limits, cancellation and handle lifetimes |
| [HTTP clients](../tests/http_clients_contract.goose), [client fixture](../tests/http_clients_fixture.py) | 3/16/64 independent generations/serials, barrier-controlled concurrency, cancel/close/reopen, retired results, binary ownership, bounded mailboxes and full shutdown cleanup |
| [Stream/ACK contract](../tests/stream_contract.goose), [real search](../tests/search_stream_contract.goose), [independent fixture](../tests/stream_fixture.py) | Typed ACK isolation, stalled consumers, 100 ACK/Cancel races, retired pages, bounded shutdown, 3/16/64 streams, flat-file positions/previews, compact codec, byte/compaction oracles and native handle reacquisition |
| [JSON corpus](../tests/json_corpus.py) | Independent decoding, round trips and malformed/bounded inputs |
| [Workbench fixture](../tests/workbench_fixture.py) | Edit/save/Git/search navigation, tabs/cursor restoration, Help/modal routing, initial Git modes, a subdirectory workspace, dirty-close decisions, idle frames and resource ownership |
| [Git/file fixture](../tests/git_fixture.py) | Process streams, files/watches, atomic-save conflicts, Git history, search and editor interactions |
| [Graphics package contracts](../tests/gfx) | Deferred close, on-demand presentation, screen/content revisions, ordered wheel, UTF-8 preedit/commit, token expiry and legacy scalar input |
| [UI composition](../tests/view_contract.goose), [text/rendering](../tests/modern_contract.goose) | Ordered actions, focus, clipping, glyph geometry, unchanged GPU frames and cleanup |
| [API fixture](../tests/api_fixture.py), [task fixture](../tests/task_fixture.py) | Persistence, failed-load/save recovery and asynchronous result adoption |

Long byte-buffer qualification uses `tools/indexed_buffer_qualification.py`,
separately from the fast CTest contract. Its default is 810000 model operations
across three seeds, 3/16/64 buffers and Goose `-O0/-O1/-O2`, plus full default-arena
saturation and reuse in every process. It records one selected toolchain and
measures its generated Store layout; see the [buffer guide](buffer/indexed.md).

The stricter joined-emoji check needs the optional reference font:

```text
python tools/fetch_emoji_font.py
python tools/run.py modern_contract tools/unicode/GraphemeBreakTest.txt build/fonts/Twemoji.Mozilla.ttf --joined
```

See [emoji](ui/emoji.md) for font coverage and licensing. Generator output uses pinned,
digest-checked Unicode data; `python tools/generate_grapheme.py` should leave the
generated tables unchanged.

When changing public build helpers, also configure/build an external CMake project
that adds this repository as a subdirectory with samples/tests disabled, imports
`lab.*`, and links its chosen native target. This checks module/glue paths outside
this project's source directory. Local results and logs belong under `local/`.

Toolchain capability probes run once before generating Goose applications. When
changing them, also check rejection against an incompatible compiler; it should
report the missing core/GUI feature before compiling application C. The probes
only generate C and do not execute graphics or native-resource operations.

For dependency refactors, also check narrow consumers: `lab.fs.path` linked only
with `goose_lab_path`, and separate C clients of `goose_lab_text` and
`goose_lab_scene`. Font shaping should not require scene-cache symbols; scene
comparison should not require font libraries or SDL. Both clients use canonical
native header paths and must return their native allocation counters to zero.

## Graphics package separation (2026-10-11)

Compiler `71e848d732362a47ee7fe000a3e1601d0196259a` merges upstream
`4f23f22629a34d971adbd8c10017d203ab6bb2fa`. Graphics/audio source now lives directly
in `packages/gfx`; there is no goose_gfx submodule or build-time patch. SDL is a
lab dependency; the unused Nuklear UI layer is omitted. Compiler link inputs and
the core target graph contain neither SDL nor graphics targets.

Windows/MSVC Release validation covers the full 33 GUI contracts (including the
two-layer C/Goose API check), 17 core/tool checks, module-root and native-adapter
compiler checks, and external core/GUI consumers with samples/tests disabled.
The external core consumer links only the path service; the GUI consumer imports
lab UI, exercises UTF-8 text transactions and recursive relative imports, and
preserves UTF-8 BOM handling and literal `@placeholder@` source text. Separate
text/scene C clients link no SDL, use canonical native headers and release all
tracked allocations. An incompatible stock compiler is rejected by the core
capability probe before application generation. Four gfx fixtures
also passed native execution at Goose -O0/-O2; the inline-return regression
passed JIT at -O0/-O1/-O2, plus pool and two storage/reuse JIT smoke runs.

The compiler's baseline runner uses `PYTHONUTF8=1` on this cp932 host. It reports
3572 successful checks, including 492 native executions and 17 bootstrap checks,
with one remaining failure: the resource-path fixture cannot open the non-ASCII
`source space é/main.goose` path. Compiler argv/file loading is unchanged from
upstream. This is a recorded Windows limitation; the compiler baseline is not
claimed fully passing. Native package executions are skipped by that baseline
because no packages are built into the compiler; lab graphics are tested by the
contracts above. Native IME candidate-window placement still requires OS checks.
