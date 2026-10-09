# Workbench

A compact editor and Git viewer for trying goose-lab in a practical application.
The left side holds the file explorer, project search or Git changes/history.
The right side holds open-file tabs and editable text or a read-only Git view.
Help lists the keyboard shortcuts. UI and editor fonts are 13 px, with 20 px
editor lines and compact, flat file rows.

## Run

From the repository root, after [configuring the build](../../README.md#build):

```text
cmake --build build --config Release --target workbench --parallel
python tools/run.py workbench --root . --file README.md
python tools/run.py workbench --root . --git
python tools/run.py workbench --root . --staged
python tools/run.py workbench --root . --history
```

`--root` selects the explorer/search directory; `--file` is relative to the
process working directory. A plain folder supports editing and search. Git must
be on PATH for Git views; a nested root resolves to the containing repository.
**Edit file** always uses that Git repository root. Choose another project by
restarting with `--root`.

Use the configured build directory with `python tools/run.py --build build/gui
workbench --root .`. `python3` also works where that is the Python 3 command.
The application itself does not require Python or PowerShell. Windows is tested;
Linux and macOS still need native validation.

## Try a workflow

1. Choose **Files** and open a file. Expand folders or use arrow keys and Enter.
   Opened paths appear as tabs; **Open** accepts a file path.
2. Edit with text selection, IME, Undo/Redo and **Save**. A dot marks unsaved text.
   Closing a dirty tab offers Keep editing, Save & close or Discard.
3. Choose **Find**, enter a literal query, and press Enter or **Find**. Clicking a
   result opens the disk file and selects the matching text. Search excludes
   unsaved edits and uses the library's default dependency/build exclusions.
4. Choose **Git**. **Changes** shows working-tree differences; **Staged** compares
   the index to HEAD. Select a file to see its patch on the right.
5. Choose **History**, then a commit and file. **Diff** shows its patch against
   the first parent; **At commit** shows the historical file. **Edit file** opens
   the current working copy. Git views never stage, commit or rewrite the index.
6. Click a file tab to return to editing. If another file is dirty, choose Keep,
   Save & open or Discard & open. Closing the window also offers a save decision.

Tabs keep up to 16 paths, cursor positions and scroll positions. Ctrl+Tab and
Ctrl+Shift+Tab switch files; overflow arrows make clipped tabs reachable.
**There is one resident editable document.** Switching files rereads disk bytes
and clears the previous file's Undo history after the save/discard decision.
Inactive tabs do not retain unsaved buffers. Switching between the editor and
Git without changing files preserves the active buffer, selection and Undo.

Disk-change checks, project search and Git refresh continue while their view is
hidden. External file changes keep local edits intact and offer Reload. Stable
frames do not redraw the GPU scene.

File names and selection stay visible during loading, saving and Git refresh.
The status bar shows the operation; affected lists temporarily ignore selection
and activation, while scrolling and other controls remain available.

## Keyboard shortcuts

Choose **Help** or press **F1** to see the bindings in the application. Application
commands use Control on Windows/Linux and Command on macOS. Tab navigation uses
Control on every platform.

| Action | Windows/Linux | macOS |
| --- | --- | --- |
| Save / open file path | Ctrl+S / Ctrl+O | Cmd+S / Cmd+O |
| Undo / redo | Ctrl+Z / Ctrl+Shift+Z | Cmd+Z / Cmd+Shift+Z |
| Files / Git view | Ctrl+Shift+E / Ctrl+Shift+G | Cmd+Shift+E / Cmd+Shift+G |
| Find in files | Ctrl+Shift+F | Cmd+Shift+F |
| Next / previous file tab | Ctrl+Tab / Ctrl+Shift+Tab | Ctrl+Tab / Ctrl+Shift+Tab |
| Close active file tab | Ctrl+W | Cmd+W |
| Select all / copy / cut / paste | Ctrl+A / C / X / V | Cmd+A / C / X / V |
| Git: Changes / Staged / History | Ctrl+1 / 2 / 3 | Cmd+1 / 2 / 3 |
| Git: find in patch or file | Ctrl+F | Cmd+F |
| Git: command palette | Ctrl+K | Cmd+K |
| Git: refresh | F5 | F5 |
| Git: next / previous hunk | F7 / Shift+F7 | F7 / Shift+F7 |
| Git: next / previous text match | F3 / Shift+F3 | F3 / Shift+F3 |
| Help / dismiss overlay | F1 / Escape | F1 / Escape |

On macOS, Command+Left/Right moves to line boundaries and Command+Up/Down moves
to document boundaries. Arrow keys, Shift selection and PageUp/PageDown are
shared; Home/End and Control/Command+Home/End are also supported by text views.

## Rendering checks

```text
python tools/run.py workbench --root . --file samples/data/emoji.txt --headless --frames 3 --screenshot build/workbench.png
python tools/run.py workbench --root . --history --headless --frames 3 --width 560 --height 860 --screenshot build/workbench-history.png
ctest --test-dir build -C Release -R workbench_integration --output-on-failure
```

Headless rendering still needs a GPU/backend. `--scale` accepts 0.5–4.0;
`--width` accepts 560–2560 and `--height` accepts 640–1440. A finite run waits for
foreground work before its final capture. The fixture uses temporary repositories
and checks navigation, saves, tabs, Help, startup Git modes, idle drawing and cleanup.

## Read the code

| File | Responsibility |
| --- | --- |
| [main.goose](main.goose) | Options, window, owned values and shutdown |
| [controller.goose](controller.goose) | Background polling, navigation and shared painting |
| [navigation.goose](navigation.goose) | Shell layout, activity bar, tab strip and Help |
| [editor/workspace.goose](editor/workspace.goose) | Explorer/search, tab paths and file navigation |
| [editor/single.goose](editor/single.goose) | Editable document, save/reload/close decisions |
| [git/viewer.goose](git/viewer.goose) | Git worker results, changes, history and read-only text |

The sample borrows the reusable APIs under `lib/lab`; its shell and tab paths
remain application code. There is one scene/renderer, one project search worker,
one Git worker and one file session. Detailed ownership and bounds are in the
[Workbench guide](../../docs/apps/workbench.md). Syntax highlighting, LSP,
terminals and Git staging are not implemented.
