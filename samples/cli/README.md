# CLI samples

Small entry points into the same libraries used by the GUI applications.
Configure `-DGOOSE_LAB_GUI=OFF` to build without the renderer; see the
[root build guide](../../README.md#build). Run commands from the repository root.

| Target | Library usage |
| --- | --- |
| `http_get` | HTTP(S) initialization, bounded response bytes and shutdown |
| `io_runner` | Process arguments, stdout/stderr, cancellation and optional directory watch |
| `files_cli` | Read/list files and publish copies atomically |
| `json_cli` | Read a top-level member or replace it with parsed JSON |
| `git_objects` | Batch object reads through Git's persistent process protocol |
| `git_history` | First-parent commits, changed files, diffs and historical blobs |
| `find_files` | Literal project search, glob filters, bounded parallel work and cancellation |

```text
cmake --build build-core --config Release --parallel
python tools/run.py --build build-core http_get https://example.com/
python tools/run.py --build build-core files_cli list samples
python tools/run.py --build build-core git_history . list
python tools/run.py --build build-core git_objects . HEAD:README.md
python tools/run.py --build build-core find_files --ignore-case -- . goose
```

Run a target without arguments for usage, except `http_get`, which fetches
`https://example.com/` by default. Git samples require Git on PATH. `files_cli copy`
and `json_cli set` write files; read/list/get operations do not. Program arguments
are passed directly rather than through a shell.

Use `python3` where that is your Python 3 command, or run executables directly.
Windows is tested; Linux/macOS still need validation. See the [library map](../../docs/libraries.md)
for API guides and native dependencies.
