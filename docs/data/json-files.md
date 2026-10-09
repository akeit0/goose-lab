# Bounded JSON files

`lab.json.file` provides `load(path, limit)` and `save(path, bytes, limit)` for
small application documents. The default byte limit is 1 MiB; the maximum is
2 MiB. JSON's existing 65,536-token and 128-level limits also apply. Both calls
report `OK`, `MISSING`, `IO`, `LIMIT`, `INVALID_PATH` or `INVALID_JSON` rather
than asserting on file contents. Load exposes owned bytes only on success.

```goose
import lab.json.file;
import lab.json.codec;
let loaded = lab_json_file::load("settings.json");
if loaded.code == lab_json_file::OK {
    let doc = lab_json_codec::parse(loaded.data);
    // Validate fields and copy application-owned values before doc/data expire.
}
```

The native bridge reads at most the caller's bound, then probes one extra byte.
It does not allocate based on an untrusted file size. Windows paths are UTF-8,
converted to wide paths. The binary storage utility has
a separate 64 KiB bound.
Link `goose_lab_files` and define `GOOSE_LAB_FILES=1` for generated programs using
these calls.

Save validates JSON and the caller's limit before touching the destination.
It uses Goose's existing `os::write_file_atomic`: write a unique sibling
file, flush, close and replace the destination; failed writes remove the
new temporary file. The parent directory must exist. This is an explicit
single-writer snapshot API. It does not lock files, detect external edits,
merge concurrent writers, schedule background I/O or migrate application data.
File I/O currently runs synchronously; use a worker if large documents or a
slow filesystem make that visible in an application.
For asynchronous editing/saving, the [JSON editing CLI](json-edit.md) composes
`lab.fs.async_files` with pure field editing and prepared saves.

File validity and domain validity are separate. A settings codec or
`api_browser.snapshot` checks field types, lengths, version and relationships before
adopting any model. Its save path should perform the same checks before calling
`lab_json_file::save`. The JSON utility never returns a document borrowing an
internal temporary buffer. Returned bytes are owned; token documents and values
borrow them within a lexical scope. Session snapshots store data rather than
native handles, worker state or UI contexts.

API Browser demonstrates explicit Save, startup restoration, dirty records,
load failures that block replacement and recovery after file repair. It keeps
`changed` (local changes relative to the HTTP source) separate from `dirty`
(records not yet saved locally). Saving clears only `dirty`. UI query/selection
are captured on Save but do not independently make records dirty. This keeps
persistence semantics in the application instead of a generic UI runtime.
