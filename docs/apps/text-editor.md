# Piece tree and text editor

The document libraries provide editing independently of the UI.
`lab.document.piece_tree` and `lab.document.model` are pure Goose. `lab.document.file` uses the existing
async-file loop, while `lab.ui.views.editor` owns viewport/input behavior. The independent
Editor page of the [workbench](workbench.md) exercises these APIs without adding
edit semantics to Git diffs or historical blobs. Its [workspace](workspace-editor.md) connects a
lazy file tree and search results to the same editor, with dirty navigation and
external-change notices. It retains one active document; multi-document tabs are unsupported.

```text
cmake --build build --config Release --target workbench --parallel 8
python tools/run.py workbench --file samples/workbench/main.goose
python tools/run.py workbench
python tools/run.py workbench --file README.md --headless --frames 3 --width 560 --height 860 --screenshot build/editor.png
```

## Why a piece tree

VS Code describes its buffer as a piece table backed by multiple buffers and a
red-black tree, with line metadata: [official design article](https://code.visualstudio.com/blogs/2018/03/23/text-buffer-reimplementation)
and [current source](https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts).
Our implementation uses the same general piece-based idea with different local
choices: UTF-8 bytes, a persistent AVL tree, and explicit bounded ownership.
The piece tree is implemented in Goose without a native dependency.

The text region starts with original contents and receives inserted bytes at its
end. Logical text bytes do not change during ordinary edits. Leaves identify
logical byte ranges rather than owning separate strings. Internal nodes
store subtree byte counts, LF counts, heights and leaf counts. An edit splits
at its boundaries and joins the surviving pieces with inserted pieces; AVL
balancing keeps lookup paths short. It creates new nodes along changed paths,
sharing unaffected nodes with previous revisions. Adjacent contiguous leaves
coalesce when their combined length fits a leaf.

Undo/redo changes a root and restores its selection/revision. It does not copy
the entire text for every revision. Line lookup uses LF counts to descend the
tree, then scans one leaf (at most 4,096 bytes). CRLF can cross leaves: counting
LF makes aggregate counts composable without special cross-piece correction.
A trailing newline produces an empty final editing row; an empty document has
one editing row. This differs intentionally from the read-only patch row model.

Nodes and text use a single `u64[>..<]` arena, fitting Goose's one-resizable-tail
rule. Its prefix contains seven words per node; its suffix packs eight UTF-8 bytes
per word. Child IDs encode absence as zero in storage and expose -1 at the API,
so unsigned byte packing remains valid with debug integer-conversion checks.
There are no typed interior references or writable byte reinterpretations.
The node prefix grows geometrically from zero, bounded by the configured limit
of at most 32,768 nodes. Growth relocates text words, while logical text offsets
stay valid. This occasionally costs O(stored text), rather than reserving the
maximum node array or shifting it on every text append.

Mark/compact collection retains the current root, saved root and all undo/redo
roots, then remaps their node indices. Document owns those indices; callers must
not retain raw root IDs across collection. It also merges the retained leaves'
text intervals, moves surviving bytes forward in place, and remaps leaf offsets.
Unreachable text can therefore be reclaimed without discarding history. Collection
runs when node or text capacity would reject an edit. If the pinned contents still
exceed the limit, the edit fails without losing document/selection/history.
Clear undo explicitly rebuilds current and saved text and their arena, preserving
the disk baseline and saved revision identity while dropping undo/redo.

## Core API

```goose
var document = lab_document_model::create(original);
if document.code != lab_document_model::OK { return; }
assert(lab_document_model::select(document, 0, 0));
let code, changed = lab_document_model::insert(document, "hello\n");
if code == lab_document_model::OK && changed {
    assert(lab_document_model::undo(document));
    assert(lab_document_model::redo(document));
}
let output = lab_document_model::contents(document); // Owned snapshot, e.g. for saving.
```

All offsets are zero-based byte offsets. Mutations and selections must be on
UTF-8 scalar boundaries and outside the interior of a CRLF pair. NUL and invalid
UTF-8 are rejected. LF/CRLF bytes are preserved; Enter uses the first observed
newline style, with LF for a new file. Paste preserves the supplied bytes and
may introduce mixed line endings. Lone CR is retained as an ordinary control
scalar; it is not a separate line terminator.

`replace(start,end,text)` reports a code and whether content changed. Validation
and conservative node/byte reservation precede the text mutation. A failed edit
preserves text, selection and history; collection may remap internal IDs. A no-op
creates no revision. Default limits are 2 MiB of current text, 8 MiB of stored text,
32,768 nodes and 256 undo entries. Older undo entries are dropped when the history
fills. Tree creation/edit preflight may reject before the theoretical node count
is full to reserve a safe upper bound on temporary path nodes.

`insert(text,true)` groups consecutive typing at the same insertion position.
Selection/movement, undo/redo, saving and non-typing edits break groups. Enter and
Tab are separate edits. `mark_saved` pins the current root and revision; undoing
back to that revision clears dirty state, and branching after undo discards redo.
Dirty is revision identity, rather than a full text comparison on every input.

`read(start,end)` owns only the requested range. The UI retrieves visible lines
and the caret's target line, rather than flattening or indexing the entire file.
`lab.ui.render.text_layout` retains native full-line shaping and source-byte scalar carets.
An editor owns up to 128 cached line handles, invalidating them on document revision
or font changes. Scrolling/selection reuse the geometry; 256-glyph block bounds
skip offscreen geometry, and only visible glyphs reach Goose's temporary arrays.
Tab/control display and ligature interpolation match the existing text utilities.
Close each layout before its borrowed font; copying a Layout is a borrowed alias.
Native layouts have a global 128-MiB retained-allocation budget and bounded source
size; conservative preflight rejects oversized expansion before shaping. A failed
layout is reported in the row/status without modifying the document. HarfBuzz,
font runs and input buffers still need temporary memory outside the retained bound.

The complete line is still shaped on initial creation and after content revision;
editing an extremely long line can remain expensive. This adds neither shaping
at arbitrary substrings nor per-keystroke incremental shaping. Horizontal width
is the largest visited line width and stays stable until a document is reopened.

## Interaction and saving

The sample supports typing, multiline paste/cut/copy, Enter, Tab, Backspace/Delete,
mouse/Shift selection, arrow/Home/End/Page movement, vertical/horizontal scrolling,
Ctrl+A/C/X/V, Ctrl+Z/Y/Shift+Z, Save/Ctrl+S and Open/Ctrl+O. Unmodified Tab inserts
a literal tab; Shift+Tab leaves the editing control through ordinary focus traversal.
The caret is one physical pixel wide and selection never changes text shaping.
User movement/deletion/hit testing uses [extended grapheme boundaries](../ui/text-foundation.md); byte-range APIs and column counts remain scalar-based.
Shared [IME preedit and atomic commits](../ui/ime.md) and [color emoji](../ui/emoji.md) are implemented.
Paragraph bidi, soft wrapping, multiple cursors and syntax highlighting are unsupported.

Opening a missing path establishes a new file without immediately writing it.
An untitled document can choose a create target through Save as/Create. Existing
files are never implicitly overwritten by this creation flow. Open on an existing
file with local edits opens Keep editing / Save first / Discard & open. Save first
saves the current file and leaves the path draft available for a subsequent Open.
A failed read keeps the previous document. Clear undo removes undo/redo history
and compacts storage; it does not mark unsaved changes as saved.

The owner-thread file session owns one event loop and child jobs. A save captures
owned bytes into a prepared sibling temporary, re-reads the disk file and compares
its exact contents with the saved root, then commits. A missing target must still
be missing before committing a new file. A mismatch reports conflict, preserves
local edits and closes/removes staging resources. Reopen and explicitly discard
only after reviewing the disk change; the sample has no force-overwrite button.

Editing is disabled while load/save is pending, and focus returns after it ends.
Programmatic callers should likewise avoid mutating the document while a file
operation is active. A revision check rejects changes observed before commit;
changes after commit cannot retrospectively cancel publication. Revalidation is
an observation, not filesystem compare-and-swap: a writer between the last read
and rename can still race. File-data sync, parent-directory durability, symlink
and metadata behavior inherit [atomic save](../io/atomic-save.md). Operations have a
30-second logical deadline; closing/cancelling can wait for outstanding OS work.
Always explicitly close the file session, even after errors.

## Closing a document

The sample enables `gfx::defer_close(true)`. Native close/quit requests become
ordered `EVENT_CLOSE_REQUESTED` events, so `frame()` keeps running while the app
decides whether to exit. Default gfx clients still end their loop immediately;
explicit `gfx::quit()` ends it regardless of this policy. Shared `lab.ui.view` routes
the request even when no text control has focus, preserving its order relative
to text edits in the same frame.

`lab.document.close` holds the exit decision independently of rendering. Call
`request(state,file)`, keep driving the file session, then `poll(state,file)`.
Pending reads/saves settle first. A clean document becomes `ready`; a dirty one
sets `prompt`. `choose(state,file,Choice.Cancel/Save/Discard)` applies an explicit
choice. The caller exits its loop only when `ready` is true. File/session owners
still close their resources explicitly afterwards.

Both editors show **Save / Discard / Cancel** on a dirty close. Save uses the same
baseline-checked atomic operation as ordinary saving and waits for success before
approving exit. A conflict, I/O error or changed pending revision returns to the
prompt with the local text preserved. Untitled/new documents can enter a save path
inside this dialog; empty paths and failed saves leave it open. Discard approves
exit without writing, and Cancel/Escape/backdrop resumes editing. Repeated close
requests do not dismiss the prompt or change the decision. Close supersedes an
unconfirmed navigation intent and waits for an already-running navigation save/load.

Undo history remains in memory; no session or recovery files are generated.
Crash/session restore is unsupported. An explicit finite `--frames` profiling run
ends at its limit without prompting or saving.

## Memory

Nodes and packed text occupy `56 * node_capacity + 8 * ceil(stored_bytes / 8)`
bytes, plus bounded document/history metadata. An empty document has no arena
elements. Capacity grows with use up to configured limits; the default maximum
retained model size is roughly 9.77 MiB. This is not a process-memory bound.

Collection retains bytes referenced by current, saved and Undo/Redo roots.
Deleted text needed by history is intentionally retained. Clear undo rebuilds
the arena. Goose's Windows runtime commits data-stack pages on demand and keeps
them for reuse until region release; logical reclamation need not immediately
reduce private committed memory. Explicit layout close frees native allocations;
allocator/driver working sets can remain larger. Compaction, I/O and construction
can require temporary storage beyond the retained model.

See [profiling](../ui/text-foundation.md#profiling) for process/native measurements and
[validation](../validation.md) for flat-string oracle, tree invariants, save conflicts,
interaction and resource cleanup checks.
