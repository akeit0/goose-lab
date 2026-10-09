# Modern UI composition in Goose

`lab.ui.view` is a shared authoring layer over Clay layout, Goose interaction,
fields and GPU painting. It is used by the GUI applications and component gallery.

## Declaration and execution

Keep layout, input resolution and painting as distinct execution stages.
Bring the declaration of each widget together: its identity, layout, label,
enabled state, value and application action live in one description.
Applications should not repeat those facts in layout, hitbox and paint functions.
Business rules remain in an application reducer or domain module.

The frame driver consumes each platform event once and delivers an application
action before consuming the next event. A reducer can request a rebuilt view
when hit testing, enabled state, visibility or programmatic focus changes.
Clicking Edit and typing within the same event batch therefore targets the
newly focused field. Repeated activations keep their platform order.

## What application code looks like

```goose
enum Action { None, Undo }

// Inside an application's description function:
lab_ui_view::button(view, "undo", 4, Action.Undo, "Undo",
    lab_ui_layout_engine::Config {
        width: lab_ui_layout_engine::fixed(84.0), height: lab_ui_layout_engine::fixed(42.0)
    }, false, can_undo);
```

That call declares the Clay element, visual properties, hitbox, disabled
behavior and activation binding. There is no separate registration or paint
call for this button. A reducer receives `lab_ui_view::Event<Action>`:

```goose
fn reduce(event: lab_ui_view::Event<Action>) -> bool {
    if event.kind == lab_ui_view::ACTIVATE && event.action == Action.Undo {
        // Apply an application command here.
        // Return true if subsequent input needs updated geometry/focusability.
        return true;
    }
    false
}
```

An application provides two immediately invoked functions to the frame driver:

```goose
fn describe() { build(view, model, width, height, scroll); }
fn reduce(event: lab_ui_view::Event<Action>) -> bool { action(model, event) }
lab_ui_view::frame(view, canvas, gfx::events(), gfx::mouse_pos(),
    gfx::focused(), scale, describe, reduce);
```

`build` calls `begin` and declares nested `box` scopes, controls and labels.
The driver solves layout and supplies hitboxes automatically. `solve` is
available inside a description when a custom composition needs calculated
bounds before adding positioned components. Task rows use this escape hatch:
one `at_button` rectangle supplies both hit testing and painting.

The frame driver performs an initial description/layout, routes ordered input,
rebuilds after reducers that return true, and refreshes the final description
before painting. Returning false defers presentation updates to that final
refresh; it does not discard model changes. The gallery uses false for its
fixed-geometry counters, switches and selected tabs. Task Inbox uses true when
commands can change rows, filters, enabled controls or field focus.
List `SELECT` requests always refresh the description after reduction so the
next key sees the accepted index. Keyboard reveal follows that accepted
selection; a reducer can reject a request without moving the scroll position.

## State and ownership

A `View<Action>` belongs to the application and holds transient descriptors,
interaction state, and separate banks of field and scroll states identified
by nonzero `u64` IDs. These use the backend-independent `lab.collections.state_bank` utility.
`field_state(view, id)` exposes a draft when the controller needs to start an
edit or examine a search. Conditional removal clears focus/capture while
preserving the draft. `forget_field` explicitly disposes a field identity;
call it when the application no longer needs that draft.
`scroll_state` and `forget_scroll` provide the equivalent scroll lifecycle.
The same numeric ID can occur in the field and scroll banks, but each declared
scroll viewport has a distinct ID. Do not retain state references across
disposal: removing a key can reuse its slot for a different logical identity.

Descriptors copy labels, names and fixed-size action values. No callback,
borrowed label or application pointer survives declaration. Goose's static
function parameters support nested composition and the frame driver without
runtime closures. Scoped `box`/`viewport` blocks must finish normally: a
nonlocal return can skip their matching close/restore, as in the lower-level
layout API. Validate before opening scopes. Actions must be fixed-size, have a default, and own their
payloads. An enum with a payload-free `None` first variant is convenient.
Goose optionals are nullable references, so `Action?` would not be an owned
optional value; the implementation deliberately stores `Action` by value.

Construct a Clay context from the canvas's base font, assign it to `view.layout`,
and destroy that layout before destroying the canvas. The frame driver manages
platform text-input enablement according to the focused field. Native resources
still have explicit lifetimes; this layer does not add an ownership mechanism
to Goose.

## Shared behavior

- `button`, `toggle`, and `field` declare interactive Clay leaves once.
- `label` declares a fixed-layout label; `paragraph` measures and paints wrapped
  text with the same base font. Numeric native tags associate each paragraph's
  wrapped lines with its owner without retaining a caller pointer.
- `viewport` supplies stationary clipping and a content offset to both hit
  testing and painting. Nested viewports accumulate parent offsets and intersect
  ancestor clips. Fully clipped controls do not enter the focus order.
- `scroll_viewport` and `at_scroll_viewport` declare vertical scrolling after
  `solve`, with a stable ID and content height. They clamp persistent state,
  apply the offset to contents, and declare a stationary draggable scrollbar.
  The frame driver routes ordered wheel events to the visible region under
  each event's pointer, then passes unconsumed movement to its ancestors.
- `list` and `at_list` combine that viewport with an owned `ListConfig<Action>`:
  focus ID, scroll ID, count, stride, selected index and application action.
  `at_list_item` declares visible rows with stable control IDs. The list has
  one keyboard focus target, independent of the current row window. Arrows,
  Home/End and Page Up/Down request selection and reveal it through ancestor
  scroll areas. Enter/Space activate the accepted selection.
- `at_button`, `at_label` and `at_decoration` compose positioned controls and
  visuals after layout. Checkbox painting is a reusable component.
- Field changes, submits and rejected edits carry their declared application
  action. Submit events own a text snapshot, so later typing cannot change it.
- Final reconciliation clears stale focus/capture and recalculates hover from
  final geometry. It does not replay events or produce new activations.
- Painting dispatches no actions and never toggles application values.

Control IDs are unique within a view and must survive reordering/filtering.
Scrollbar capture uses the scroll-state identity namespace; it reserves no
application control IDs and preserves the current field/list focus. Track
clicks page by one viewport height. Release, focus loss, Escape, disposal or
removal of the viewport cancels capture. Its wider pointer target uses the
same clip as the painted thumb, and an active drag continues outside the viewport.
Clay names are unique within a layout. Keyboard traversal follows component
declaration order, skipping disabled and fully clipped controls. A composite
list owns the focus for its rows and nested buttons; inline fields retain
their own editing focus. Later
interactive declarations sit above earlier ones; disabled controls block
click-through. Decoration nodes do not intercept input.

The execution phases follow [GPUI and Clay](../design.md#references), adapted to
Goose's value and ownership model. One frame owns its descriptions; persistent
field/scroll state is keyed by stable identity.

## Limits

This remains an experimental API. A view allows 1024 descriptors, 32 persistent
field identities, 32 persistent scroll identities, 32 list descriptions, 128 viewport regions,
96 UTF-8 bytes per name and 512 bytes per label/placeholder.
The underlying Clay bridge has its own 1024 named-element and 256 KiB frame-text
budgets. Paragraph text is copied into that native frame arena rather than the
label buffer. Capacity violations currently assert; these budgets are not a
production recovery policy. IDs for changing field sets need explicit disposal.

`at_paragraph` places a separate completed Clay text context at a custom
rectangle's origin and inherits viewport translation/clipping. It avoids
copying wrapped lines into small labels. Keep that context alive and unchanged
until paint; destroy it explicitly after the view is finished. The
[API Browser](../apps/api-browser.md) uses this for independently scrolling descriptions,
including lines longer than the label budget.

Nested vertical wheel/drag scrolling and uniform-row keyboard selection/reveal
are supported. Horizontal text scrolling is provided by the text/editor views;
general scroll viewports are vertical. Momentum, general control focus reveal,
multiple selection and native accessibility are unsupported.
See [scrolling](scrolling.md), [IME](ime.md) and [text layout](text-layout.md).

The driver can rebuild layout for each action that changes input geometry.
The gallery performs a preliminary layout to calculate application-managed
scroll limits; shared scroll viewports derive limits from declared content height.

## Custom controls and overlays

The [tree view](tree-view.md) adds an opt-in hierarchical list protocol.
Pointer selection carries its origin; Left/Right produce expansion intents
only for hierarchical lists. `lab.ui.views.tree` owns generic tree reduction and
virtual-row composition, while the Git app maps leaf data to diff requests.
Disclosure chevrons use shared vector painting instead of font symbols.
`ListConfig.framed` defaults to true for existing lists; trees opt out and use
compact borderless rows with background-only selection/hover feedback.

`at_custom` registers a focus/capture region and emits typed `INPUT` events
with one raw platform event for its reducer. It does not paint or activate on
Enter/Space. Release events retain the prior capture target even outside the
hitbox, allowing composed drag controls to end their drag correctly. The
shared text view uses this for source selection and its horizontal thumb.
`shortcut` declares an exact key/modifier action for the current description;
it takes precedence over the focused control and consumes that key once.
Bindings disappear with the control description. See [text view](text-view.md).


The [command palette and modal layer](command-palette.md) provide shared
input isolation across both viewers. Nodes, shortcuts and scroll regions carry
a description layer; only the top modal receives input, while every layer paints.
This also traps Tab focus and wheel remainder, rather than relying on a backdrop
hitbox alone. `lab.ui.overlays.modal` owns open/close focus restoration and capture cancellation.
`ListConfig.activate_on_click` opts into release activation for command rows;
existing selection-only lists retain their behavior. Shortcut repeat is opt-in.
Custom page painters can defer overlays until after their content is painted.

See [validation](../validation.md) for ordered actions, focus/capture and clipping checks.
