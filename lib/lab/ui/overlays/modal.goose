// Shared modal lifecycle and composition; no callbacks survive description.
namespace lab_ui_overlays_modal;
import std;
import vec;
import gfx;
import lab.ui.view;
import lab.ui.geometry;
struct State { opened: bool = false, restore: u64 = 0 }
fn open<A>(view: lab_ui_view::View<A>&, state: State&, initial_focus: u64) {
    if !state.opened { state.restore = view.input.focused; }
    for &entry in view.fields.entries { entry.value.dragging = false; }
    state.opened = true; view.input.captured = 0; view.drag.id = 0; view.input.focused = initial_focus;
}
fn close<A>(view: lab_ui_view::View<A>&, state: State&) {
    if !state.opened { return; }
    state.opened = false; view.input.captured = 0; view.drag.id = 0;
    view.input.focused = state.restore; state.restore = 0;
}
fn backdrop<A>(event: lab_ui_view::Event<A>) -> bool {
    event.kind == lab_ui_view::INPUT && event.input.kind == gfx::EVENT_MOUSE_BUTTON && event.input.button == gfx::MOUSE_LEFT && event.input.down
}
// base is the backdrop/layer ID; base+1 blocks panel padding; children need
// distinct IDs. Compose at the root so ancestor scrolling cannot clip the modal.
fn at_panel<A,F>(view: lab_ui_view::View<A>&, base: u64, initial_focus: u64, panel: lab_ui_geometry::Rect, dismiss: A) {
    assert(base > 0 && base < 18446744073709551615);
    lab_ui_view::modal(view, base, initial_focus) {
        lab_ui_view::at_decoration(view, str("modal-scrim-", base), view.screen, lab_ui_view::FILL, float4 { 0.0, 0.0, 0.0, 0.60 });
        lab_ui_view::at_custom(view, str("modal-backdrop-", base), base, dismiss, view.screen, true, false);
        lab_ui_view::at_decoration(view, str("modal-panel-", base), panel);
        lab_ui_view::at_custom(view, str("modal-padding-", base), base + 1, dismiss, panel, false, false);
        F();
    };
}
