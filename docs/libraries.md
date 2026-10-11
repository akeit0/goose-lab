# Library map

Modules are grouped by capability, with paths and namespaces that mirror their
location. For example `import lab.net.http;` uses `lab_net_http`; file editing is
`lab.document.model` / `lab_document_model`. UI rendering is `lab.ui.render.font`
/ `lab_ui_render_font`.
See [architecture and dependency boundaries](architecture.md).
For choosing a representation, see [useful storage and lifetime patterns](goose-patterns.md).

| Import prefix | Modules under that prefix | Native target / guide |
| --- | --- | --- |
| `lab.buffer` | [`indexed`](../lib/lab/buffer/indexed.goose), [`slot_arena`](../lib/lab/buffer/slot_arena.goose) | Pure Goose; [indexed storage](buffer/indexed.md), [variable slot arena](buffer/slot-arena.md) |
| `lab.collections` | [`byte_buffer`](../lib/lab/collections/byte_buffer.goose), [`tree`](../lib/lab/collections/tree.goose), [`state_bank`](../lib/lab/collections/state_bank.goose) | Pure Goose |
| `lab.text` | [`utf8`](../lib/lab/text/utf8.goose), [`grapheme`](../lib/lab/text/grapheme.goose), [`line_break`](../lib/lab/text/line_break.goose), [`strings`](../lib/lab/text/strings.goose), [`line_index`](../lib/lab/text/line_index.goose), [`literal_search`](../lib/lab/text/literal_search.goose), [`selection`](../lib/lab/text/selection.goose), [`diff`](../lib/lab/text/diff.goose) | Pure Goose; [text foundation](ui/text-foundation.md) |
| `lab.json` | [`codec`](../lib/lab/json/codec.goose), [`edit`](../lib/lab/json/edit.goose), [`file`](../lib/lab/json/file.goose) | `file` needs `goose_lab_files`; [JSON](data/json.md) |
| `lab.io` | [`admission`](../lib/lab/io/admission.goose), [`event_loop`](../lib/lab/io/event_loop.goose), [`cancel`](../lib/lab/io/cancel.goose), [`stream`](../lib/lab/io/stream.goose), [`process`](../lib/lab/io/process.goose), [`process_stream`](../lib/lab/io/process_stream.goose), [`console`](../lib/lab/io/console.goose), [`timer`](../lib/lab/io/timer.goose), [`debounce`](../lib/lab/io/debounce.goose) | `admission` is pure Goose; `goose_lab_loop`, `goose_lab_cancel`, `goose_lab_process`, `goose_lab_console`; [I/O](io/io-core.md), [streams](io/streams.md) |
| `lab.fs` | [`path`](../lib/lab/fs/path.goose), [`glob`](../lib/lab/fs/glob.goose), [`files`](../lib/lab/fs/files.goose), [`async_files`](../lib/lab/fs/async_files.goose), [`watch`](../lib/lab/fs/watch.goose), [`storage`](../lib/lab/fs/storage.goose), [`explorer`](../lib/lab/fs/explorer.goose), [`search`](../lib/lab/fs/search.goose), [`search_client`](../lib/lab/fs/search_client.goose), [`search_clients`](../lib/lab/fs/search_clients.goose), [`search_codec`](../lib/lab/fs/search_codec.goose) | `goose_lab_path`, `goose_lab_files`, `goose_lab_loop`, `goose_lab_watch`; [files](io/async-files.md), [search streams](io/streams.md) |
| `lab.net` | [`http`](../lib/lab/net/http.goose), [`http_clients`](../lib/lab/net/http_clients.goose) | `goose_lab_http`; [transport](design.md#http), [independent clients](io/http-clients.md) |
| `lab.git` | [`repository`](../lib/lab/git/repository.goose), [`batch`](../lib/lab/git/batch.goose), [`client`](../lib/lab/git/client.goose), [`history`](../lib/lab/git/history.goose), [`object`](../lib/lab/git/object.goose), [`tree`](../lib/lab/git/tree.goose) | Process/file/loop services; [Git](apps/git-viewer.md) |
| `lab.document` | [`model`](../lib/lab/document/model.goose), [`piece_tree`](../lib/lab/document/piece_tree.goose), [`store`](../lib/lab/document/store.goose), [`file`](../lib/lab/document/file.goose), [`close`](../lib/lab/document/close.goose), [`workspace`](../lib/lab/document/workspace.goose) | Pure editing or asynchronous file services; [document](apps/text-editor.md), [shared Store](document/store.md) |
| `lab.ui` | [`geometry`](../lib/lab/ui/geometry.goose), [`command`](../lib/lab/ui/command.goose), [`view`](../lib/lab/ui/view.goose); see subgroups below | [UI composition](ui/ui-composition.md) |
| `lab.ui.layout` | [`engine`](../lib/lab/ui/layout/engine.goose), [`scroll`](../lib/lab/ui/layout/scroll.goose), [`viewport`](../lib/lab/ui/layout/viewport.goose) | `engine` needs `goose_lab_layout`; [layout](ui/layout.md) |
| `lab.ui.input` | [`interaction`](../lib/lab/ui/input/interaction.goose), [`composition`](../lib/lab/ui/input/composition.goose), [`shortcuts`](../lib/lab/ui/input/shortcuts.goose) | [IME](ui/ime.md) |
| `lab.ui.render` | [`font`](../lib/lab/ui/render/font.goose), [`text_layout`](../lib/lab/ui/render/text_layout.goose), [`scene`](../lib/lab/ui/render/scene.goose) | `goose_lab_text`; `scene` also needs `goose_lab_scene` and Goose gfx; [text](ui/text-layout.md) |
| `lab.ui.controls` | [`components`](../lib/lab/ui/controls/components.goose), [`field`](../lib/lab/ui/controls/field.goose) | Shared styles/painting and editable fields; [composition](ui/ui-composition.md) |
| `lab.ui.views` | [`text`](../lib/lab/ui/views/text.goose), [`editor`](../lib/lab/ui/views/editor.goose), [`tree`](../lib/lab/ui/views/tree.goose) | Views over shared models; [editor](apps/text-editor.md), [trees](ui/tree-view.md) |
| `lab.ui.overlays` | [`modal`](../lib/lab/ui/overlays/modal.goose), [`palette`](../lib/lab/ui/overlays/palette.goose) | [Modal/palette](ui/command-palette.md) |

`lab.text.internal.grapheme_data` is generated implementation data, not an
application-facing API. Every library module stays independent of `samples` and `tools`.
Sample models/controllers use paths such as `api_browser.browser` or
`workbench.editor.workspace`; their matching flat namespaces are `app_api_browser`
and `app_editor_workspace`.

Native plain C headers stay independent of compiler-generated runtime types.
Their neighboring glue headers adapt slices/builders only inside the generated
translation unit. `native/goose_lab.h` selects adapters through feature definitions
provided by the linked targets. See [architecture](architecture.md#native-code).

## Ownership and execution

[`lab.io.admission`](../lib/lab/io/admission.goose) is a pure Goose bounded demand
queue for round-robin admission across separate owners. It keeps fixed domain/key
records rather than request payloads or native resources; see
[shared capacity and reuse](io/mixed-services.md#fair-host-admission-and-repeated-reuse).

[`lab.buffer.slot_arena`](../lib/lab/buffer/slot_arena.goose) stores variable byte
values in caller-assigned slots with hole reuse and deferred compaction. Its
caller supplies logical identity/generation; it needs no native target. See the
[slot arena guide](buffer/slot-arena.md).

[`lab.buffer.indexed`](../lib/lab/buffer/indexed.goose) provides independent
generation-checked byte buffers in an explicit caller-owned Store, using a chunk
directory and library freelist. It needs no native target; see
[indexed buffers](buffer/indexed.md) for bounds, ownership and representation costs.

Use owned arrays for stored/queued data and borrowed slices for synchronous calls.
Never retain pointers into Goose values in native state. Configure font families
before measurement seals them. Close dependent layouts before their font family.
Native handles must have one explicit owner; copying an integer handle does not
transfer ownership or create another resource.

Application workers exchange owned typed messages. Cancellation and request
serials have distinct jobs: stop obsolete work and reject obsolete completions.
Event-loop operations have bounded queues/buffers and explicit completion/cancel/
close paths. Poll or wait at application boundaries rather than hiding a second
event loop in a component.

Keep application reducers out of `lib/lab`. Promote a utility when another caller
needs the same contract. Shared primitives should expose typed state and operations
rather than accepting an application model or silently owning global resources.

## Build boundary

Native target declarations live in `native/io`, `native/fs`, `native/net` and
`native/ui`. Pinned dependency configuration is in `cmake/NativeDependencies.cmake`;
font defaults are in `cmake/Fonts.cmake`. `cmake/GoosePrograms.cmake` provides
public application helpers. Samples and contract registration remain separate.
Choose native targets with `goose_lab_program(... LIBRARIES ...)`; use
`goose_lab_gui_program` for layout, scene and Goose gfx together.
