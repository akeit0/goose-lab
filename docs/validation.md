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

With samples and tests enabled, the GUI configuration registers 23 checks and
the GUI-free configuration registers 10. Enabling manual tools adds the
`document_experiment_smoke` check. Tests use loopback HTTP/TLS fixtures,
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
| [Independent document contract](../tests/multi_document_contract.goose) | 3/16/64 pooled documents, independent Undo/selection/saved state, actual save success/failure, stale generations, budgets and 700-operation model comparison |
| [HTTP fixture](../tests/http_fixture.py), [native cancellation](../tests/cancel_contract.c) | TLS/redirect/byte limits, cancellation and handle lifetimes |
| [JSON corpus](../tests/json_corpus.py) | Independent decoding, round trips and malformed/bounded inputs |
| [Workbench fixture](../tests/workbench_fixture.py) | Edit/save/Git/search navigation, tabs/cursor restoration, Help/modal routing, initial Git modes, a subdirectory workspace, dirty-close decisions, idle frames and resource ownership |
| [Git/file fixture](../tests/git_fixture.py) | Process streams, files/watches, atomic-save conflicts, Git history, search and editor interactions |
| [UI composition](../tests/view_contract.goose), [text/rendering](../tests/modern_contract.goose) | Ordered actions, focus, clipping, glyph geometry, unchanged GPU frames and cleanup |
| [API fixture](../tests/api_fixture.py), [task fixture](../tests/task_fixture.py) | Persistence, failed-load/save recovery and asynchronous result adoption |

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
