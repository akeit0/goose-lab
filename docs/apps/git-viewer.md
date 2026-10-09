# Git Diff Viewer

A real repository -> isolated process -> owned diff -> interactive Goose UI.
The viewer uses the same Clay/FreeType/HarfBuzz/SDL3 stack as the other modern
samples. Git must be installed and available on PATH.

```text
cmake --build build --config Release --target workbench --parallel
python tools/run.py workbench --root C:/work/project --git
python tools/run.py workbench --root . --staged
python tools/run.py workbench --root . --history
python tools/run.py workbench --root . --git --headless --frames 3 --screenshot build/git-diff.png
```

This is the **Git** page of the [workbench](workbench.md). The explorer/search root
defaults to `.`; Git resolves a subdirectory to the repository root. Choose another
folder through `--root` at startup. **Edit file** opens the current working file in
the shared editor, using its dirty-navigation decision.

External worktree, index, HEAD and ref changes refresh through shared
[watch/debounce utilities](../io/file-watching.md), even while Editor is active.
Refresh/F5 remains available when recursive watching fails. Linked worktrees also
observe Git/common directories outside the worktree. The command palette is opened
with Ctrl+K; it can pause automatic refresh. Ctrl+1/2/3 selects working/staged/history;
F7/Shift+F7 navigates hunks; Ctrl+Shift+C copies the patch. Ctrl+Shift+F returns to
the workbench's project search. Escape closes the palette or the text Find bar.

## Scope and limits

This viewer handles tracked working/index differences, untracked previews and
[first-parent commit history with past file contents](git-history.md).
Side-by-side alignment, editing/staging/reverting and arbitrary
revision comparison are not implemented. Renames are shown as addition and
deletion. Binary changes are reported as binary rather than converted to text.
Combined merge diffs are rejected with a specific message. A failed refresh
retains the previous collection and comparison mode. Choosing another file
while a diff is running cancels the old read and coalesces to the latest path.
The displayed filename, patch and navigation remain together until the new
result is adopted; a late completion cannot appear under a different filename.
Refresh and comparison-mode controls stay available during diff reads. A new
refresh cancels the outstanding diff and runs after its completion is drained.

Untracked regular files are compared against `/dev/null` with Git's `--no-index`.
Text appears as additions, including old/new numbering, empty-file headers and
missing-final-newline markers. Binary files show Git's summary and the observed
file size. Copy patch preserves Git's original output; a binary summary does
not include a binary payload. Files observed above 2 MiB, directories, symlinks,
Windows reparse points and unsupported text encodings produce explicit errors.
Nested repository directory entries also produce the regular-file error.

The viewer accepts up to 512 files, 512 UTF-8 bytes per repository/file path,
2 MiB per patch, 32,768 display rows and 4,096 hunks. Unsupported encodings and
exceeded bounds are explicit errors rather than partial adoption. A single
process captures at most 2 MiB across stdout/stderr and has an eight-second
running deadline by default. Repository refresh uses root discovery and file
listing and watch-path discovery as separate bounded processes. The 512-file total includes both tracked
and untracked entries. A failed or oversized untracked listing is rejected
without adopting a partial collection. Long rows are clipped horizontally,
not wrapped or copied into the small UI-label buffer. Existing font-atlas/GPU
frame budgets still apply; extreme single lines, very large displays and
prolonged use have not been load-tested. The tested platform is Windows.

## Reusable pieces and ownership

`lab.collections.tree` and `lab.ui.views.tree` provide the shared hierarchy, projection and virtual
row behavior. `lab.git.tree` only maps Git paths/status indices into that model.
The tree is validated before adopting refreshed files; a model capacity/depth
error retains the previous collection. Folder keys use full paths, never row
numbers or basenames, so rebuilding order and equal leaf names are safe.

`lab_fs_files::info(path)` returns a small owned `{code, size}` observation using the
existing `goose_lab_files` native bridge. It accepts UTF-8 paths and distinguishes
missing files, IO errors, invalid paths and non-regular files; no handle escapes.
Linking that archive enables `GOOSE_LAB_FILES` through its CMake interface.
The observed size is a preflight check, not a snapshot or lock. Git can see later
writes; the existing capture deadline and output budget still bound its process.
Metadata queries themselves use the operating system's synchronous filesystem
API and do not have a cancellable deadline. Windows is validated; POSIX is not.

`lab.text.line_index` builds an immutable owned offset table for LF/CRLF text. Empty
text has no rows; a trailing newline does not add a phantom row. `line` borrows
from caller-owned text; `row_at` uses binary search for a byte position. The
caller must keep the original text unchanged while using its index. This is a
small useful collection for text tools, rather than another map implementation:
Goose already provides `dictionary`, sorting and array search.

`lab.text.diff` parses hunk ranges and tracks old/new positions, additions, deletions,
context and no-final-newline markers. Header-looking added lines such as
`+++literal` remain additions inside a hunk. It checks declared counts before
adopting the complete patch. Rows store byte ranges; the text is owned once.
The mutable Patch has bounded metadata arrays and one final grow/shrink source
builder. This follows Goose's restriction on resizable fields. Moving a worker
result into mutable UI state uses an explicit `copy`.

`lab.io.process` is a synchronous mechanism intended for a worker. It accepts an
argument array and working directory without a shell; returns owned stdout,
stderr, a capture code and the separate exit code. Invalid input, launch
failure, capture failure, output limits, timeout and cancellation are distinct.
Partial output from failed capture is diagnostic only; Git never adopts it.
Results use frozen owned byte arrays; native handles never enter Goose messages.
Link `goose_lab_process`; its interface enables `GOOSE_LAB_PROCESS` and the existing
cancellation bridge. The native layer drains both output streams fairly, closes
all handles and terminates descendants when the child finishes or is cancelled.
Windows uses UTF-8-to-wide conversion, CRT-compatible argument quoting, an
explicit inherited-handle list, a hidden process and a kill-on-close job.
A POSIX process-group implementation is included but is not validated here.

`lab.git.repository` owns the Git boundary; `lab.git.client` and `workbench.git.viewer` remain sample
protocol and UI. Tracked listing uses `--name-status -z`; untracked listing uses
`ls-files --others --exclude-standard --full-name -z`. Standard excludes include
`.gitignore`, `.git/info/exclude` and the user's configured exclude file.
Spaces, Unicode and control characters are not confused with separators.
Display paths escape controls; calls retain the exact path. Diff requests use literal pathspecs
and an explicit `--` separator, with external diff, textconv, pager, color,
word-diff and line-prefix variations disabled. The CLI supplies quotePath for
readable Unicode headers without changing Git configuration. Public `files`
and `diff` expect a repository root; call `root` for arbitrary subdirectories.
`untracked(repo, path)` takes a repository-relative regular-file path and accepts
Git's no-index exit status 1 as a successful difference. It rejects absolute,
parent-traversing and colon-containing paths. Its path portability is narrower
than arbitrary POSIX filenames. The worker chooses this operation from `?`
status rather than guessing from an empty tracked diff.

The behavior follows [Git's diff specification](https://git-scm.com/docs/git-diff),
[Git's file-listing specification](https://git-scm.com/docs/git-ls-files)
and [Microsoft's process-creation guidance](https://learn.microsoft.com/en-us/windows/win32/procthread/creating-processes).
The viewer issues discovery/diff commands only. Integration validation checks
that the repository index and working files remain byte-for-byte unchanged.

See [validation](../validation.md) for process, parser and interaction checks.

## Find in files

Ctrl+Shift+F returns to **Editor → Search**, where one shared worker searches disk
files independently of Git status. Clicking a result opens the editable document
with the same save/discard/cancel navigation decision. Git observation continues
while search is active. The current GUI exposes a literal query; include/exclude
globs and ASCII case folding are available through the CLI and library.
See [file search](file-search.md) for ownership, coverage and limits.
