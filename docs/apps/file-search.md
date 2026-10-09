# Find in files

`lab.fs.search` searches current filesystem contents independently of Git, HTTP
and the GUI. The `find_files` CLI works in the GUI-free build. The workbench Editor
uses the same engine through one owned worker, then opens a selected match in
the editable document.

```text
cmake --build build --config Release --target find_files workbench --parallel 8
python tools/run.py find_files --include "**/*.goose" -- . "fn main"
python tools/run.py find_files --ignore-case --exclude "scratch/**" -- . "TODO"
python tools/run.py workbench --root .
```

The CLI emits one JSON object per match and flushes each page. Diagnostics and
final counters go to stderr. Exit 0 means completed without skipped eligible
files, 1 means partial coverage, cancellation, timeout or I/O failure, and 2
means invalid arguments. Results before a limit/cancellation remain useful;
they must not be mistaken for a complete search. Paths/results are unsorted:
concurrent reads can change arrival order. Compare by path and byte offset.

Open Editor → Search to run a literal project query and edit a matching file.
The CLI supports include globs and case-insensitive searches; the integrated
Editor currently exposes the query only.

## Search contract

The query is a UTF-8 literal of 1–512 bytes, without NUL, CR or LF. Overlapping
matches are returned. Optional case folding changes ASCII A–Z only: Unicode
case conversion, normalization, regex and multiline queries are not implemented.
Offsets are zero-based UTF-8 byte ranges `[start,end)`; line and column are
one-based, and columns count Unicode scalars, not graphemes or display cells.
A tab counts as one scalar. CRLF bytes remain in the returned/opened file.
Preview text is bounded, escaped for display, and is never a copy/export source.

Path patterns use `/`, are case-sensitive on every platform and match the whole
relative path. `*` matches within one component, `?` matches one Unicode scalar,
`**` matches across components, and `**/` matches zero or more directory prefixes.
For example, `**/*.goose` includes both `main.goose` and `src/main.goose`.
A doubled star must occupy a whole component. Backslashes are rejected; brackets
are literal. There are no character classes, escapes, negations or Gitignore rules.

The default include is `**`. The default exclusions are `**/.git`, `**/.git/**`,
`**/node_modules/**`, `**/target/**`, `**/build/**`, `**/build-*/**` and
`**/third_party/**`. Excluded directories are pruned. The library lets callers
replace this list; CLI `--exclude` adds to it. Tracked, untracked and Git-ignored
files are eligible alike. In the viewer, this searches the current working files,
including when the preceding view was staged changes or a historical commit.

Known symlinks and special entries are outside the search policy. Unknown entry
types, unsupported paths, non-UTF-8/binary files, read failures and oversized files
are reported as skipped. Directory failure stops the search with I/O failure.
This is not a filesystem sandbox: root/ancestor links and concurrent path
replacement retain the underlying async-read semantics. Results describe files
read at different times, rather than an atomic project snapshot.

## Ownership and bounds

```goose
var search = lab_fs_search::start(root, query,
    lab_fs_search::Options { include: "**/*.goose", parallel: 4 });
if search.code != lab_fs_search::OK { /* invalid start: no live loop */ return; }
loop {
    let page = lab_fs_search::poll(search, 20);
    if page.code != lab_io_event_loop::OK { /* loop/API misuse or failure */ break; }
    for hit in page.hits { /* owned metadata; consume or retain */ }
    for issue in page.issues { /* coverage diagnostics */ }
    if page.done { /* inspect page.result and page.progress.skipped */ break; }
}
lab_fs_search::close(search);
```

The state owns a private event loop. Start/poll/cancel/close belong to the same
thread. Do not copy a live state or transfer its context to another thread.
Always close after a successful start, including after completion or error;
terminal poll preserves its result until close. Closing cancels and joins native
jobs, then invalidates their IDs. `page.code` describes the loop/API operation;
`page.result` describes the terminal search. Result pages own their metadata.

There is one directory listing, a pool of 1–8 reads (default 4), and one active
Goose scan buffer. Files are capped at 2 MiB, results at 2,048, enumerated entries
at 4,096, path bytes at 512 and depth at 32. Each poll scans at most 64 KiB of
KMP input and returns at most 32 matches and 32 issues. Native read buffers and
Goose copies are bounded by these limits; there is no unbounded file/output queue.
The root uses one slot in the 4,096-task collection, so at most 4,095 eligible
children fit. Enumerated-entry limits count entries before filters/exclusions.
Exactly reaching the match budget is allowed; seeing an additional match reports
LIMIT. Deadline defaults to 30 seconds, accepts 1–600,000 ms, and is checked
between polls. UTF-8 validation and line-coordinate work are not hard real-time
budgets. Filesystem cancellation/close can wait for outstanding OS work.

The CLI exposes parallel, match, file-byte, path, depth and deadline budgets,
plus `--cancel-after MS`. An empty query or invalid pattern starts no I/O.
Cancellation retains earlier results and releases outstanding children.

## UI and reopening

Use Find in files or Ctrl+Shift+F; enter a query, optionally change Include or
Ignore ASCII case, then Search/Enter. Stop cancels the active search. Clicking a
result or selecting with arrows/Home/End opens the current file, reveals the
matching line and selects the exact original bytes. Ctrl+C in the text view
copies that selection; Copy file copies the complete opened bytes. F5 reruns the
submitted search from the current query/options. Working tree/Staged/History
returns to Git views. Search mode pauses automatic Git refresh; it does not
silently rerun on filesystem changes. Run Search again for a new observation.

`lab.fs.search_client` is a sample adapter with owned Job/Update messages, a serial,
one cancellation token and one latest queued request. Acknowledgements permit
only one unacknowledged nonterminal page, so a stalled UI cannot accumulate all
results. Cancel/deadline bypass the acknowledgement wait. The search worker is
independent of the Git/file-opening worker. Their typed queues assume one viewer
instance per process; this adapter is not a general multi-client dispatcher.

The `open_hit(root,hit,query,options)` library helper returns owned current-file
bytes only if the query still occurs at the recorded byte range. That check is
not a whole-file revision check. The workbench instead opens through
`lab.document.workspace`: it checks the match against the adopted document,
selects it if valid and otherwise reports “Search position changed” while keeping
the opened file available for editing. The workbench caps visible results at 256;
the shared scanner's default budget is 2,048.

## Shared utilities

`lab.text.literal_search` is incremental KMP with a caller-owned cursor, input budget
and 32-match pages. The displayed-text search uses it too.
`lab.fs.glob` is a bounded Unicode-scalar matcher with explicit slash semantics;
it needs no filesystem or GUI. These are useful beyond the search sample.

See [validation](../validation.md) for scan budgets, cancellation and reopening checks.
