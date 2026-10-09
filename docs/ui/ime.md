# IME composition in shared Goose controls

The modern samples paint conversion text inline in shared `lab.ui.controls.field` and
`lab.ui.views.editor`. Committed text stays unchanged until an SDL text-input commit.
The OS still owns the candidate list. This is available in both editors, Task
Inbox, API Browser, the Git viewer's fields and the component samples.

## Platform boundary

Call `gfx::text_transactions(true)` **before** `gfx::open` or `open_headless`.
All modern sample entry points do so. It sets SDL's
[implemented IME UI hint](https://wiki.libsdl.org/SDL3/SDL_HINT_IME_IMPLEMENTED_UI)
to `composition`, leaving candidates native. Windows SDL needs that capability
to send application-drawn preedit events; merely handling the event in Goose
would leave the OS composition window in use. `lab_ui_view::frame` also ensures
transaction routing is enabled, but cannot replace the pre-open configuration
for every platform. Close resets the opt-in policy and its hint.

Default gfx clients retain scalar `EVENT_TEXT` events. Opted-in clients receive:

- `EVENT_TEXT_EDITING`: preedit UTF-8 and selection `start`/`length` in scalars.
- `EVENT_TEXT_COMMIT`: the full UTF-8 string from one SDL text-input event.

Events carry a small token, not a fixed-size string or a borrowed C pointer.
`gfx::text_event_into(token, out)` returns the complete byte count and copies
the fitting prefix. Consumers query the length, enforce their own budget, then
copy the entire payload. Tokens expire on the next frame or close. A zero token
signals overflow; a stale/invalid token returns -1. The native arena grows
only with input, up to 64 KiB per frame, including four-byte length records.
No control applies a partially copied commit. Changing this packed Event ABI
requires rebuilding Goose programs and the native gfx library together.

`gfx::text_input` starts/stops SDL input only on transitions. Repeating a frame
does not restart an ongoing conversion. Controls pass their virtual caret to
`gfx::text_input_area` in screen pixels; gfx converts those coordinates to SDL
window units and avoids repeated identical platform calls. Candidate placement
uses [SDL_SetTextInputArea](https://wiki.libsdl.org/SDL3/SDL_SetTextInputArea).

## Ownership and editing

`lab.ui.input.composition` owns at most 512 bytes of preedit, its replacement byte range,
the preedit's selected byte range, a document revision and a serial. The bounded
inline value fits Goose's existing control-state bank without a native owner
or variable-size record mutation. The bank's 32 possible fields add at most
16 KiB of preedit storage. A gfx Event adds 16 bytes; the 4,096-event interaction
buffer adds 64 KiB rather than megabytes of inline strings.

The [SDL editing event contract](https://wiki.libsdl.org/SDL3/SDL_TextEditingEvent)
counts Unicode scalars, not source bytes or graphemes. The shared helper converts
to UTF-8 byte offsets, clamps oversized offsets, and uses the end for an unset
cursor. IME selection may intentionally lie inside a grapheme. Normal user
movement/deletion remains grapheme-aware after confirmation.

Preedit saves the current replacement selection and never edits the document.
Fields shape the complete virtual string; the editor retains one additional
owned layout of the composed line, replacing its selected bytes virtually.
An unchanged preedit reuses that layout, including when only its selection changes. When a selection spans lines, its first
line previews the joined prefix, preedit and last-line suffix; selected intervening
rows are temporarily omitted while the source line positions remain unchanged.
The committed edit then recomputes real rows. Preview is limited to the existing
1 MiB layout budget; an oversized preview is rejected explicitly.

Both controls paint a conversion underline, its selected segment and a caret
one physical pixel wide. Only the focused control reports candidate geometry.
The editor shows/reveals the first replacement line and follows the virtual
caret horizontally. Saves and search see committed bytes only; preedit stays outside
the document's dirty/close decision until confirmed.

Confirmation performs one replacement. Editor history separates that transaction
from previous and following ordinary typing. SDL on Windows sends an empty
editing event immediately before the committed string; the pending replacement
range survives that clear, so the commit still has one Undo entry. A later normal
key abandons the pending range if no commit followed.

Active conversion owns keyboard handling: Enter, Tab, navigation and application
shortcuts do not submit, move focus, insert a newline or save. Escape clears
conversion first. Clicks that move a text caret or focus, focus loss, disabled/removed controls or opening a
modal cancels it; editor document revision changes also discard stale preedit.
Focus-changing clicks and Escape drop remaining text payloads already collected
in that frame, preventing an old commit from entering the new field. The next
frame resumes ordinary input. Scrollbar movement retains the composition and
updates its candidate anchor. SDL clears native composition through
[SDL_ClearComposition](https://wiki.libsdl.org/SDL3/SDL_ClearComposition).

The [GPUI input example](https://github.com/zed-industries/zed/blob/main/crates/gpui/examples/input.rs)
was a reference for marked ranges, commit handling and reporting caret bounds.
Its UTF-16 platform conventions and entity callbacks are not copied: Goose keeps
source-byte models, SDL scalar selection metadata and immediately invoked static
functions.

## Checks and limits

Automated checks inject SDL events, covering preedit replacement, commit/rejection,
focus loss, one-step Undo and shared painting. They do not operate the Microsoft
IME candidate window. See [validation](../validation.md) for running the checks.
Native candidate placement and platform-specific behavior need manual verification.
Surrounding-text/reconversion protocols, arbitrary preedit styles, paragraph bidi
and multiline preedit are unsupported. [Color emoji](emoji.md) uses the same
shared preedit painting path.

```text
cmake --build build --config Release --target workbench
python tools/run.py workbench --file README.md
python tools/run.py workbench --root . --file README.md
```

Switch the keyboard to Japanese, enter kana, convert with Space and confirm with
Enter. The first Enter should confirm without inserting a newline; a later Enter
inserts one. Try replacing a selection, cancelling with Escape, moving focus to a
path/search field, and Undo after confirmation. The candidate popup should follow
the caret while scrolling. A stationary window should remain GPU-idle.
