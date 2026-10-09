# Commands and modal input

Git Viewer and API Browser open a shared command palette with **Ctrl+K** or
**Commands**. Type words to filter, use Up/Down or Page Up/Down to choose,
and press Enter or click a row to run it. Escape, Ctrl+K or an outside click
closes the palette. Tab/Shift+Tab move between its query and result list.
Home/End in the query continue to move the text caret; in the list they select
the first/last result. Disabled commands remain visible with a reason and
cannot execute. A disabled selection does not close the palette on Enter.

## Owned command catalog

`lab.ui.command` has no GUI dependency. A `Catalog<Action>` owns up to 64 commands:
stable nonzero ID, title, typed action, description, search keywords, optional
shortcut and current availability/reason. `add` validates lengths, single-line
UTF-8, duplicate IDs and identical shortcut descriptions before copying.
`code` reports `INVALID` or `LIMIT`; a failed catalog cannot project or execute.

```goose
var catalog = lab_ui_command::Catalog<Action> {};
assert(lab_ui_command::add(catalog, 1, "Save snapshot", Action.Save,
    "Save records, URL, filter and selection", "file disk persist",
    "S", gfx::MOD_CTRL, can_save, "A request is running"));
```

Filtering requires every space-separated word to match the title or keywords.
ASCII letters ignore case; non-ASCII text compares exactly. Results preserve
catalog order. `State.current` is a command ID, rather than a filtered index,
so query changes and catalog reordering preserve an existing selection.
The fallback is the first enabled result, or the first result if all are disabled.
`resolve` returns an owned action only when a fresh catalog still permits it.
There are no retained handlers, captured application references or native resources.

Titles are limited to 96 UTF-8 bytes, descriptions/keywords to 160 each,
shortcut names to 32 and reasons to 96. The field accepts 240 query bytes.
Shortcut names use `gfx::scancode`; composition checks physical key/modifier
duplicates within each input layer. `lab.ui.view` supports 128 bindings in a frame.

## Composition and execution

Keep `lab_ui_overlays_palette::State` in the application. Its `Config<Action>` supplies
a reserved control-ID base, scroll key, three reducer actions and a metadata
font. Base, base+1, base+2 and base+3 identify backdrop, panel blocker, query
and list; row IDs are `base + 16 + command.id`. Reserve that range and a unique
scroll key, with enough room to avoid u64 overflow. The samples use base
100000, scroll key 10 and command IDs 1–13.

Build the catalog from the current model. After `lab_ui_view::begin`, call
`lab_ui_overlays_palette::bindings(view, catalog)` for available application shortcuts and
declare Ctrl+K as the opening action. After solving/describing page controls,
call `lab_ui_overlays_palette::show(view, state, config, catalog)` at the root.
On opening, call `lab_ui_overlays_palette::open`; for palette events, call `reduce` with
a freshly built catalog. Apply `result.action` through the existing application
reducer when `result.invoked` is true. Rebuild when `result.changed` is true.

The palette closes and restores focus **before** returning an action. An action
that opens a repository editor or the response view can therefore set its own
focus. Async completion continues normally while a palette is open; availability
updates on the next description and is checked again on execution. Buttons
and reducers still enforce their own application rules for other entry points.

Git commands cover refresh, working/staged comparison, changing repository,
patch search/copy and hunk/match navigation. API commands cover fetch/cancel,
offline data, save/reload, record/response tabs, completion and clipboard export.
The catalog also supplies shortcut labels: F5, Ctrl+1/2, Ctrl+O, Ctrl+F,
F7/Shift+F7, Ctrl+Shift+C for Git; Ctrl+Enter, Ctrl+S/R, Ctrl+1/2,
Ctrl+F and Ctrl+Shift+C for API; F3/Shift+F3 for available text search results.

## Reusable modal boundary

`lab.ui.overlays.modal` can compose other dialogs independently of commands. `open` saves
the previous focus key and cancels pointer, field and scrollbar dragging;
`close` clears capture and restores that key. Reconciliation clears restored
focus if the underlying control was removed, disabled or clipped away.
`at_panel` immediately invokes a static composition block for its children.
Its full-screen backdrop dismisses on a left press; a panel blocker prevents
padding clicks from dismissing. The subsequent release cannot activate a
background button.

`lab_ui_view::modal` assigns a layer to nodes, viewports and shortcuts. Only the
last described layer registers hitboxes or receives raw input, shortcuts,
Tab focus, scrollbar dragging and wheel movement. Wheel remainder stays in
that layer. Invalid modal focus returns to the initial control, or another
visible focusable child. Window focus loss still clears capture. Compose
dialogs after solve, at the root, so page clips/translation cannot affect them.

Applications painting custom content after `lab_ui_view::frame` set
`view.defer_overlays = true`, paint their page content, then call
`lab_ui_view::paint_overlays` before rendering. This keeps raw text and diff gutters
behind the scrim/panel. With the default setting, the frame paints every layer.
Both paths use the same input boundary. Flat palette rows use the shared list's
opt-in `activate_on_click`; selection occurs on press and execution on release.

## Limits

The palette uses bounded literal word matching. Fuzzy ranking, user-defined
bindings, command history and native accessibility are unsupported. General
popup placement and menus require their own input semantics rather than a modal
backdrop. See [validation](../validation.md) for modal input isolation and focus checks.
