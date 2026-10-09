# Renderer and component gallery

`component_gallery` uses Clay, the fork's SDL3/GPU `gfx` layer, FreeType,
and HarfBuzz. The application model,
hit testing, component styles, clipping, geometry and draw batching live in
Goose.

Design references and their adaptations are described in [API design](../design.md).

## Run it

```text
cmake --build build --target component_gallery --config Release --parallel
python tools/run.py component_gallery
python tools/run.py component_gallery --headless --frames 3 --screenshot gallery.png
python tools/run.py component_gallery --width 560 --height 1000
python tools/run.py component_gallery --scale 1.25
```

Tab and Shift+Tab move focus. Enter/Space activate controls. Pointer presses
capture an ID; releasing outside that control cancels the click. Buttons,
switches and tabs keep their state in the sample's `Model`. Narrow windows
stack the cards, and the mouse wheel scrolls the content. Scale is explicit;
automatic monitor DPI changes are not handled.

Windows defaults to Segoe UI with Yu Gothic Medium as the Japanese fallback.
`GOOSE_LAB_FALLBACK_PATH` selects another fallback (empty disables it).
`--font path.ttf` selects another
font at runtime; `GOOSE_LAB_FONT_PATH` changes the CMake default. Linux's
default is DejaVu Sans; macOS needs a suitable font path. Those platforms have
not been validated here. The sample does not redistribute Segoe UI.

Use the build configuration in the [README](../../README.md). Add a GUI program
with `goose_lab_gui_program(name samples/name.goose)`. GUI targets do not link
HTTP unless requested explicitly.

## Frame and ownership contracts

1. Open `gfx`; create a `lab_ui_render_scene::Canvas` and its fonts. Create a
   `lab_ui_layout_engine::Context` from a live `lab_ui_render_font::Font`.
2. Begin the scene in logical units. Begin/build/finish the Clay layout.
3. Begin interaction; register stable nonzero IDs with calculated, clipped
   bounds. Registration order defines stacking; the last hitbox wins.
4. Resolve the ordered `gfx::events()` once. Input coordinates convert from
   physical pixels using the same scale as the scene. Invisible and disabled
   controls do not receive focus; a disabled top layer blocks click-through.
5. Paint components using that input state. `button` returns activation;
   `toggle` returns the resulting boolean. The caller updates its own model.
6. Render the scene. Destroy layout before its font, destroy the canvas,
   then close `gfx` when finished.

There are no escaping Goose closures, native references to model data, or
destructor-dependent lifetimes. Scoped layout blocks execute immediately.
Native font/layout handles check generations; copying a handle does not
create another owner. All GUI/text calls are main-thread calls.

See the [library map](../libraries.md) for module and native target boundaries.

`lab_ui_render_font::shape` returns owned glyph data, logical advance width and UTF-8
cluster offsets. Native measurement does not rasterize. Painting populates
a font's atlas, and a revision triggers its next GPU upload. Glyph advances
remain fractional; final glyph quads land on physical pixels even when their
parent origin is fractional. Focus rings and hover colors never move labels.

The current limits are 16 live fonts, a 1024×1024 RGBA atlas and 4096 cached
glyphs per font, 16 font assets / 10,922 quad instances / 2048 batches / 32 clips per
canvas, and 1024 hitboxes / 4096 events / 256 activations per input frame.
Native failures return a diagnostic; the high-level shape/render prototype
asserts on failures or exceeded array limits. This is not yet a recoverable
production error API. A font that exhausts its atlas needs paging or eviction.

## Current boundaries

Font families share one atlas and baseline across ordered fallback faces.
Wrapping splits oversized words at shaped clusters with basic Japanese
punctuation/kana prohibitions. See [text layout](text-layout.md),
[color emoji](emoji.md), [IME](ime.md) and [grapheme editing](text-foundation.md).
Paragraph bidi, font-provided ligature carets, atlas paging and native
accessibility are unsupported.

Rendering uses compact quad instances and adjacent batching. Exact scene
comparison suppresses unchanged GPU work; CPU frame construction continues.
The gallery is a component sample with static sidebar labels.

Applications use [UI composition](ui-composition.md) to declare layout, visual
properties, enabled state and action bindings together. The frame driver handles
input and painting as separate phases. See [validation](../validation.md) for checks.
