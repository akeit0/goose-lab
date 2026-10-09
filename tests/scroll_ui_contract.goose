import std;
import os;
import vec;
import gfx;
import lab.ui.view;
import lab.ui.render.font;
import lab.ui.geometry;
import lab.ui.layout.scroll;
import support.scroll.demo;
fn tick(app: app_scroll_demo::App&) { assert(gfx::frame()); app_scroll_demo::frame(app); assert(app.view.nodes.len < 80); }
fn point(app: app_scroll_demo::App&, rect: lab_ui_geometry::Rect) { gfx::inject_mouse((rect.x + rect.w / 2.0) * app.scale, (rect.y + rect.h / 2.0) * app.scale, 0, false); }
fn click(app: app_scroll_demo::App&, rect: lab_ui_geometry::Rect) {
    let x = (rect.x + rect.w / 2.0) * app.scale; let y = (rect.y + rect.h / 2.0) * app.scale;
    gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, true); gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, false); tick(app);
}
fn hit(app: const app_scroll_demo::App&, id: u64) -> lab_ui_geometry::Rect {
    for control in app.view.input.hits { if control.id == id { assert(!lab_ui_geometry::empty(control.bounds)); return control.bounds; } }
    assert(false); lab_ui_geometry::Rect {}
}
fn press(app: app_scroll_demo::App&, name: const u8[:]) {
    assert(gfx::inject_key(name, true)); assert(gfx::inject_key(name, false)); tick(app);
}
fn send_key(name: const u8[:]) { assert(gfx::inject_key(name, true)); assert(gfx::inject_key(name, false)); }
fn mouse(app: app_scroll_demo::App&, x: f32, y: f32, button: i64 = 0, down: bool = false) {
    gfx::inject_mouse(x * app.scale, y * app.scale, button, down); tick(app);
}
fn keyboard_contract(app: app_scroll_demo::App&) {
    click(app, lab_ui_view::bounds(app.view, "first")); assert(app.view.input.focused == 4);
    press(app, "End"); assert(app.selected == 1999 && app.view.input.focused == 4); hit(app, 2999);
    press(app, "Up"); assert(app.selected == 1998);
    press(app, "PageUp"); assert(app.selected == 1993);
    press(app, "Home"); assert(app.selected == 0 && lab_ui_view::scroll_state(app.view, 2).offset == 0.0);
    press(app, "Up"); assert(app.selected == 0);
    send_key("Down"); send_key("Down"); send_key("PageDown"); tick(app);
    assert(app.selected == 7 && app.view.input.focused == 4); hit(app, 1007);
    // There is one list stop, even though its visible row descriptors change.
    press(app, "Tab"); assert(app.view.input.focused == 1);
    assert(gfx::inject_key("Left Shift", true)); send_key("Tab"); assert(gfx::inject_key("Left Shift", false)); tick(app);
    assert(app.view.input.focused == 4 && app.selected == 7);
    // Reveal also crosses parent clips, moving just far enough to show the row.
    click(app, lab_ui_view::bounds(app.view, "last"));
    lab_ui_view::scroll_state(app.view, 1).offset = 200.0; tick(app);
    press(app, "Home"); assert(app.selected == 0 && lab_ui_view::scroll_state(app.view, 1).offset == 90.0);
    let row = hit(app, 1000); assert(row.h == 36.0);
}
fn drag_contract(app: app_scroll_demo::App&) {
    click(app, lab_ui_view::bounds(app.view, "first"));
    let inner = app_scroll_demo::inner_bounds(app); let content = app_scroll_demo::COUNT * app_scroll_demo::STRIDE;
    let thumb = lab_ui_layout_scroll::thumb(lab_ui_view::scroll_state(app.view, 2), inner, content);
    mouse(app, thumb.x + thumb.w / 2.0, thumb.y + thumb.h / 4.0, gfx::MOUSE_LEFT, true);
    assert(app.view.drag.id == 2 && lab_ui_view::scroll_state(app.view, 2).offset == 0.0 && app.selected == 0);
    mouse(app, inner.x - 40.0, inner.y + inner.h + 100.0);
    assert(lab_ui_view::scroll_state(app.view, 2).offset == content - inner.h && lab_ui_view::scroll_state(app.view, 1).offset == 0.0);
    assert(app.view.drag.id == 2 && app.view.input.focused == 4);
    mouse(app, inner.x - 40.0, inner.y + inner.h + 100.0, gfx::MOUSE_LEFT, false);
    assert(app.view.drag.id == 0 && app.selected == 0);
    mouse(app, thumb.x, thumb.y); assert(lab_ui_view::scroll_state(app.view, 2).offset == content - inner.h);
    click(app, lab_ui_view::bounds(app.view, "first"));
    // Track clicks page; they never become row selections or start a drag.
    mouse(app, inner.x + inner.w - 5.0, inner.y + inner.h - 10.0, gfx::MOUSE_LEFT, true);
    mouse(app, inner.x + inner.w - 5.0, inner.y + inner.h - 10.0, gfx::MOUSE_LEFT, false);
    assert(lab_ui_view::scroll_state(app.view, 2).offset == inner.h && app.selected == 0 && app.view.drag.id == 0);
    let moved = lab_ui_layout_scroll::thumb(lab_ui_view::scroll_state(app.view, 2), inner, content);
    mouse(app, moved.x, moved.y + 6.0, gfx::MOUSE_LEFT, true); assert(app.view.drag.id == 2);
    press(app, "Escape"); assert(app.view.drag.id == 0);
    mouse(app, inner.x, inner.y + inner.h, gfx::MOUSE_LEFT, false);
    assert(lab_ui_view::scroll_state(app.view, 2).offset == inner.h);
    mouse(app, moved.x, moved.y + 6.0, gfx::MOUSE_LEFT, true);
    assert(gfx::inject_focus(false)); assert(gfx::inject_focus(true)); tick(app); assert(app.view.drag.id == 0);
    mouse(app, inner.x, inner.y + inner.h, gfx::MOUSE_LEFT, false);
    click(app, lab_ui_view::bounds(app.view, "first"));
}
fn main() {
    let argv = args(); assert(argv.len == 2 || argv.len == 3); var scale: f32 = 1.0;
    if argv.len == 3 { let n, ok = parse_flt(argv[2]); assert(ok); scale = n as f32; }
    assert(gfx::open_headless((1000.0 * scale) as i64, (820.0 * scale) as i64));
    var app = app_scroll_demo::create(lab_ui_render_font::default_font(), scale); tick(app);
    let inner = app_scroll_demo::inner_bounds(app); let area = lab_ui_view::bounds(app.view, "workspace");
    point(app, inner); assert(gfx::inject_wheel(0.0, -1.0)); tick(app);
    assert(lab_ui_view::scroll_state(app.view, 2).offset == 44.0 && lab_ui_view::scroll_state(app.view, 1).offset == 0.0);
    // Distinct pointer positions in one frame must route each wheel event independently.
    point(app, inner); assert(gfx::inject_wheel(0.0, -1.0));
    point(app, lab_ui_geometry::rect(area.x + 4.0, area.y + 4.0, 8.0, 8.0)); assert(gfx::inject_wheel(0.0, -1.0)); tick(app);
    assert(lab_ui_view::scroll_state(app.view, 2).offset == 88.0 && lab_ui_view::scroll_state(app.view, 1).offset == 44.0);
    // The first wheel uses the previous frame's pointer, even if a later motion
    // makes the platform's final pointer land over the inner list.
    assert(gfx::inject_wheel(0.0, -1.0)); point(app, inner); tick(app);
    assert(lab_ui_view::scroll_state(app.view, 2).offset == 88.0 && lab_ui_view::scroll_state(app.view, 1).offset == 88.0);
    click(app, lab_ui_view::bounds(app.view, "reset"));
    let limit = app_scroll_demo::COUNT * app_scroll_demo::STRIDE - inner.h;
    lab_ui_view::scroll_state(app.view, 2).offset = limit - 20.0; tick(app);
    point(app, inner); assert(gfx::inject_wheel(0.0, -1.0)); tick(app);
    assert(lab_ui_view::scroll_state(app.view, 2).offset == limit && lab_ui_view::scroll_state(app.view, 1).offset == 24.0);
    assert(gfx::inject_wheel(0.0, -1.0)); tick(app);
    assert(lab_ui_view::scroll_state(app.view, 1).offset == 68.0);
    assert(gfx::inject_wheel(0.0, 2.0)); tick(app);
    assert(lab_ui_view::scroll_state(app.view, 2).offset == limit - 88.0 && lab_ui_view::scroll_state(app.view, 1).offset == 68.0);
    // Child clip follows parent movement but is intersected with the outer viewport.
    lab_ui_view::scroll_state(app.view, 1).offset = 200.0; tick(app);
    let child = app.view.regions.regions[1];
    assert(child.world.y == inner.y - 200.0 && child.clip.y == area.y && child.clip.h == 130.0);
    for control in app.view.input.hits {
        if control.id >= 1000 && !lab_ui_geometry::empty(control.bounds) {
            assert(control.bounds.y >= child.clip.y && control.bounds.y + control.bounds.h <= child.clip.y + child.clip.h);
        }
    }
    click(app, lab_ui_view::bounds(app.view, "last"));
    assert(app.selected == 1999 && lab_ui_view::scroll_state(app.view, 2).offset == limit && lab_ui_view::scroll_state(app.view, 1).offset == 0.0);
    click(app, hit(app, 2998)); assert(app.selected == 1998);
    click(app, lab_ui_view::bounds(app.view, "first")); assert(app.selected == 0 && lab_ui_view::scroll_state(app.view, 2).offset == 0.0);
    // Scrolling then clicking uses freshly translated hitboxes within that same batch.
    point(app, inner); assert(gfx::inject_wheel(0.0, -1.0));
    let row_x = (inner.x + 30.0) * scale; let row_y = (inner.y + 18.0) * scale;
    gfx::inject_mouse(row_x, row_y, gfx::MOUSE_LEFT, true); gfx::inject_mouse(row_x, row_y, gfx::MOUSE_LEFT, false); tick(app);
    assert(app.selected == 1);
    let before = lab_ui_view::scroll_state(app.view, 2).offset;
    assert(gfx::inject_focus(false)); assert(gfx::inject_wheel(0.0, -1.0)); assert(gfx::inject_focus(true)); tick(app);
    assert(lab_ui_view::scroll_state(app.view, 2).offset == before);
    assert(gfx::inject_wheel(1.0, 0.0)); tick(app); assert(lab_ui_view::scroll_state(app.view, 2).offset == before);
    keyboard_contract(app); assert(gfx::screenshot(str(argv[1], ".keyboard.png"))); drag_contract(app);
    assert(gfx::screenshot(argv[1]) && gfx::misuse_count() == 0);
    app_scroll_demo::destroy(app); gfx::close(); print("Nested scroll routing, dragging, keyboard selection/reveal and windowed rows passed");
}
