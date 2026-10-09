# Read-only text view

`lab.ui.views.text` is shared by the Git patch pane and the API Browser's Response
tab. It displays unwrapped UTF-8 text with range selection, exact copying,
vertical/horizontal scrolling and literal search. The Git app supplies diff
colors and line-number gutters; the API app supplies original response bytes.
Neither consumer implements its own text input loop.

## Ownership and composition

The application owns its source. `build(source, font)` returns bounded owned
row offsets, the maximum display width and the font identity. It stores no
source reference and does not copy the body. Keep the bytes and font unchanged
while using this metadata. On every source replacement, rebuild the Document,
call `reset(state, source)` and reset the external vertical scroll. Checking the
source length alone cannot detect replacement by different bytes of equal length.

State owns cursor/anchor byte offsets, preferred x for vertical movement,
horizontal scroll and search metadata. It retains no glyph or native handles.
The vertical offset uses an existing `lab.ui.view` scroll identity. Find query state
survives source replacement, while matches and selection are reset.

`Config<Action>` declares the text, vertical-scroll and horizontal-bar IDs,
the input action, font index, line stride and optional gutter width. Control
IDs must be distinct from all other controls in that View. Scroll IDs belong
to the separate scroll namespace. The 14-pixel horizontal-bar strip is reserved
even for short lines, keeping vertical geometry stable as content changes.

After solving layout, `at_view` registers the focus/capture region and shared
vertical scrolling. Typed `INPUT` actions carry one ordered `gfx::Event` into
`handle`; it maps raw events to state changes. `find_bar` describes the query,
result count and navigation buttons using the application's `FindConfig`.
Application actions map to `Command` values. `lab_ui_view::shortcut` supplies Ctrl+F,
F3, Shift+F3 and Escape bindings without replaying a second event loop.

After the ordinary View paints, `paint` paints visible text rows. Its static,
immediately invoked row callback receives the row index and rectangle, paints
application backgrounds/gutters and returns a text color. The source and
callback never escape the call. The ordinary label's 512-byte capacity does not
apply to text rows. See `workbench.git.viewer` and `api_browser.browser` for complete usage.

## Interaction

| Input | Result |
| --- | --- |
| Click/drag | Place the caret/select a range, including multiple rows |
| Shift+click/arrows | Extend selection |
| Left/Right | Move across UTF-8 scalar boundaries and whole CRLF terminators |
| Up/Down, Page Up/Down | Move by rows, retaining preferred x across short/empty rows |
| Home/End | Start/end of the current line |
| Ctrl+Home/End | Start/end of the document |
| Ctrl+A, Ctrl+C | Select all/copy the exact selected source bytes |
| Wheel/vertical thumb | Use the shared vertical scroll region |
| Horizontal wheel/thumb | Move horizontally, bounded by measured content width |
| Ctrl+F or Find | Open the text search bar |
| Enter, F3, next button | Select/reveal the next match, wrapping at the end |
| Shift+F3, previous button | Select/reveal the previous match |
| Escape or close button | Close Find and return focus to the text |

Escape closes the sample window when Find is already closed. Text entry,
Backspace, Delete, paste and cut do not edit the source. Copy failures are
reported by `State.copy_failed`, which the sample exposes in its status text.
Pointer motion outside the text can extend/reveal selection; autoscroll is
driven by motion events, without a stationary-pointer timer.

Tabs display as four spaces and other control scalars as dots. Row indexing
strips CR from CRLF for painting; selection and copying retain original tabs,
CRLF and final terminators. Search also operates on the source, including
control/newline bytes if a caller supplies such a query.

## Stable geometry and limits

Caret/selection positions use full-line HarfBuzz advances through
`lab_ui_render_font::geometry`, without filling the raster atlas. Display expansion maps
those positions back to original source scalar boundaries. Painting uses
`lab_ui_render_font::window`: shape the same full line, then rasterize/return only glyphs
whose ink intersects the visible horizontal window. Moving selection or the
window never reshapes a truncated prefix/suffix. Carets occupy one physical
pixel at the configured display scale.

User movement/hit testing uses extended grapheme boundaries with LTR geometry;
exact byte-range APIs retain scalar positions. Ligature interior positions use
interpolated advances. Bidirectional selection, word navigation, GDEF ligature
carets, wrapping and editing are unsupported.
It accepts 2 MiB of UTF-8 and 32,768 rows. Unsupported encoding or excess input
produces an explicit code, with no partial document. Fixed row metadata reserves
approximately 512 KiB per Document so it can be replaced in mutable Goose state.
The source itself stays in the application's single owned buffer.

When replacing the same document, `rebase(state, new_source)` retains scroll,
find text and bounded byte selection, aligns endpoints to UTF-8 boundaries,
cancels text/thumb dragging and rebuilds matches. It does not map positions
semantically across inserted/deleted lines. Rebuild Document for the new source
first and let the existing viewport clamp its scroll. Git automatic refresh
uses this path; identical bytes preserve the existing document/state instead.

Search is literal, folding ASCII letters and comparing other UTF-8 scalars
exactly. A bounded KMP prefix table avoids repeated rescanning of long patterns;
overlapping matches are supported. Above 4,096 matches the search rejects its
partial result and asks for a narrower query. The shared single-line query
field currently accepts 240 UTF-8 bytes; State can hold up to 512.

Maximum-width measurement happens on adoption. Visible lines are fully shaped
for hit testing and painting, so extremely long individual lines can still be
expensive. Existing font-atlas, vertex and batch budgets apply; large-input
latency and very large displays have not been load-tested. This is a bounded
review component, not a complete editor.

See [validation](../validation.md) for contract and integration checks.
