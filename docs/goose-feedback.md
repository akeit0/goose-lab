# Goose feedback from applications

Application experience suggests these patterns for Goose's value semantics,
isolated workers and explicit resource lifetimes. Checkout-specific investigations
belong in ignored local references.
The [pattern guide](goose-patterns.md) collects the reusable storage/lifetime
choices and measured tradeoffs; this page discusses application experience and
remaining language/API questions.

## Composing document and Git pages

The workbench combines two independently resizable values: a document/piece tree
and a Git diff byte buffer. They cannot both be embedded as fields of one `App`,
because Goose permits only one resizable tail. Keep each owner in a separate local
variable and pass references together with fixed-size coordination state. This
works without a heap allocator or pointers into movable Goose arrays.

Resource sharing must also be explicit. The editor owns one scene and its font
assets; the Git page borrows the font table and paints into that scene. Search
workers use typed queues, so two clients of the same protocol would compete for
messages. The host owns one search client and polls it even when its page is hidden.
The [workbench sample](apps/workbench.md) demonstrates these conventions.

Tabs expose another consequence of the same value model: an array cannot own
resizable `Document` elements. The current Workbench keeps a bounded array of
paths/cursor/scroll records and one document owner. Switching files follows an
explicit dirty-buffer decision and rereads bytes, so inactive tabs have no Undo
or unsaved buffer. This bounds resident document memory, but differs from an
editor with independently resident buffers. Multiple such buffers need a shared
arena with fixed-size document records, or separately owned stacks; merely
placing the existing document type in a tab array is not valid Goose v1.

The [independent-document experiment](experiments/independent-documents.md) now
uses existing `reusable[]` slice pools and fixed descriptors for 3/16/64 resident
buffers, independent Undo/saved state and generation-checked IDs. It is a headless
full-snapshot baseline, separate from Workbench's Piece Tree. The measurement
runner separates owned text/history, reusable/high-water storage and copy work;
its capacity preflight sorts live ranges only when append headroom cannot cover
the request, with a separate counter for that fallback. Compare
chunked and pooled-tree representations before attributing these costs to a
missing move facility or requesting independent dynamic stacks. Pool reuse
does not itself release committed memory to the OS.

The [persistent document Store](document/store.md) now implements this shared-tree
alternative with an explicit owner, independent current/saved/Undo/Redo roots and
collection across every live document. Equal 32-entry history traces at 3/16/64
documents avoid whole-text edit/save copies and reduce arena lengths. They retain
approximately 1 MiB fixed document/history descriptors and pay collection and
node-prefix text relocation. These are library representation costs to investigate
before proposing a language/runtime change; Workbench adoption remains separate.

The [indexed byte-buffer library](buffer/indexed.md) now supplies an explicit
caller-owned Store with fixed chunk directories and one grow-only byte arena.
Library freelists keep independently lived buffers in that owner without exposing
pool names, native allocations or raw borrowed slices. Generation IDs reject
closed/reused slots; complete byte/chunk-quota checks precede mutation. Multiple
Stores remain separate local owners. Direct lookup trades chain traversal for
147,456 raw bytes of reserved directory/freelist entries per Store, even when
few buffers are open. This tests an existing-Goose library alternative; it does
not yet add edit sharing, persistent Undo or OS-memory release.

## Values and worker boundaries

Typed queues and isolated workers fit HTTP requests, Git jobs and search results
well when messages own their payload. Borrow input slices only inside a call;
do not put pointers to UI models or native font buffers in a queue. Request serials
reject stale results independently of cooperative cancellation. See
[the API sample](apps/api-browser.md) and [cancellation](io/cancellation.md).

The [HTTP client Service](io/http-clients.md) now tests same-protocol composition
without competing client-local pollers: one explicit owner dispatches a bounded
worker queue to generation/serial-checked client mailboxes. Three confirmed
concurrent requests and 3/16/64 lifecycle traces cover cancellation, immediate
close/reopen, delayed/duplicate results, storage refusal and shutdown. Closed
jobs retain their token owners until completions are drained. This needs no Goose
compiler/runtime change; indexed buffers provide one shared payload tail.
It still requires one Service per message protocol. Runtime queue addressing,
multiple independent Service owners, streaming backpressure and adaptation of
the existing search/Git clients remain separate questions. Counts/budgets bound
the copied queue traffic; no zero-copy or total-memory claim follows from this.

The [stream/search experiment](io/streams.md) extends that boundary with one
unACKed page per request. Runtime worker IDs cannot address typed queues, so
eight concrete worker entry points specialize distinct `Ack<Payload, Lane>`
types. This prevents a foreign worker from consuming an ACK, while tickets and
sequences reject old messages. It covers 3/16/64 clients, held consumers,
ACK/Cancel races, close/reopen and native-resource cleanup with real search data.
Goose/native API changes were unnecessary. The initial search Service reserved
2859463 fixed bytes for 64 full-capacity mailboxes. Encoding used fields into a
flat byte packet and storing only ready payloads in one grow-shrink tail reduces
the fixed metadata/header to 10047 bytes. The independent oracle checks actual
queue bytes, previews and codec layout as well as result positions. Removal now
shifts later arena bytes; full-capacity packets can be nine bytes larger than the
old image, and owned exports remain fixed-size. The sparse 64-search fixture
uses 481792 queue-image bytes versus 14269440 for the same 320 messages at the
old fixed size, while compaction shifts 270410..370544 bytes across nine runs.
This proves a representation
choice, not a universal throughput/RSS improvement. The lane count remains static
and the native 16-read quota still needs per-worker budgeting. Dynamic queue
addressing, fair multiplexing and different arena reuse policies remain separate
investigations.

Variable-size values make accidental full-document copies expensive. A piece tree,
byte arenas and bounded Undo records keep editing independent of a contiguous
document copy. Render only visible lines and retain caches with explicit budgets.
See [text editor](apps/text-editor.md) and [memory/idle work](ui/text-foundation.md).

## Explicit lifetimes

Goose does not need destructors to model native resources. Give every handle one
owner, treat copied handles as aliases, and provide explicit close/destroy paths.
Stop/join workers before shutting down their service. Font sources can be shared
internally by native code while Goose still owns one family handle. Tests check
resource counts after cleanup. Early returns must follow the same cleanup policy.

Document-close decisions are reusable application behavior: save/discard/cancel
stays separate from native window-close events and asynchronous writes. See
[workspace editor](apps/workspace-editor.md) and [atomic save](io/atomic-save.md).

## UI APIs

Layout, behavior and painting are separate execution phases. A shared declaration
layer brings their authoring together: stable IDs, typed actions and a reducer are
easier to use than manually matching three independent widget lists. The reducer
belongs to the application; interaction, focus/capture, modal isolation and
scrolling belong to reusable libraries. See [UI composition](ui/ui-composition.md).

UTF-8 byte offsets remain useful across storage, shaping and selection. Extended
grapheme boundaries define editing units, not individual code points or glyphs.
IME preedit must not create Undo entries until committed. Color emoji fallback
must choose a face for a whole cluster. Shared library contracts keep these rules
consistent across application controls.

## Toolchain integration

Library imports need explicit search roots. Native public headers must not assume
compiler-generated slice names; adapters belong after runtime declarations in the
generated translation unit. Keep compiler source selection separate from public
library modules. See [toolchain requirements](toolchain.md).

Hierarchical imports work well for capability groups: `lab.net.http`,
`lab.document.model` and `lab.ui.render.font` keep application concerns out of
shared primitives. Namespace identifiers encode that path with underscores;
this follows Goose's existing namespace model. Import segments must be ordinary
identifiers: `loop` is a keyword, so the service uses `lab.io.event_loop`.

Native boundaries should match actual dependencies as well as directory names.
Font shaping and scene snapshot comparison have separate archives/adapters.
Filesystem job state machines share portable I/O types with the loop, rather
than importing its registry definitions. Third-party includes/compile definitions
are private implementation dependencies; native capability flags propagate to
generated applications. See [architecture](architecture.md).

Promote utilities after repeated use demonstrates a shared contract. Keep domain
models, controllers and sample-only constants under the individual `samples` application directories. No upstream
issue or PR is implied by these notes.
