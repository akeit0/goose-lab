# Workspace editor: file navigation and disk changes

The workbench Editor page connects the existing piece-tree editor to a lazy directory
explorer and project search. It retains **one active editable document**. A file
click or Enter opens it; a search hit selects the matching UTF-8 byte range. Arrow
keys navigate lists without opening every intermediate file. Reopening an active
file from the explorer preserves its edits and history. Ctrl+Shift+F opens Search;
Ctrl+S saves. Full path input appears only after Open / Save as is requested.

```text
cmake --build build --config Release --target workbench --parallel 4
python tools/run.py workbench --root . --file README.md
python tools/run.py workbench --root .
```

`--file` is relative to the process working directory; explorer/search paths are
relative to `--root`. The workbench shares the same document lifecycle with its
Git page. Historical Git blobs and diff views remain read-only. See the
[workbench workflow](workbench.md).

## Production references and deliberate adaptations

These are references for behavior and ownership, not copied implementations:

- [VS Code's text-file model](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/textfile/common/textFileEditorModel.ts)
  serializes saves, checks model versions after asynchronous reads, and preserves
  modified buffers. Here explicit flags and an owned pending `Intent` replace
  promises/listeners. Save-and-open advances only after successful publication
  and a clean document. Failed/conflicting saves retain the active buffer.
- [VS Code's explorer model](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/files/common/explorerModel.ts)
  resolves unresolved children on demand and merges successful results. Our
  bounded forest lists expanded folders one at a time; an entire listing must
  succeed before it replaces the tree. Stable keys preserve expansion on Refresh.
- [Helix's Rust document](https://github.com/helix-editor/helix/blob/master/helix-view/src/document.rs)
  checks existence before reloading and applies a text diff through history.
  We preserve the previous buffer on missing/invalid input, but explicitly replace
  the single document on a successful Reload and clear its Undo history. Selection
  byte offsets are clamped to valid boundaries; there is no diff-based rebasing.
- [libuv filesystem events](https://docs.libuv.org/en/v1.x/fs_event.html)
  can omit a filename. They invalidate a snapshot rather than authorizing an edit.
  We watch the active file's parent, including atomic rename saves, and asynchronously
  compare bytes with the saved baseline after coalescing events.
- [Go's filepath.Abs](https://pkg.go.dev/path/filepath#Abs) separates lexical
  absolute names from unique filesystem identity. `lab.fs.path` follows that distinction;
  there is no implicit symlink resolution or project security boundary.

## UI-independent APIs

`lab_document_workspace::State` borrows a single `lab_document_file::State`; it owns
only intent/observation metadata and native watch/read handles. The caller must
use both on the file session's owner thread. Neither holds interior references
to the document arena. `request` refuses another navigation while one is pending.

```goose
var file = lab_document_file::create();
var navigation = lab_document_workspace::State {};
lab_document_workspace::request(navigation, file,
    lab_document_workspace::Intent { path: "src/main.goose" });
// If navigation.prompt, the UI offers Keep, Save, or Discard:
lab_document_workspace::choose(navigation, file, lab_document_workspace::Choice.Save);
// Every frame/event-loop iteration:
lab_document_workspace::poll(navigation, file);
// Close observation before its borrowed file context:
lab_document_workspace::close(navigation);
lab_document_file::close(file);
```

An `Intent` can include `start`, `end`, `query`, and `ignore_case` for search
navigation. Selection occurs only if the live document still has that query at
those offsets and both ends are legal UTF-8/CRLF boundaries. A stale hit opens
the file and reports that search must be repeated; it does not select unrelated
bytes. Within a dirty active document, a hit navigates the current local text
without rereading disk or dropping Undo. Search itself reads disk files and
does not include unsaved changes.

Dirty navigation sets `prompt`. Keep cancels the intent. Discard starts a read;
failure still preserves the previous buffer, selection and history. Save waits
for the prepared-save baseline check and publication before opening the target.
A conflicting save never advances to the next file. An untitled buffer needs a
Save as target first; Save & open is unavailable without one.

`document_file.open(..., require_exists=true)` rejects a missing target instead
of treating it as a new empty document. Its default remains compatible with new
file creation. Loads capture both the current revision and next revision before
starting. Programmatic insertion followed by Undo during the read is detected
even when Undo restores the old saved revision. Successful adoption increments
`generation`, ensuring shaped-layout caches are cleared even when both documents
begin at revision 1.

## External changes

`disk` distinguishes SAME, CHANGED, DELETED and UNREADABLE, with `disk_code` for
details. Comparison uses saved bytes, not the current local edit or only an
mtime/digest. A periodic check every five seconds also reconciles lost events or
a failed watch. `watch_code` records that failure. Opening starts another check
after installing the watch, covering the initial read/watch gap.

Observation never adopts new text, so typing continues while it reads. The UI
offers Reload; dirty documents require confirmation. Deleted, oversized, binary,
invalid UTF-8 or unreadable files retain the current document. Save revalidates
independently of the watcher, so a stale notification cannot permit an overwrite.
Reads are cancelled before load/save transitions; generation/path changes retire
the old watcher/read. Each probe has a 30-second deadline and a 2-MiB byte limit.

Existing save limitations still apply: revalidation followed by replacement is
not atomic compare-and-swap against another writer. Window close uses the shared
save/discard/cancel decision, including untitled save paths and failed-save retention.
No sibling recovery copy is written. See [text editor](text-editor.md#closing-a-document).

## Explorer and memory bounds

`lab.fs.explorer` borrows the caller's loop. `create/poll/load/refresh/close` manage one
directory listing, and its `tree/state/loaded` adapt the existing tree model.
New branches start collapsed. The active file expands only its required ancestors
and is selected/revealed when they resolve. Only expanded folders are listed; collapse does
not discard cached children. Refresh relists the root and expanded descendants.
It is currently explicit; file observation does not refresh the whole explorer.

Limits are 512 entries per directory, 2,048 tree nodes, depth 32, and 512-byte
project keys/absolute application paths. A failed or over-limit listing leaves
the last successful forest intact and reports failure. `.git`, links, special
files, unknown entry types and nonportable project names are excluded, with a
`skipped` count. There is no `.gitignore` parser. The search adapter retains at
most 256 hits; reaching that cap reports incomplete results. It uses the existing
search exclusions, cancellation and one-page acknowledgement backpressure.

The forest, expansion keys and listing staging are bounded inline storage (about
3.60 MiB in Explorer); 256 hits add about 217 KiB. A completed listing temporarily
copies the forest to permit failed builds without partial adoption. These costs
are separate from text storage and process memory. Making the tree capacity
proportional is a useful next memory improvement. The workspace is a separate
wrapper around the standalone editor so the standalone sample does not reserve
these arrays. The wrapper puts its one resizable editor/document tail last,
respecting Goose's layout restrictions instead of adding heap-owned document
pointers or destructors. No document array or document copy per explorer row.

`lab_fs_path::absolute(path,limit=32768)` returns owned UTF-8 bytes and a code; errors
return empty bytes. Windows uses GetFullPathNameW and slash normalization; POSIX
uses the working directory and lexical component normalization. It does not read
the target and can name a new file. Case, hard-link and symlink aliases may remain
distinct. `relative` validates portable project keys and is shared with search.
Link native path support through `goose_lab_loop`; no extra external dependency.

## Limits

The workspace retains one active document. Tabs, workspace-root switching,
automatic clean-buffer reload, diff-based reload Undo, syntax highlighting and
soft wrapping are unsupported. Windows is validated; the POSIX path branch is
unvalidated. Shared [IME](../ui/ime.md), [grapheme editing and idle rendering](../ui/text-foundation.md)
apply to this editor. See [validation](../validation.md) for navigation, conflicts
and resource cleanup checks.
