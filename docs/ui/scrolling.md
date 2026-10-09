# Scrolling, list selection and persistent state utilities

The Scroll Lab exercises a 2,000-row selectable collection inside a scrolling
workspace. Wheel movement over the list moves its contents; movement around
the list moves the workspace. At a list boundary, only the remaining movement
reaches the workspace. Selecting a row updates the detail panel; First item
and Last item select and reveal that item. Reset scroll resets both offsets.
Drag either scrollbar, or click its track to page. Click a row or Tab into the
list, then navigate with arrows, Home/End and Page Up/Down. The selection keeps
its logical focus even when navigation replaces the visible row descriptions.

The scrolling stress launcher is test support, rather than a user sample:

```text
cmake --build build --config Release --target scroll_lab
python tools/run.py scroll_lab
python tools/run.py scroll_lab --headless --frames 3 --width 560 --height 700 --screenshot scroll-lab.png
python tools/run.py scroll_lab --scale 1.25
```

## Declare once, resolve together

After Clay layout is solved, declare a viewport with a stable nonzero identity
and logical content height:

```goose
lab_ui_view::scroll_viewport(view, "workspace", 1, content_height) {
    lab_ui_view::at_scroll_viewport(view, list_bounds, 2, count * stride) {
        let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(view, 2),
            list_bounds.h, stride, count);
        for i in range.first..range.end {
            // Declare a row at list_bounds.y + i * stride.
            // Use its stable item identity for the control ID.
        }
    };
};
```

These scopes invoke their blocks immediately. There is no stored callback.
Bounds and row coordinates are unscrolled content coordinates. Each region
inherits its parent's content translation, and its own offset moves only its
contents. Its clip intersects its translated bounds with the parent clip.
The scrollbar indicator inherits the parent's translation, so it stays fixed
within its own viewport. Hitboxes and painting use this same resolved geometry.
The default thumb is 6 logical units wide with a 14-unit pointer target.
Hover and dragging widen the visible thumb; the drag stores a grab fraction
so resizing does not change where the pointer holds it. Capture persists
outside the viewport, preserves keyboard focus and ends on release, Escape,
focus loss, viewport removal or explicit scroll-state disposal. These tests
exercise capture outside the viewport within the platform event stream;
dragging across another native window has not been manually validated.

The `lab.ui.view` frame driver routes each platform event in order and rebuilds
geometry after wheel movement. A subsequent click in the same batch sees
the updated row positions. Wheel routing uses the pointer associated with
the ordered motion/button events, rather than the frame's final pointer and
aggregate wheel delta. A 44-unit move with only 20 units left in the list
moves the list by 20 and its parent by 24. Reversing direction lets the child
consume movement again. Unrelated sibling viewports receive no remainder.

## A composite list

Use an owned configuration to describe the logical collection independently
of which rows are currently rendered:

```goose
enum Action { None, Select }
lab_ui_view::at_list(view, list_bounds, lab_ui_view::ListConfig<Action> {
    id: 4, scroll_id: 2, count: count, stride: stride,
    selected: model.selected, action: Action.Select
}) {
    let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(view, 2),
        list_bounds.h, stride, count);
    for i in range.first..range.end {
        lab_ui_view::at_list_item(view, str("row-", i), (1000 + i) as u64, i,
            lab_ui_geometry::rect(list_bounds.x, list_bounds.y + i * stride,
                list_bounds.w - 16.0, stride), str("Item ", i + 1));
    }
};
```

The reducer receives `SELECT` with an owned `event.index` and its declared
application action; it can accept, reject or map the index to a domain ID.
`selected = -1` means no selection, and empty/disabled lists are not focus stops.
The frame driver refreshes the controlled index after each request even if
the reducer returns false. Arrow key repeat works; unrelated modified keys
are left to other controls. Page size is the number of whole rows in the viewport,
with a minimum of one. Navigation clamps at the ends rather than wrapping.
From no selection, forward navigation chooses the first item, backward the last.

Entering through Tab reveals the accepted item. Keyboard navigation requests
reveal only after the reducer accepts that index, including through scrolling
ancestors. Pointer selection leaves the press/release geometry in place, so
selecting a partially visible task does not move its Edit button before release.
Enter/Space produces `ACTIVATE` for the accepted index. Task Inbox uses this
to edit the selected task; its model keeps a stable task ID while the list
configuration uses that ID's position in the current filtered result.

Rows and their nested buttons share the list's keyboard focus. Inline fields
retain their own text-editing focus. The list focus ID and each row's control
ID must be unique among controls; scroll IDs belong to a separate namespace.
No array of 2,000 focusable controls or stored item callback is needed.

## Pure utilities

| Module | Contract |
| --- | --- |
| `lab.collections.state_bank` | Up to 32 values keyed by nonzero `u64`; defaults on first access; explicit removal |
| `lab.ui.layout.viewport` | Up to 128 regions; parent indices; shared translated bounds and intersected clips |
| `lab.ui.layout.scroll` | Clamp offsets, consume movement with remainder, reveal an interval, calculate uniform-row ranges |
| `lab.text.selection` | Logical previous/next/first/last/page movement independent of rendered rows |
| `lab.ui.geometry` | Translate, intersect, test containment and recognize empty rectangles |

`ensure` returns false for an invalid/full state bank; `get` asserts that the
key exists or can be created. `lookup` returns a borrowing `T?` from the bank.
Values survive conditional omission and reordering because identities are
keys, rather than declaration positions. `remove` can swap the last entry
into the removed slot. Do not hold returned references across remove/clear;
look up the identity again. The view uses independent banks for fields and
scroll positions, with explicit `forget_field` and `forget_scroll` operations.

`visible` returns a half-open `[first, end)` range for constant row stride and
one extra row at each edge by default. Clipped rows are harmless; describing
only that range avoids declaring 2,000 components. `reveal` moves the minimum
distance needed to show an interval; oversized intervals align at their top.
These functions depend on no platform or UI backend. Task Inbox uses the
same range and scroll viewport instead of separate wheel/hitbox/thumb code.

## Limits

Scrolling is vertical, with wheel input, dragging and uniform-row keyboard
selection/reveal. Momentum, horizontal scroll viewports, variable-height rows,
multiple selection, type-to-search, general control focus reveal and native
accessibility are unsupported. See [validation](../validation.md) for routing,
capture and virtual-row checks.
