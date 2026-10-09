# Git history and past file contents

The same Goose APIs serve a GUI-free CLI and the native Git viewer. Git is
required on PATH. No checkout, index update or worktree write is performed.

```text
cmake --build build-core --config Release --target git_history
./build-core/Release/git_history.exe . list
# Copy a full commit ID from list (40 or 64 lowercase hexadecimal bytes).
./build-core/Release/git_history.exe . files COMMIT_ID
./build-core/Release/git_history.exe . diff COMMIT_ID README.md
./build-core/Release/git_history.exe . blob COMMIT_ID README.md
# Anchor, offset, page size. JSON exposes whether another page is available.
./build-core/Release/git_history.exe . list COMMIT_ID 32 32

cmake --build build --config Release --target workbench
python tools/run.py workbench --root . --history
```

`list` emits one JSON page; `files` emits a JSON array; `diff` emits original
unified patch bytes; `blob` emits exact binary bytes. Failed operations emit no
partial stdout. Do not use a text-mode shell redirection when preserving binary
bytes; a caller can capture the executable's stdout directly.

## Library boundary

`lab_git_history::page(repo, anchor="", offset=0, count=32, options={})` returns an
owned `Page`: code/error, anchor, offset, more and commit metadata. An empty
anchor resolves HEAD once. An unborn HEAD produces an empty page. Subsequent
calls use that full anchor ID, so newly created commits do not shift offsets.
The library accepts 1–64 records per page and offsets 0–1,000,000. One extra
record determines `more`; a failed parse never returns a partial page.

Each `Commit` owns its ID, first parent, parent count, author, author ISO date
and subject. Metadata is NUL separated; separators in subjects/author text
cannot be confused with LF, tabs or filenames. Malformed framing, duplicate
IDs and unsupported metadata are errors. IDs accept SHA-1 and SHA-256 shapes;
SHA-256 repositories have not been tested. Author/subject limits are 512/1,024
UTF-8 bytes. Display labels escape controls and truncate separately; API values
remain exact within these limits.

History follows the **first parent**, keeping the main line through merges.
`files(repo, commit, options)` and `diff(repo, commit, path, options)` compare the
commit with its first parent. A parentless commit is compared with an empty
tree. A merge therefore shows what was introduced into its main line, rather
than a combined diff. Shallow history boundaries follow Git's available
ancestry. Renames appear as deletion/addition. The existing 512-file/path,
2 MiB output, 32,768 row and 4,096 hunk limits apply.

`blob(repo, commit_id, path, options)` returns an owned `lab_git_object::Result`.
It requests `COMMIT_ID:path` through the existing `cat-file --batch -Z` decoder.
The response must be a file blob. A deleted/missing file, tree or submodule
entry has an explicit error. File paths are literal object paths, preserving
Unicode and brackets. The generic `lab_git_object::read` also accepts bounded
Git object expressions and exposes batch statuses/types/raw bytes.

The object reader owns a private event loop, sends one copied request, signals
stdin EOF, drains the response, checks framing/input/exit completion, then
closes the loop and all children on every exit. It is a synchronous worker-side
convenience over `lab.io.process_stream`, not an owner-thread asynchronous API.
Cancellation is checked before launch and between loop steps (at most 20 ms
waits, excluding cleanup). The caller keeps its cancellation token alive until
the operation returns. The default eight-second deadline and 2 MiB combined
stdout/stderr budget remain; framing consumes some of that budget, so an exact
2 MiB blob cannot fit. Binary and unsupported text encodings remain valid CLI
blob bytes. The UI reports binary or encoding errors instead of altering them.

`lab_text_diff::plain(bytes)` creates owned line rows without interpreting `@@`, `+++`
or other patch syntax. It preserves original LF/CRLF/final-newline bytes and
gives each row a file line number. NUL-containing data is reported as binary;
other non-UTF-8 text is an encoding error. The shared text view handles
selection, search, scrolling and exact copy for both representations.

## UI and request adoption

History/Ctrl+3 opens 32 commits at a time. Rows show subject, abbreviated ID,
author/date and a merge marker. Pointer and keyboard selection share the
existing virtual list behavior. Newer/Older reuse the anchor. Refresh/F5 resolves
the current HEAD and returns to the newest page; an automatic metadata refresh
retains the anchor/page/current commit. Worktree-only notifications do not
reload history. The file filter applies to changed paths in the chosen commit.

Diff/File at commit switch the shared text surface. Deleted files use Diff;
their content button is disabled. The path includes the ID that produced the
displayed text, even while a newer selection is loading. Copy file and Ctrl+C
copy original content bytes. Empty/binary files have no copyable text surface.

The worker returns owned snapshots. One serial and cancellation token cover
all request kinds. The UI stores only the latest queued intent and drains a
cancelled completion before starting it. Commit-file adoption precedes a file
read; search edits during that stage are applied to the newly returned
collection. Late responses cannot be adopted under another path, commit or
content mode. Mode switches use the same queue. Failed requests retain the
previous collection where possible and show an error.

Arbitrary revision comparisons, all-parent graphs, branch selection and file
history/rename following are unsupported. Windows is validated; POSIX remains
unvalidated. The commands follow Git's
[history format and first-parent options](https://git-scm.com/docs/git-log),
[tree diff options](https://git-scm.com/docs/git-diff-tree) and
[size-framed object protocol](https://git-scm.com/docs/git-cat-file).
