# Documentation

Start with the [project README](../README.md) for building and running samples.
The [library map](libraries.md) lists imports and native targets;
[architecture](architecture.md) describes dependency boundaries and ownership.
The [Goose pattern guide](goose-patterns.md) compares useful storage structures,
ownership and asynchronous lifetimes, with measured costs and application limits.

## Library guides

| Area | Guides |
| --- | --- |
| Data | [JSON parsing/writing](data/json.md), [JSON files](data/json-files.md), [field editing](data/json-edit.md) |
| Buffers | [Indexed byte storage](buffer/indexed.md): independent lifetimes and direct lookup; [slot arena](buffer/slot-arena.md): variable values, hole reuse and deferred compaction |
| Documents | [Persistent document Store](document/store.md): multiple explicit-owner documents, shared Undo/saved roots, collection and equal-history comparison |
| I/O | [Event loop and processes](io/io-core.md), [cancellation](io/cancellation.md), [independent HTTP clients](io/http-clients.md), [bounded streams/search clients](io/streams.md), [process stdin/framing](io/process-input.md) |
| Files | [Asynchronous reads/listings](io/async-files.md), [atomic saves](io/atomic-save.md), [watching/reconciliation](io/file-watching.md) |
| UI authoring | [Composition](ui/ui-composition.md), [Clay layout](ui/layout.md), [scrolling/lists](ui/scrolling.md), [tree view](ui/tree-view.md), [commands/modals](ui/command-palette.md) |
| Text and rendering | [Renderer](ui/modern-ui.md), [font families/wrapping](ui/text-layout.md), [read-only text view](ui/text-view.md), [Unicode/memory/idle work](ui/text-foundation.md), [IME](ui/ime.md), [emoji](ui/emoji.md) |

## Applications

- [Workbench](apps/workbench.md): the main editor, explorer/search and Git application.
- [Text editor and piece tree](apps/text-editor.md): document edits, Undo, save/close and memory limits.
- [Workspace editor](apps/workspace-editor.md): explorer/search navigation and disk changes.
- [Git viewer](apps/git-viewer.md), [history/objects](apps/git-history.md) and [file search](apps/file-search.md).
- [API Browser](apps/api-browser.md): HTTP, local snapshots and asynchronous UI results.
- [Task Inbox](apps/task-inbox.md): stable records, local storage and failure handling.

## Development

- [Toolchain requirements](toolchain.md) and [local configuration](local-development.md).
- [API design and references](design.md) and [Goose feedback](goose-feedback.md).
- [Validation](validation.md) and [third-party notices](../THIRD_PARTY.md).
- [Independent document experiments](experiments/independent-documents.md): headless
  slice-pool ownership, correctness and reproducible time/storage comparisons.
- [Goose pool runtime experiments](experiments/pool-runtime.md): the same minimal
  source on upstream/fork, growth policies, stale views and a compiler diagnostic.
- [Buffer storage experiments](experiments/buffer-storage.md): geometric runs,
  linked pool chunks and the indexed Goose library under mixed growth, non-LIFO
  retirement and reopening.

Library guides describe current APIs, ownership, errors and limits. Application
guides describe complete workflows and their domain-specific rules. Put shared
test instructions in validation; keep run logs, historical comparisons, personal
paths and checkout investigations under ignored `local/`.
