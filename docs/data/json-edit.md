# JSON field editing with asynchronous saving

`lab.json.edit` changes one top-level object member without decoding and
reserializing unrelated fields. `json_cli` connects this pure Goose utility to
async reads and prepared atomic saves. It demonstrates configuration-file
publication policy above the shared I/O mechanisms, without a UI.

## Try it

```text
cmake --build build-core --config Release --target json_cli json_contract --parallel
./build-core/Release/json_cli.exe get settings.json compact
./build-core/Release/json_cli.exe set settings.json compact true
./build-core/Release/json_cli.exe set settings.json retries 3
./build-core/Release/json_cli.exe --cancel-after 0 set settings.json compact false
```

The file must already exist and have an object root. `get PATH KEY` prints the
member's exact JSON representation followed by LF, or fails when absent.
`set PATH KEY JSON` replaces a member or inserts it when absent. JSON is a
complete fragment: `true`, `3`, `null`, an array/object or a quoted JSON string.
Shell quoting must preserve those JSON quotes. In Windows PowerShell a literal
string argument can be passed using stop-parsing syntax:

```text
./build-core/Release/json_cli.exe --% set settings.json theme "\"dark\""
```

Key names are literal decoded strings. `editor.tabSize` refers to one key with
a dot in its name, not a nested path. The default file/output limit is 1 MiB;
`--limit BYTES` accepts 1..2097152. Token/depth bounds default to 65,536/128.
Exit codes are 0 for success/no change, 1 for operation/edit failure, and 2 for
invalid command usage. Diagnostics and save receipts go to stderr; successful
set emits no payload to stdout.

## Pure editing API

```goose
import lab.json.edit;

let result = lab_json_edit::set(
    "{\"compact\":false,\"future\":{\"id\":900719925474099312345}}",
    "compact", "true");
if result.code == lab_json_edit::OK {
    // result.bytes owns complete JSON; result.changed is a byte-level edit.
}
```

`set(source, key, value, limits=lab_json_codec::Limits {})` validates source and fragment,
locates the decoded key, and substitutes only the value token's byte range.
The original key spelling, surrounding whitespace, unknown members, number
spelling and nested data remain byte-for-byte intact. Adding a missing member
inserts an escaped key/value before the root closing brace. This is not a
formatter or domain schema validator. New fragments keep their supplied
representation and whitespace; semantically equivalent but differently spelled
values still count as edits.

`Edited { code, error, changed, bytes }` owns its output. On failure, bytes is
empty and changed is false. Codes distinguish malformed source, malformed value,
non-object root, ambiguous duplicate target keys, invalid UTF-8 key and limits.
`error` retains JSON error code/byte offset when relevant. SOURCE offsets refer
to source, VALUE offsets to the fragment, and combined validation limits can
refer to the constructed output. Non-parser errors have no meaningful offset.
`message(code)` explains the edit error.

`find(document, key)` returns `Match { code, index }`, with index -1 and OK for
absence. The index selects a value token in that same borrowed document.
It rejects multiple decoded matches, including `"a"` and `"\u0061"`, rather
than silently editing one occurrence. Unrelated duplicate keys are preserved;
the general JSON parser's duplicate acceptance remains unchanged.

Both inputs are validated separately, then the complete output is checked.
Combining valid inputs can exceed token/depth limits. Output length is checked
before constructing the full output. An exact existing value match returns
unchanged owned bytes; the CLI avoids creating a save job in that case.
Documents/values never borrow an internal buffer that escapes the function.
The utility needs no native library; imports are only std, JSON and UTF-8.

## File lifecycle and external changes

The CLI uses the existing shared-loop contracts:

1. Read owned source bytes asynchronously and validate/edit them in Goose.
2. Prepare a complete sibling temporary with file-data sync enabled.
3. At ready, read the destination again and compare exact bytes to the original
   read. Refuse publication if it changed or the re-read failed.
4. Commit, drive/drain the write receipt, then explicitly close the context.

Application codecs can validate field types, versions and relationships before
step 2. Adoption/edit decisions stay in Goose and native request lifetimes below
them. The utility does not invent a self-referencing object containing owned
source and JSON values borrowing that source.

The pre-commit comparison detects changes observed before publication, including
whitespace-only edits. It is not compare-and-swap: another writer can change
the file after that read and before rename. No lock, watcher or transaction is
claimed. Reads are observations rather than filesystem snapshots. The CLI does
not create a default configuration on a failed/missing read. Missing keys can
be inserted into a successfully loaded object.

A cancellation timer spans the whole operation. Before publication, cancellation
or rejection cancels and removes the prepared file. If rename already succeeded,
the save receipt reports success even if cancellation was requested. Cleanup
failures and remaining staging paths are reported. Synchronous close can wait
for executing OS work. Publication, file-data sync, metadata replacement and
power-loss limitations remain those in [atomic saves](../io/atomic-save.md).

JSON parsing/editing is synchronous bounded CPU work on the owner thread;
only filesystem requests run in libuv's worker pool. A timer cannot interrupt
an executing parse. UI adapters can move pure JSON processing to a Goose worker
if their actual workload requires it, transferring owned data at that boundary.

See [validation](../validation.md) for contract and integration checks.
