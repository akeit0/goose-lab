# Workbench

The main application combines an editable document and project explorer/search
with read-only Git diffs and first-parent history. Git must be available on PATH.
A plain directory still supports editing/search; Git errors appear on the Git page.

```text
cmake --build build --config Release --target workbench --parallel
python tools/run.py workbench --root . --file README.md
python tools/run.py workbench --root . --git
python tools/run.py workbench --root . --history
```

`--root` selects the explorer/search directory. `--file` is resolved relative to
the process working directory. Git resolves a subdirectory to its repository
root; **Edit file** uses that root, even when the explorer covers a subdirectory.
Select another folder by restarting with `--root`.

## A complete workflow

1. Select a file in **Editor → Files**, or enter a literal query under **Search**.
   Clicking a result opens the current disk file and selects the matching bytes.
2. Edit, select text, use IME, Undo/Redo and save with **Ctrl+S**.
3. Switch to **Git**. Select **Working tree**, **Staged** or **History**, then a
   file. Filter paths, navigate hunks and find/select/copy patch text.
4. Choose **Edit file** to open the current working file in the editor. History
   contents remain read-only; this action opens current disk bytes.
5. If a different file is requested while the document is dirty, choose
   **Keep editing**, **Save and open** or **Discard and open**. Switching pages
   itself preserves the current buffer, selection and Undo history.

The active document and Git continue observing disk changes while their page is
hidden. Search pages also continue draining while Git is active. Git never stages,
commits or rewrites the index. A save is an explicit editor action; Git reflects
its result after watch/debounce reconciliation. **Refresh/F5** is available if
watching fails. Git **Ctrl+Shift+F** returns to the shared project search.

Closing the window from either page follows the editor's save/discard/cancel
decision. Switching views releases IME preedit, without inserting uncommitted
composition into document bytes.

## Composition and ownership

`workbench/controller.goose` coordinates the pages and their navigation intents.
The editor owns the renderer and three font assets; the Git view borrows their
font table and paints into that renderer. Layout and input state remain separate
per page. There is one project search worker, one Git worker and one file session.
All page polling runs at the host boundary, independent of the visible page.

Goose permits only one resizable tail per value. Both the document and Git diff
contain such a tail, so the entry point owns them in separate local variables and
passes references alongside a small fixed-size coordination `State`. It does not
introduce pointers into Goose-owned storage or copy native ownership into messages.
Shutdown joins workers and closes borrowed layouts before destroying the font
sources and renderer. Stable frames use the shared scene's on-demand presentation.

The sample retains one editable document; it does not yet provide multiple tabs,
syntax highlighting, LSP, a terminal or Git staging. See the detailed
[document](text-editor.md), [workspace](workspace-editor.md) and
[Git](git-viewer.md) guides for behavior and bounds.

`--headless --frames N --screenshot path`, `--width`, `--height` and `--scale`
support reproducible rendering. The workbench interaction fixture covers dirty
navigation, background save/diff refresh, search ownership, close from Git and
zero tracked UI native bytes after shutdown, at normal and 125% scale.
