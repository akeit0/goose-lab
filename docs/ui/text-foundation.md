# Unicode editing, memory and idle rendering

Fields, read-only text views and the piece-tree editor share Unicode editing
boundaries. The renderer suppresses unchanged GPU work. See also [IME](ime.md)
and [color emoji](emoji.md).

## Editing boundaries

`lab.text.grapheme` implements Unicode 17.0.0 extended grapheme boundaries from
[UAX #29 revision 47](https://www.unicode.org/reports/tr29/tr29-47.html).
This covers combining marks, CRLF, Hangul, spacing marks, prepend characters,
Indic conjuncts, emoji modifiers, variation selectors, emoji ZWJ sequences,
and Regional Indicator pairs. It does not normalize or rewrite source bytes.
Unicode 17 is pinned; upgrading data/rules is an explicit maintenance task.

- `offsets(bytes)` returns owned UTF-8 byte offsets, including zero and the end;
  invalid UTF-8 returns an empty result and false. Empty text returns `[0]`.
- `State`/`feed(cp)` scans contiguous valid scalars in one pass with constant state.
- `boundary`, `previous`, `next` borrow valid UTF-8 and require scalar positions.
- `boundary_at<Read>` uses an immediately invoked scalar accessor, with no
  retained callback/reference. `Read(at, backwards)` returns a scalar and its
  start/end byte position.

The accessor follows the partial-text context idea in Rust's
[unicode-segmentation GraphemeCursor](https://github.com/unicode-rs/unicode-segmentation/blob/master/src/grapheme.rs).
Our implementation reads through the piece tree using at most four scratch bytes,
including across leaf boundaries, rather than flattening a line/document.
It inspects additional preceding context only for Indic, emoji ZWJ and flag rules.
Very long runs of Regional Indicators or combining context can require a linear
backward scan; this is not a constant-time random-access index.

`lab_document_model::boundary`, `select`, `replace`, saved bytes and search ranges keep
UTF-8 scalar/CRLF byte contracts. `lab_document_model::grapheme_boundary`, `previous` and
`next` provide user editing units. An exact search result may deliberately select
an interior scalar range; explicit byte-range replacement retains that meaning.

Fields and both text views use grapheme boundaries for pointer hit testing and
arrow movement. Backspace/Delete from ordinary collapsed carets remove a whole
cluster. Interactive insertion which joins an existing cluster moves the accepted
caret to its end. The editor also records that caret in its undo entry.
Scalar geometry remains addressable for exact search/selection positions;
selection still never reshapes or shifts text. Retained native layouts flag
interior scalar stops in an unused high bit of their bounded source offset,
avoiding an extra retained caret array. Ligature interiors retain advance
interpolation; GDEF carets and paragraph bidi remain future work.

`tools/generate_grapheme.py` verifies SHA-256 hashes of three official Unicode
17 property files, then emits the checked-in immutable table. Normal builds need
no network or generator. ASCII and Hangul syllables use direct rules; 833 packed
ranges occupy 5,831 bytes. Generated data and the official test corpus carry the
[Unicode license](../../tools/unicode/LICENSE.txt).

## Unchanged frames

`lab.ui.render.scene` retains an explicitly owned native snapshot of the latest rendered
geometry. It compares actual bytes, not a collision-prone hash. The snapshot grows
with used quad/batch data and is freed by `scene::destroy`; copied handle values
are borrowed aliases, not independent owners.

The key includes screen recreation/open generation, size, physical scale,
background, pipeline/sampler/corner-buffer identities, font/texture identities
and current raster revisions. Exact quad and batch bytes cover glyph placement,
selection/caret, clipping, drawing order and colors. An identical scene returns
false from `scene::render`, increments `Canvas.skipped`, and performs no font
texture upload, geometry upload or screen render pass. Changes increment
`Canvas.renders`. Every changed frame redraws the complete scene; this is not
partial-damage rendering.

Canvas creation enables `gfx::present_on_demand(true)` in the lab graphics package. Continuous
presentation remains the default for other gfx clients. Successful screen render
passes request presentation automatically. Upload/compute/blit writers to the
screen must call `gfx::request_present()` explicitly. Window expose/show/restore
requests a presentation of existing pixels. Resize recreates the screen and
invalidates the scene through `screen_revision()`.

`screen_content_revision()` tracks screen render passes/recreation and explicit
requests. Each Canvas remembers its accepted value after drawing, so another
Canvas or an external screen writer cannot leave an unchanged cached scene hidden
behind different pixels. Polling, reducers and asynchronous results still run;
visible results enter the same exact comparison. CPU frame construction/polling
continues: a coordinated event wait for input and libuv work is separate work.

The counters `gfx::submit_count()` and `present_count()` count frame command-buffer
submissions and recorded swapchain blits. Upload/readback command buffers and
screenshot synchronization are outside the submit counter. An unchanged scene
avoids those uploads as well. Counters are diagnostic evidence, not Task Manager
GPU utilization measurements or a promise about the desktop compositor.

## Allocation model

Each rectangle/glyph/stroke is a 72-byte Quad instance with six shared corner
vertices. A Canvas reserves space for 10,922 quads; native scene snapshots and
GPU instance buffers grow with actual usage. Goose quad/batch arrays remain fixed
capacity. `scene::vertex(canvas,index)` inspects logical corners without allocating.
Goose's single resizable tail prevents embedding independent resizable geometry
and metadata arrays in one model.

FreeType source bytes are shared by exact path between live families and sizes.
Faces, HarfBuzz metrics and raster atlases are family-owned. Families see an
immutable source snapshot while any reference to that path remains live;
different path spellings do not deduplicate. Font-file reload requires closing
all corresponding families before recreation. Last release frees source bytes
after dependent faces are destroyed. Each family owns a 4-MiB CPU atlas and a
GPU atlas of the same dimensions.

Clay's custom break-policy offsets allocate when used, grow geometrically to
their limit and reuse capacity across frames. Its frame text buffer and arena
are bounded allocations. Retained line layouts avoid allocating complete
offscreen glyph/caret arrays every frame; see [document memory](../apps/text-editor.md#memory).

Native diagnostics distinguish font source bytes, CPU atlas bytes, Clay
arena/text/policy storage, retained layouts and scene snapshots. They exclude
Goose runtime regions, third-party transient allocations, GPU textures and driver
memory. Their sum is not total process memory.

## Profiling

```text
cmake -S . -B build -DGOOSE_LAB_BUILD_TOOLS=ON
cmake --build build --config Release --target ui_profile workbench
python tools/profile.py ui --label ui-layers
python tools/profile.py editor --label editor-memory
python tools/run.py ui_profile --stage editor --frames 240
python tools/run.py ui_profile --window --stage editor --frames 1800
```

`ui` measures isolated component stages; `editor` measures the full workbench
with small, 2 MiB and long-line documents.

The Python utility writes synthetic inputs, screenshots, logs and JSON beneath
`build/`. `--build` and `--configuration` select another build. It uses Python
stdlib only and resolves both CMake output layouts. It samples RSS on Windows,
Linux (`/proc`) and macOS (`ps`); private bytes are additional Windows data.
Absent memory samples remain absent, rather than being reported as zero. OS
measurements have different accounting and should not be compared across platforms.
Sampling includes initialization and driver/runtime costs; compare runs
with the same inputs and settings. These utilities are manual profiling tools.
Save measurements and comparisons under ignored `local/`.

## Limits and checks

CPU polling/frame construction continues while idle. Runtime monitor DPI changes,
paragraph bidi and GDEF ligature caret mapping are unsupported. Emoji-safe
editing does not guarantee configured fonts cover every joined sequence.
See [validation](../validation.md) for Unicode, selection, cleanup and unchanged-frame checks.
