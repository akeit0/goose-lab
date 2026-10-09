# Color emoji and text presentation

Shared text rendering handles color emoji in labels, fields, retained editor
lines and IME preedit. Applications continue to store UTF-8; selection, deletion
and Undo retain the existing Unicode 17 extended-grapheme editing policy.
Try [samples/data/emoji.txt](../../samples/data/emoji.txt) in either editor, or the Typography
card in Component Gallery.

## Font configuration

Windows defaults to the installed Segoe UI Emoji font. Its coverage and joined
sequences depend on the installed version. Some versions expose families as
several glyphs and flags as regional letters; complete sequences still remain one
editing unit. The optional COLR v0 reference font exercises joined families and
flags with a reproducible font selection.

```text
python tools/fetch_emoji_font.py
cmake -S . -B build -DGOOSE_SOURCE_DIR=/path/to/compatible/goose -DGOOSE_LAB_EMOJI_PATH="$PWD/build/fonts/Twemoji.Mozilla.ttf"
cmake --build build --config Release --parallel 4
python tools/run.py workbench --file samples/data/emoji.txt
```

The helper fetches the unmodified [Twemoji Mozilla v0.7.0 release](https://github.com/mozilla/twemoji-colr/releases/tag/v0.7.0),
verifies its SHA-256 and writes it and an attribution notice into the ignored
`build/fonts` directory. Normal builds make no download. The emoji artwork is
credited to Twemoji contributors under CC BY 4.0; font-generation code is credited
to Mozilla Foundation under Apache-2.0. See the [upstream license](https://github.com/mozilla/twemoji-colr/blob/master/LICENSE.md).
This older reference font does not cover the entire Unicode 17 emoji repertoire.
The binary is not checked into this repository.

`GOOSE_LAB_EMOJI_PATH` selects a different locally available font; an empty
value disables the emoji face. `GOOSE_LAB_SYMBOL_PATH` selects a normal text
symbol fallback (Segoe UI Symbol on Windows), keeping text-style hearts and
symbols visible even when the emoji font has empty monochrome base outlines.
Other platforms default to empty paths and need explicit configuration.

Low-level families remain explicit:

```goose
let font = lab_ui_render_font::create_family(lab_ui_render_font::default_font(), lab_ui_render_font::default_fallback());
assert(font.id != 0);
let symbols = lab_ui_render_font::default_symbols();
if symbols.len > 0 { assert(lab_ui_render_font::add_fallback(font, symbols)); }
let emoji = lab_ui_render_font::default_emoji();
if emoji.len > 0 { assert(lab_ui_render_font::add_emoji(font, emoji)); }
// Measure, create dependent layouts, paint; close layouts before the font.
lab_ui_render_font::destroy(font);
```

`add_emoji` uses an existing family face slot and ownership, with a presentation
role rather than a separate resource type. Like `add_fallback`, call it before
measurement seals the family. `lab_ui_render_scene::create` and `add_font` configure the
ordinary fallback, symbol face and emoji face automatically; each accepts explicit
paths. Empty emoji/symbol arguments disable those additions for that family.

## Shaping and painting

Font choice uses complete Unicode 17 extended grapheme clusters. The native
streaming rules and `lab.text.grapheme` use properties generated from the same pinned,
digest-checked Unicode files. Contiguous clusters using the same face and script
are shaped together, retaining ordinary ligatures and kerning. There is no
per-scalar boundary array in native run selection.

Emoji presentation prefers faces added with `add_emoji`; ordinary text keeps
ordered fallback. U+FE0F requests emoji presentation, U+FE0E requests text, and
the Unicode `Emoji_Presentation` property supplies the default. Keycap sequences
also request emoji. Default-ignorable joiners/selectors/tags do not require their
own visible glyph. Scalar coverage alone cannot guarantee a composed sequence;
unsupported sequences retain available component or missing glyphs.

FreeType loads color glyphs with `FT_LOAD_COLOR`. Its COLR v0 layers and supported
BGRA bitmaps enter the existing RGBA atlas with premultiplied RGB. The shader
converts the filtered sample for the existing straight-alpha blend, preserving
edge color. A `Glyph.colored` flag distinguishes intrinsic color from a normal
text mask: foreground RGB tints text, while only foreground opacity affects emoji.
The [FreeType glyph documentation](https://freetype.org/freetype2/docs/reference/ft2-glyph_retrieval.html)
describes these bitmap and COLR v0 semantics; [Unicode emoji presentation](https://www.unicode.org/reports/tr51/tr51-29.html)
defines the selectors/defaults used here.

Immediate/windowed and retained layout painting share this path. Wrapping
intersects shaped break candidates with extended grapheme boundaries, so a font
that emits multiple glyphs for one emoji cannot make wrapping split the sequence.
Selection and caret changes reuse geometry and never re-shape around the selection.
For comparison, [GPUI's text system](https://github.com/zed-industries/zed/blob/main/crates/gpui/src/text_system.rs)
also separates line layout, decoration runs and cached glyph raster bounds.
Here that separation uses explicit borrowed font handles and owned line handles,
with fixed atlas/layout budgets appropriate to the existing Goose APIs.

## Ownership, memory and limits

Families have eight face slots, sixteen live family slots, a 1024×1024 RGBA
CPU atlas (4 MiB) and one GPU atlas of the same dimensions. Color adds no second
atlas. The 4096-entry glyph cache also keys text/color load policy, avoiding reuse
of a color glyph for explicit text presentation. Atlas/cache exhaustion retains
the existing capacity error behavior; eviction and additional atlas pages are
not implemented.

Immutable font file bytes are shared across sizes/families using the same path.
The reference emoji source adds about 1.41 MiB once; the Windows symbol source
adds about 2.40 MiB once. Faces and font-engine scratch storage are additional.
The retained glyph record adds a load-policy integer; layout memory still obeys
the existing 128 MiB global limit. No process-memory or long-session leak claim is
made from these counters. Repeated glyph painting keeps atlas revisions/source
bytes stable, and unchanged scenes still skip GPU work.

COLR v1 paint graphs without v0 compatibility layers, SVG fonts, PNG-compressed
bitmap fonts and arbitrary scaling of fixed bitmap strikes remain unsupported.
The build still disables FreeType's PNG dependency. A font containing v1 and v0
tables can use its v0 layers, as Segoe UI Emoji does.

See [validation](../validation.md) for whole-cluster fallback, clipboard, deletion,
Undo and injected IME checks. Native IME behavior and candidate placement require
manual checks; other platforms and runtime monitor DPI changes are unvalidated.
