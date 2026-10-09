# Font families and overflow wrapping

The modern UI shares one text provider between Clay measurement, GPU painting
and field caret/selection geometry. A `Font` owns an ordered family of up to
eight faces, a common baseline and one atlas.

## Configure a family

```goose
import std;
import lab.ui.render.font;
fn main() {
    let family = lab_ui_render_font::create_family(lab_ui_render_font::default_font(), lab_ui_render_font::default_fallback());
    assert(family.id != 0);
    // Optional additional face, before measurement or layout creation:
    // assert(lab_ui_render_font::add_fallback(family, "path/to/font.ttc", 1));
    assert(lab_ui_render_font::width(family, "Goose / 日本語 / café") > 0.0);
    lab_ui_render_font::destroy(family);
}
```

`create` creates a primary-only family. `create_family` adds one fallback and
destroys the primary if adding that fallback fails. `add_fallback` appends
another owned face, optionally selecting a zero-based face from a collection.
An unsuccessful addition leaves the existing family intact. Empty fallback
paths are accepted by `create_family` as an explicit primary-only choice.

The first `metrics`, `width`, `shape`, `fit`, or layout creation seals the
family. Later additions fail with `lab_ui_render_font::error()`. Stable metrics prevent a
font change from invalidating already calculated layout or caret geometry.
Destroy dependent layout contexts before destroying their family. Copies of
the numeric handle are aliases, not additional owners. Calls stay on the UI
thread, following the existing explicit native ownership convention.

Families have at most eight faces; there are sixteen live family slots.
Each family keeps its own 1024×1024 atlas and 4096 cached glyphs. Cache keys
include face, glyph ID and text/color load policy: IDs from different font files are unrelated.
File bytes remain owned until the corresponding FreeType face is destroyed.

The shaper selects a face covering each complete extended grapheme cluster,
preferring explicitly configured emoji faces for emoji presentation, then shapes
contiguous runs using that face and script. Base characters and their combining marks stay together. Logical
advances and original UTF-8 byte clusters remain continuous across font runs;
all glyphs use the family's maximum ascent and descent. Unsupported clusters
remain visible using the primary missing-glyph representation.

`has_glyph(font, codepoint)` checks scalar coverage in the family. It is a
diagnostic convenience, not a guarantee that every variation or emoji sequence
will shape correctly. Measurement and fitting do not rasterize or revise the
atlas; painting does.

Windows samples use Segoe UI followed by Yu Gothic Medium when available.
They also configure text symbols and emoji presentation faces; see [color emoji](emoji.md)
for `add_emoji`, selectors, supported font formats and memory limits.
`GOOSE_LAB_FALLBACK_PATH` selects another fallback during CMake setup;
an empty value disables it. `lab_ui_render_scene::create` and `add_font` also accept an
explicit fallback path. System fonts are not redistributed. Other platforms
need a locally installed fallback path and have not been validated here.

## Wrap oversized words

```goose
import std;
import lab.ui.render.font;
import lab.ui.layout.engine;
fn main() {
    let family = lab_ui_render_font::create_family(lab_ui_render_font::default_font(), lab_ui_render_font::default_fallback());
    assert(family.id != 0);
    let layout = lab_ui_layout_engine::create(family);
    assert(lab_ui_layout_engine::begin(layout, 240.0, 10000.0));
    lab_ui_layout_engine::box(layout, "description", lab_ui_layout_engine::Config {
        width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit()
    }) {
        assert(lab_ui_layout_engine::text(layout,
            "https://example.com/resources/abcdefghijklmnopqrstuvwxyz0123456789",
            lab_ui_layout_engine::WRAP_OVERFLOW));
    };
    assert(lab_ui_layout_engine::finish(layout));
    // Read wrapped lines or paint through lab_ui_view::at_paragraph.
    lab_ui_layout_engine::destroy(layout);
    lab_ui_render_font::destroy(family);
}
```

`WRAP_WORDS`, `WRAP_NEWLINES`, and `WRAP_NONE` retain their existing behavior.
`WRAP_OVERFLOW` prefers normal word boundaries, then divides only words that
cannot fit the resolved width. `WRAP_JAPANESE` adds basic Japanese kinsoku to
that overflow policy. `lab_ui_view::paragraph` and the API Browser's separately
scrolling description use `WRAP_JAPANESE`. Original text is
copied to the frame arena without inserted spaces, replacement bytes, or
changes to the application model and exported JSON.

The native Clay adapter closes the implicit root, resolves horizontal sizing,
and subdivides oversized entries in Clay's measured-word tape before its final
layout pass. This integration uses the pinned Clay internals already used by
the adapter; the dependency submodule remains unchanged. A Clay update needs
the layout contracts rerun. Parent fit heights and scroll extents include every
wrapped line; reported line widths are measured from the actual shaped bytes.
Frame-owned text addresses key independent measurement tapes, so identical
strings at different widths or with different policies cannot alter each
other's wrapping. The cache is reset before those addresses are reused.

`lab_ui_render_font::fit(font, bytes, width)` returns a fitting prefix length in UTF-8 bytes,
at a boundary shared by shaping and extended grapheme segmentation. Prefixes are reshaped at the break rather than
borrowing positions from an unbroken string. It returns at least one complete
cluster for nonempty valid text, even if that cluster alone is too wide; callers
can always make progress. Invalid inputs return -1 with a diagnostic. This is
an LTR fitting utility; prefix search assumes increasing advance widths.

## Goose-owned break policies

`lab.text.line_break` classifies basic opening/closing brackets, Japanese punctuation,
small hiragana/katakana, iteration marks and prolonged sound marks. Its pure
Goose `japanese(bytes)` returns owned increasing `u32` byte offsets and a valid
UTF-8/bounds flag. The default input limit is 256 KiB, with an optional explicit
limit up to INT32_MAX. `can_start`, `can_end`, and `allows` can also be used without
fonts, Clay or a GPU. An invalid or oversized string returns an empty array and false.

`lab_ui_render_font::fit_japanese` intersects that policy with shaped clusters. A base and
its combining marks stay together even when a scalar-level policy proposes
a boundary between them. `fit_at(font, bytes, width, offsets)` exposes the
same mechanism for caller policies; offsets must be positive and increasing.
Offsets beyond the current slice are ignored, and the hard end is implicit.

```goose
import std;
import lab.ui.render.font;
import lab.text.line_break;
fn main() {
    let font = lab_ui_render_font::create_family(lab_ui_render_font::default_font(), lab_ui_render_font::default_fallback());
    assert(font.id != 0);
    let candidates, ok = lab_text_line_break::japanese("あい、う"); assert(ok);
    let bytes = lab_ui_render_font::fit_at(font, "あい、う", lab_ui_render_font::width(font, "あい"), candidates);
    assert(bytes == 3); // Move い、 together; the next line cannot start with 、.
    lab_ui_render_font::destroy(font);
}
```

`lab_ui_layout_engine::text_at(context, bytes, offsets, tag)` copies both arrays immediately
into bounded native frame storage. Offsets here must lie within the supplied
string. The frame holds at most 262144 offsets (1 MiB) in addition to its text
arena. Tags and paragraph ownership behave exactly like ordinary text.
Candidates constrain emergency breaks inside oversized words, while explicit
spaces/newlines continue to define ordinary word and hard-line boundaries.

If no permitted cluster boundary fits, fitting returns the first permitted
one, allowing the smallest unbreakable group to exceed the width. This retains
kinsoku and guarantees progress without dropping or inserting characters.
For example, `「あ」` stays together even in a viewport narrower than that group.
Explicit hard ends remain authoritative, including malformed prose ending
with an opening bracket. This is basic horizontal punctuation/kana handling,
not a complete implementation of [JLReq](https://www.w3.org/TR/jlreq/#characters_not_starting_a_line):
no spacing compression, hanging punctuation, full Unicode break classes,
Japanese justification, halfwidth-kana rules or paired-ellipsis rules.

## Exercise it in the application

Run `api_browser`, click Example, and search for `日本語`. The Unicode record
contains Japanese and Latin text, decomposed accent/kana sequences, and a long
URL. Resize the window to see the description reflow, use arrows to position the
search caret, toggle completion, and Copy JSON to verify the original bytes.

[Grapheme editing](text-foundation.md) filters user caret hits while retaining
scalar geometry for byte-range APIs. [IME](ime.md) uses the same retained geometry;
[color emoji](emoji.md) coverage depends on the configured fonts.
Paragraph bidi, full Unicode line-break rules, hyphenation, atlas paging and
automatic system font discovery are unsupported. See [validation](../validation.md)
for shaping, wrapping and selection checks.

Primary references: [HarfBuzz clusters](https://harfbuzz.github.io/working-with-harfbuzz-clusters.html),
[FreeType character mapping](https://freetype.org/freetype2/docs/reference/ft2-character_mapping.html),
and [FreeType face creation](https://freetype.org/freetype2/docs/reference/ft2-face_creation.html).
