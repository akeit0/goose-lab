# Clay layout in Goose

`import lab.ui.layout.engine;` uses namespace `lab_ui_layout_engine::`. It is experimental and lives
in this project, outside `std`. The backend is the pinned Clay v0.14 submodule,
commit `b25a31c1a152915cd7dd6796e6592273e5a10aac`.

## Build, calculate, draw

Create one layout context with `lab_ui_layout_engine::create(font)` for a live
`lab_ui_render_font::Font`, keep it across frames, and destroy it before that font.
FreeType/HarfBuzz supply its metrics. All calls belong on the main thread;
only one layout may be built
at a time. Several completed contexts can coexist.

Inside a frame, declare containers and leaves, call `finish`, then place
components by ID. This gives input handlers the current frame's
geometry. Component calls still return events immediately; Clay does not retain
Goose blocks or callbacks.

```goose
import lab.ui.layout.engine;
import lab.ui.geometry;
import lab.ui.render.font;
import lab.ui.render.scene;
// canvas is a live lab_ui_render_scene::Canvas; create once at startup:
// let layout = lab_ui_layout_engine::create(canvas.fonts[0].font);
assert(lab_ui_layout_engine::begin(layout, 600.0, 300.0));
lab_ui_layout_engine::box(layout, "root", lab_ui_layout_engine::Config {
    direction: lab_ui_layout_engine::ROW,
    width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(),
    padding: lab_ui_layout_engine::padding(12), gap: 10,
}) {
    lab_ui_layout_engine::leaf(layout, "sidebar", lab_ui_layout_engine::Config {
        width: lab_ui_layout_engine::fixed(160.0), height: lab_ui_layout_engine::grow(),
    });
    lab_ui_layout_engine::leaf(layout, "content", lab_ui_layout_engine::Config {
        width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(),
    });
};
assert(lab_ui_layout_engine::finish(layout));
let sidebar, found = lab_ui_layout_engine::bounds(layout, "sidebar");
assert(found);
lab_ui_render_scene::fill(canvas, sidebar, float4 { 0.1, 0.1, 0.15, 1.0 });
// Register hitboxes using bounds, resolve input, then paint your components.
```

`box` executes its block immediately and pairs `open`/`close`. A nonlocal
Goose return skips `close`; finish rejects that unbalanced hierarchy.
Use explicit `open`/`close` when a scoped block does not fit the control flow.

## Sizing and text

| API | Meaning |
| --- | --- |
| `fit(min, max)` | Size from children, optionally constrained |
| `grow(min, max)` | Share available space with other growing children |
| `fixed(size)` | Exact size |
| `percent(fraction)` | Fraction in 0–1 of available parent space |
| `Config.direction` | `ROW` or `COLUMN` |
| `Config.padding`, `gap` | Insets per edge and spacing between children |
| `Config.align_x`, `align_y` | `START`, `END` or `CENTER` |

For fit/grow, `max == 0` means unbounded. Sizes and results use the same
logical units as the scene; glyph pixel alignment happens later in
the renderer. Available width controls wrapping. Text metrics come directly
from the context's text provider, without estimating widths from character counts.

Call `text(layout, value, WRAP_WORDS)` inside a box to add measured text.
`WRAP_NEWLINES` and `WRAP_NONE` are also available. Text is copied immediately
into native frame storage, so a temporary Goose string may expire before
`finish`. `line_count`/`line` expose Clay's visible wrapped text commands.
Each `line` returns owned text and an `lab_ui_geometry::Rect`; that text survives
the next frame. Draw it with `lab_ui_render_scene::text` using the same font and logical
scale. Account for scrolling in both painting and hitboxes.

## Ownership and errors

Contexts own a Clay arena and 256 KiB of text storage. Generation-checked
handles reject stale contexts. Only hashed IDs enter Clay's persistent map;
it keeps no pointer to a caller's ID string. Named IDs must be unique per
frame. Duplicate hashes are reported as duplicate IDs.

A layout supports at most 16 contexts, 1024 named elements and
1024 text elements per context/frame, and 256 KiB of text per frame. These
are explicit limits, not silent truncation. Measurements are reset each
frame because text storage is reused; preserving a measurement cache across
frames needs a separate ownership design and performance measurements.

`begin`, `open`, `close`, `text` and `finish` return success. `status` and
`error` explain failure; errors remain sticky until the next `begin`.
Always call `finish` after a successful `begin`, including when declarations
fail: it unwinds the native hierarchy and lets the next frame recover.
`bounds` returns a rectangle plus `found`; queries for IDs absent this frame
return zero/false, including IDs that existed in an older frame.

## Current boundary

The component gallery uses Clay with a shared text provider,
input system and painter. The [modern UI guide](modern-ui.md) describes it.

The binding currently exposes sizing, alignment, nesting and text wrapping.
Clay clipping, scroll state, floating elements, transitions and its full
render-command schema are not exposed. It is a layout foundation, not a
replacement editor or a complete retained UI framework.

Upstream references: [Clay v0.14](https://github.com/nicbarker/clay/tree/v0.14)
and its [C macro implementation](https://github.com/nicbarker/clay/blob/v0.14/clay.h).
The small bridge uses the macro expansion's open/configure/close functions;
review that boundary when changing the pinned revision.
