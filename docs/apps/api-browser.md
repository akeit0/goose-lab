# API Browser

API Browser takes a real feature through HTTP, JSON, an owned domain model and
the modern Goose UI. Fetch a collection, search it, select records with the
mouse or keyboard, inspect a scrollable description, change a local completion
flag, copy the complete collection as JSON, and save a local snapshot for
the next launch. Fetch and Example replace the current collection; Save keeps
the current records and their local edits on disk.

```text
cmake --build build --config Release --target api_browser --parallel 8
python tools/run.py api_browser
```

The app restores `api-browser.json` from the working directory if present,
or starts with five offline records. Fetch or Enter in the URL field
requests the displayed endpoint. The default URL is JSONPlaceholder's todos
endpoint; it is an optional live demo, not part of automated validation.
`Example` restores the offline collection. No request starts until Fetch,
Enter, or the explicit `--fetch` command-line flag.

```text
python tools/run.py api_browser --headless --frames 3 --screenshot build/api-example.png
python tools/run.py api_browser --width 560 --height 860
python tools/run.py api_browser --scale 1.25 --width 1475 --height 1025
```

`--url URL --fetch` runs a request immediately. `--frames N` finishes after N
frames, waits for any outstanding bounded request, adopts its response, then
captures the final view. `--screenshot PATH` chooses the output path. Ordinary
window close or Escape with the palette and Find closed requests cancellation, joins the worker, then shuts
down HTTP. While loading, Fetch becomes Cancel; cancelling retains the current
collection and its local changes. HTTPS uses the existing verified HTTP/TLS
adapter. See [cancellation](../io/cancellation.md) for ownership and latency limits.

Commands/Ctrl+K opens the shared [command palette](../ui/command-palette.md).
It includes Fetch/Cancel, example data, Save/Reload, tabs, completion and copying.
Disabled operations remain visible with their reason, including unsaved data
and an active request. Ctrl+Enter fetches, Ctrl+S saves, Ctrl+R reloads/checks,
Ctrl+1/2 switches Record/Response and Ctrl+Shift+C copies the encoded collection.
The palette owns keyboard/pointer input while open; HTTP completion still updates
its availability. Escape closes the palette and returns to the previous control.

## Local persistence

Use **Save** after fetching or changing records. **Reload** restores the saved
collection, URL, search text, selected ID and local-change flag. Restarting the
application restores the same snapshot without an HTTP request. There is no
automatic save on edit or close: the footer shows unsaved records. URL/search/
selection are captured when Save is pressed; changing those alone does not
mark the collection dirty. Reload is disabled while records are unsaved or a
request is active. Save and completion changes are also disabled during HTTP.

```text
python tools/run.py api_browser --data C:/work/records.json
python tools/run.py api_browser --no-data --headless --frames 3
```

`--data PATH` selects the snapshot, whose parent directory must already exist.
`--no-data` disables persistence for an isolated demo. A missing file is normal
and is not created until Save. Invalid JSON, invalid domain fields, unsupported
versions and oversized files leave the file and current records untouched and
block Save. Repair/remove the file and Reload to recover. If there are unsaved
records, Reload becomes **Check file**: a successful check enables Save and
keeps those records, rather than restoring over them. A failed write retains
records and the existing good file and offers Save again. A failed HTTP response
never writes to disk; Reload can recover the last saved collection.

The snapshot's parent directory is watched, so external atomic replacement,
deletion and recreation show a compact **Review** notice. Current records,
unsaved edits, filter and selection stay in place. Save is disabled until Review
resolves the change: **Load file** replaces the current model and unsaved edits;
**Use local** retains it and allows the next Save to replace the reviewed file;
**Later** leaves the notice pending. Invalid files disable Load/Use local and
can be repaired while the dialog stays open. Deleted files can be recreated by
Use local followed by Save. Escape dismisses Review before closing the app.

Content revisions suppress self-write notifications and detect same-size edits.
Save also checks the current file before writing, even before an event arrives.
This is local conflict detection, not locking or an atomic multi-writer
transaction. Watch failure retains manual Reload and Save's preflight check.
See [file watching](../io/file-watching.md) for bounds, native ownership and limits.

The snapshot has `format: "goose-api-browser"`, `version: 1`, session fields and
`records`. Exact i64 IDs and original Unicode strings survive encoding. Version
changes are rejected rather than guessed; migrations are not implemented.
`api_browser.snapshot` remains a sample-domain codec. See [JSON files](../data/json-files.md)
for the reusable file boundary and explicit ownership pattern.

## Data boundary

The JSON payload is either an array of records or an object containing an
`items` array. Other fields are ignored.

```json
{"items":[{"id":9007199254740993,"title":"Inspect café data","body":"Details","completed":false}]}
```

`api_browser.feed` validates at most 128 records. Each needs a unique positive i64
`id` and a non-empty, single-line `title` of at most 160 UTF-8 bytes. Optional
`body` is a string of at most 2,048 bytes; optional `completed` is a boolean.
Omitted fields become empty/false; explicit null is a schema error. Lengths
are bytes and are checked before copying into capped arrays. The whole feed
is rejected if any record fails. A failed fetch displays an empty/error state,
rather than partially adopting records. Retry Fetch or load Example to recover.

`api_browser.client` is the sample's worker protocol. Call `lab_net_http::init` on the main
thread before spawning it. There is one outstanding request: a serial guards
against stale completions. Each job owns a fresh cancellation token until its
completion is drained. Cancel keeps the old collection and local edits; a stop
message plus join gives explicit teardown even while a request is active.
HTTP is bounded at 1 MiB, eight seconds total and three seconds to connect.
Non-2xx status, transport errors, JSON failures and schema failures become
owned error messages. JSON errors include line, byte column and byte offset.

The worker parses the borrowed response body, validates it and extracts owned
records **before** the response/document expire. Queue messages contain owned
records and an owned copy of the original bounded body, not a document borrowing
the response. The UI can keep browsing/searching
the current collection during loading. Mutating/exporting records is disabled
until completion so a fetch does not silently overwrite an edit made mid-request.

## Layout and interaction

`api_browser.browser` owns the model, stable selected record ID and keyed view state.
`lab.ui.view` describes layout, enabled state, visual content and typed actions
together. Search derives IDs and maps a list selection index back to a domain
ID; the selected identity is retained when still visible. Search uses existing
ASCII case folding, with non-ASCII text compared byte-for-byte.

At logical widths below 900, the record list and details stack. The list uses
the shared virtualized uniform-row/list driver, keyboard navigation and
draggable scrollbar. Descriptions use a separate completed Clay text layout
inside a shared scroll viewport. `lab_ui_view::at_paragraph` places those wrapped
commands at the viewport origin without copying long lines into a 512-byte
label. The text context must stay valid and unchanged until paint, then can be
rebuilt for the next description. Scroll state is independent of the list and
resets when selection changes. The completion button stays outside the viewport.

The **Response** tab uses the shared [read-only text view](../ui/text-view.md). It
shows the exact HTTP body, including JSON/schema failures and non-2xx bodies.
Transport failures label any retained bytes as a partial response. Local record
edits do not rewrite it, and cancellation retains the previous body. Select/copy
a range, Ctrl+A/C to copy all, drag the horizontal scrollbar, or use Find/Ctrl+F
and Enter/F3/Shift+F3. Escape closes Find before closing the window.

Original HTTP bodies are session-only. Example and Reload instead show generated
JSON, explicitly labelled as offline or snapshot data. The Record tab retains
the existing wrapped description and local editing controls. Switching tabs
keeps record selection, with independent response scroll/selection state.
The HTTP body remains bounded at 1 MiB; generated snapshot JSON uses the shared
2-MiB text bound. Unsupported UTF-8 or excessive rows show a text-view error.

Export includes every record, even when search hides it. The structured JSON
writer preserves exact IDs and emits owned strings with proper escaping. Its
allowance is sized from the maximum domain payload, including worst-case
escaping. The clipboard copies that output before temporary storage expires;
clipboard failure leaves a visible retry message. Export is not capped at
64 KiB. Refetching replaces local edits and clears the copied indication.

Text uses the grayscale FreeType/HarfBuzz renderer with ordered font families.
Windows defaults to Segoe UI plus Yu Gothic Medium for Japanese. Oversized
words and URLs wrap at shaped cluster boundaries; descriptions contribute
their full wrapped height to scrolling. The offline Unicode record exercises
Japanese search, mixed text and a long URL. Basic Japanese kinsoku keeps
closing punctuation and small kana off soft line starts and opening brackets
off soft line ends within oversized words. See [text layout](../ui/text-layout.md)
for configuration and ownership. Color emoji, IME, full bidi, complete Japanese composition,
accessibility and atlas paging remain unfinished.

See [validation](../validation.md) for contract and integration checks.
