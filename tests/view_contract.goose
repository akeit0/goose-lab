import std;
import vec;
import gfx;
import lab.ui.view;
import lab.ui.layout.engine;
import lab.ui.render.scene;
import lab.ui.render.font;
import lab.ui.geometry;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.ui.overlays.palette;
import lab.ui.command;
import lab.ui.overlays.modal;
enum Action { Add, Reset, Entry, Remove }
fn mouse(x: f32, y: f32, down: bool) -> gfx::Event {
    var e = default<gfx::Event>(); e.kind = gfx::EVENT_MOUSE_BUTTON; e.button = gfx::MOUSE_LEFT; e.x = x; e.y = y; e.down = down; e
}
fn key(name: const u8[:]) -> gfx::Event { var e = default<gfx::Event>(); e.kind = gfx::EVENT_KEY; e.scancode = gfx::scancode(name) as i32; e.down = true; e }
fn text(cp: u32) -> gfx::Event { var e = default<gfx::Event>(); e.kind = gfx::EVENT_TEXT; e.codepoint = cp; e }
fn main() {
    assert(gfx::open_headless(500, 300));
    for factor in [1.0, 1.25, 1.5, 2.0] {
        let scale: f32 = factor as f32;
        var c = lab_ui_render_scene::create(lab_ui_render_font::default_font(), scale);
        var v = lab_ui_view::View<Action> { layout: lab_ui_layout_engine::create(c.fonts[0].font) };
        var enabled = true; var visible = true; var count = 0; var submits: u8[..64] = []; var rejections = 0;
        fn build() {
            lab_ui_view::begin(v, 400.0, 240.0);
            lab_ui_view::box(v, "root", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(44.0), gap: 8 }) {
                lab_ui_view::button(v, "add", 1, Action.Add, "Add", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(60.0), height: lab_ui_layout_engine::grow() }, false, enabled);
                lab_ui_view::button(v, "reset", 2, Action.Reset, "Reset", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(60.0), height: lab_ui_layout_engine::grow() });
                if visible { lab_ui_view::field(v, "entry", 3, Action.Entry, "Type", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, true, 64, true); }
            };
        }
        fn reduce(event: lab_ui_view::Event<Action>) -> bool {
            if event.kind == lab_ui_view::ACTIVATE {
                if event.action == Action.Add { count++; }
                if event.action == Action.Reset { count = 0; }
            }
            if event.kind == lab_ui_view::REJECTED { rejections++; }
            if event.kind == lab_ui_view::SUBMIT { submits.append(event.text); submits.append("|"); }
            false
        }
        lab_ui_render_scene::begin(c, 400.0, 240.0);
        let events = [mouse(20.0 * scale, 20.0 * scale, true), mouse(20.0 * scale, 20.0 * scale, false),
                      mouse(90.0 * scale, 20.0 * scale, true), mouse(90.0 * scale, 20.0 * scale, false),
                      mouse(20.0 * scale, 20.0 * scale, true), mouse(20.0 * scale, 20.0 * scale, false),
                      mouse(20.0 * scale, 20.0 * scale, true), mouse(20.0 * scale, 20.0 * scale, false)];
        lab_ui_view::frame(v, c, events, float2 { 20.0 * scale, 20.0 * scale }, true, scale, build, reduce);
        assert(count == 2 && v.input.hovered == 1);
        // A repeated paint must never repeat actions.
        lab_ui_view::paint(v, c); assert(count == 2);
        enabled = false;
        lab_ui_view::frame(v, c, [key("Return")], float2 { 20.0 * scale, 20.0 * scale }, true, scale, build, reduce);
        assert(count == 2 && v.input.focused == 0 && v.input.hovered == 0);
        enabled = true;
        let typing = [mouse(180.0 * scale, 20.0 * scale, true), mouse(180.0 * scale, 20.0 * scale, false), text(65), key("Return"), text(66), key("Return"), text(67)];
        lab_ui_view::frame(v, c, typing, float2 { 180.0 * scale, 20.0 * scale }, true, scale, build, reduce);
        assert(submits == "A|B|" && lab_ui_view::field_state(v, 3).text == "C");
        lab_ui_view::frame(v, c, [text(0x85)], float2 { 180.0 * scale, 20.0 * scale }, true, scale, build, reduce);
        assert(rejections == 1 && lab_ui_view::field_state(v, 3).text == "C");
        visible = false;
        lab_ui_view::frame(v, c, [], float2 { 180.0 * scale, 20.0 * scale }, true, scale, build, reduce);
        assert(v.input.focused == 0 && v.input.captured == 0 && v.input.hovered == 0);
        visible = true;
        lab_ui_view::frame(v, c, [], float2 { 180.0 * scale, 20.0 * scale }, true, scale, build, reduce);
        assert(lab_ui_view::field_state(v, 3).text == "C");
        lab_ui_view::forget_field(v, 3); assert(lab_ui_view::field_state(v, 3).text.len == 0);
        lab_ui_layout_engine::destroy(v.layout); lab_ui_render_scene::destroy(c);
    }
    palette_contract();
    custom_contract();
    list_contract();
    assert(gfx::misuse_count() == 0); gfx::close();
    print("Shared composition: ordered actions, field identity, focus reconciliation and scale passed");
}

fn list_contract() {
    var c = lab_ui_render_scene::create(lab_ui_render_font::default_font());
    var v = lab_ui_view::View<Action> { layout: lab_ui_layout_engine::create(c.fonts[0].font) };
    var selected: i64 = -1; var count: i64 = 100; var enabled = true; var shown = true; var changes = 0; var accept = true; var height: f32 = 100.0;
    fn build() {
        lab_ui_view::begin(v, 400.0, 240.0);
        lab_ui_view::leaf(v, "list", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(200.0), height: lab_ui_layout_engine::fixed(height) });
        lab_ui_view::solve(v);
        if shown {
            lab_ui_view::list(v, "list", lab_ui_view::ListConfig<Action> { id: 60, scroll_id: 1, count: count, stride: 20.0, selected: selected, action: Action.Add, enabled: enabled }) {
                let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(v, 1), height, 20.0, count);
                for i in range.first..range.end { lab_ui_view::at_list_item(v, str("item-", i), (100 + i) as u64, i, lab_ui_geometry::rect(0.0, i * 20.0, 180.0, 20.0), str(i)); }
            };
        }
    }
    fn reduce(e: lab_ui_view::Event<Action>) -> bool { if e.kind == lab_ui_view::SELECT && accept { selected = e.index; changes++; } false }
    lab_ui_render_scene::begin(c, 400.0, 240.0);
    lab_ui_view::frame(v, c, [key("Tab")], float2 { 0.0, 0.0 }, true, 1.0, build, reduce);
    assert(v.input.focused == 60 && selected == 0 && changes == 1);
    var repeated = key("Down"); repeated.repeat = true;
    lab_ui_view::frame(v, c, [repeated, key("Down")], float2 { 0.0, 0.0 }, true, 1.0, build, reduce);
    assert(selected == 2 && changes == 3);
    accept = false;
    lab_ui_view::frame(v, c, [key("End")], float2 { 0.0, 0.0 }, true, 1.0, build, reduce);
    assert(selected == 2 && lab_ui_view::scroll_state(v, 1).offset == 0.0 && changes == 3);
    accept = true;
    enabled = false;
    lab_ui_view::frame(v, c, [mouse(30.0, 30.0, true), mouse(30.0, 30.0, false), key("End")], float2 { 30.0, 30.0 }, true, 1.0, build, reduce);
    assert(selected == 2 && v.input.focused == 0 && changes == 3);
    enabled = true; count = 0; selected = -1;
    lab_ui_view::frame(v, c, [key("Tab"), key("Down")], float2 { 0.0, 0.0 }, true, 1.0, build, reduce);
    assert(v.input.focused == 0 && selected == -1 && changes == 3);
    count = 100;
    lab_ui_view::frame(v, c, [mouse(195.0, 6.0, true)], float2 { 195.0, 6.0 }, true, 1.0, build, reduce);
    assert(v.drag.id == 1);
    shown = false; lab_ui_view::frame(v, c, [], float2 { 0.0, 0.0 }, true, 1.0, build, reduce);
    assert(v.drag.id == 0 && v.input.captured == 0);
    shown = true; lab_ui_view::scroll_state(v, 1).offset = 500.0;
    lab_ui_view::frame(v, c, [], float2 { 0.0, 0.0 }, true, 1.0, build, reduce);
    let thumb = lab_ui_layout_scroll::thumb(lab_ui_view::scroll_state(v, 1), lab_ui_view::bounds(v, "list"), 2000.0);
    lab_ui_view::frame(v, c, [mouse(195.0, thumb.y + thumb.h / 4.0, true)], float2 { 195.0, thumb.y + thumb.h / 4.0 }, true, 1.0, build, reduce);
    height = 160.0;
    lab_ui_view::frame(v, c, [], float2 { 195.0, thumb.y + thumb.h / 4.0 }, true, 1.0, build, reduce);
    let resized = lab_ui_layout_scroll::thumb(lab_ui_view::scroll_state(v, 1), lab_ui_view::bounds(v, "list"), 2000.0);
    var motion = default<gfx::Event>(); motion.kind = gfx::EVENT_MOUSE_MOTION; motion.x = 195.0; motion.y = resized.y + resized.h / 4.0;
    lab_ui_view::frame(v, c, [motion], float2 { motion.x, motion.y }, true, 1.0, build, reduce);
    assert(v.drag.id == 1 && lab_ui_view::scroll_state(v, 1).offset > 499.99 && lab_ui_view::scroll_state(v, 1).offset < 500.01);
    lab_ui_view::forget_scroll(v, 1); assert(v.drag.id == 0);
    lab_ui_layout_engine::destroy(v.layout); lab_ui_render_scene::destroy(c);
}

fn custom_contract() {
    var c = lab_ui_render_scene::create(lab_ui_render_font::default_font());
    var v = lab_ui_view::View<Action> { layout: lab_ui_layout_engine::create(c.fonts[0].font) };
    var visible = true; var blocked = true; var removed = 0; var show_text = true;
    var label: u8[..64] = "Owned label";
    fn build() {
        lab_ui_view::begin(v, 400.0, 240.0);
        lab_ui_view::box(v, "root", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), gap: 8 }) {
            lab_ui_view::leaf(v, "viewport", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(100.0), height: lab_ui_layout_engine::fixed(80.0) });
            if show_text {
                lab_ui_view::paragraph(v, "first", "First paragraph wraps across several lines.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(100.0), height: lab_ui_layout_engine::fit() });
                lab_ui_view::paragraph(v, "second", "Second paragraph has its own lines.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(100.0), height: lab_ui_layout_engine::fit() });
            }
        };
        lab_ui_view::solve(v);
        lab_ui_view::viewport(v, "viewport", float2 { 0.0, -40.0 }) {
            if visible { lab_ui_view::at_button(v, "remove", 1, Action.Remove, lab_ui_geometry::rect(0.0, 60.0, 80.0, 44.0), label); }
            // Completely clipped controls must not enter the focus order.
            lab_ui_view::at_button(v, "outside", 2, Action.Add, lab_ui_geometry::rect(120.0, 60.0, 80.0, 44.0), "Outside");
            if blocked { lab_ui_view::at_button(v, "blocker", 3, Action.Add, lab_ui_geometry::rect(0.0, 60.0, 80.0, 44.0), "Disabled", false); }
        };
    }
    fn reduce(e: lab_ui_view::Event<Action>) -> bool {
        if e.kind == lab_ui_view::ACTIVATE && e.action == Action.Remove { removed++; visible = false; return true; }
        false
    }
    lab_ui_render_scene::begin(c, 400.0, 240.0); build();
    label = "Changed source";
    assert(v.nodes[2].text == "Owned label");
    lab_ui_view::prepare(v); lab_ui_view::prepare(v);
    assert(v.nodes[2].rect.y == 20.0); // Custom placements do not accumulate transforms.
    var first_lines = 0; var second_lines = 0;
    for i in lab_ui_layout_engine::line_count(v.layout) {
        let tag = lab_ui_layout_engine::line_tag(v.layout, i);
        if tag == 1 { first_lines++; } else if tag == 2 { second_lines++; } else { assert(false); }
    }
    assert(first_lines > 1 && second_lines > 1);
    lab_ui_view::frame(v, c, [mouse(30.0, 30.0, true), mouse(30.0, 30.0, false)], float2 { 30.0, 30.0 }, true, 1.0, build, reduce);
    assert(removed == 0 && v.input.focused == 0); // Disabled top layer blocks click-through.
    blocked = false; show_text = false;
    lab_ui_render_scene::begin(c, 400.0, 240.0);
    lab_ui_view::frame(v, c, [key("Tab")], float2 { 30.0, 30.0 }, true, 1.0, build, reduce);
    assert(v.input.focused == 1 && v.input.hits[1].bounds.w == 0.0);
    for batch in c.batches { assert(batch.clip.w <= 100.0 && batch.clip.h <= 80.0); }
    lab_ui_view::frame(v, c, [key("Return"), key("Return")], float2 { 30.0, 30.0 }, true, 1.0, build, reduce);
    assert(removed == 1 && v.input.focused == 0 && v.input.hovered == 0);
    lab_ui_layout_engine::destroy(v.layout); lab_ui_render_scene::destroy(c);
}

enum PaletteAction { Open, Query, Choose, Dismiss, Background, Run }
fn palette_contract() {
    for factor in [1.0, 1.25, 1.5, 2.0] {
        let scale: f32 = factor as f32;
        var canvas = lab_ui_render_scene::create(lab_ui_render_font::default_font(), scale);
        var view = lab_ui_view::View<PaletteAction> { layout: lab_ui_layout_engine::create(canvas.fonts[0].font) };
        var palette = lab_ui_overlays_palette::State {}; var count = 0; var background = 0; var allowed = true; var field_shown = true;
        let config = lab_ui_overlays_palette::Config<PaletteAction> { base: 100, scroll_id: 10, query: PaletteAction.Query, choose: PaletteAction.Choose, dismiss: PaletteAction.Dismiss };
        fn catalog() -> lab_ui_command::Catalog<PaletteAction> {
            var c = lab_ui_command::Catalog<PaletteAction> {};
            for i in 12 { assert(lab_ui_command::add(c, (i + 1) as u64, str("Command ", i), PaletteAction.Run, "Run this command", "execute", "", 0, allowed, "Currently unavailable")); } c
        }
        fn build() {
            lab_ui_view::begin(view, 400.0, 240.0);
            lab_ui_view::shortcut(view, "F5", 0, PaletteAction.Background); lab_ui_view::shortcut(view, "K", gfx::MOD_CTRL, PaletteAction.Open);
            lab_ui_view::box(view, "page", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }) {
                lab_ui_view::button(view, "behind", 1, PaletteAction.Background, "Behind", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(90.0), height: lab_ui_layout_engine::fixed(32.0) });
                if field_shown { lab_ui_view::field(view, "behind-field", 2, PaletteAction.Background, "Behind field", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(160.0), height: lab_ui_layout_engine::fixed(32.0) }); }
                lab_ui_view::leaf(view, "behind-list", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
            };
            lab_ui_view::solve(view);
            lab_ui_view::scroll_viewport(view, "behind-list", 1, 1000.0) {};
            let c = catalog(); lab_ui_overlays_palette::show(view, palette, config, c);
        }
        fn reduce(event: lab_ui_view::Event<PaletteAction>) -> bool {
            if event.action == PaletteAction.Open && event.kind == lab_ui_view::ACTIVATE { lab_ui_overlays_palette::open(view, palette, config); return true; }
            if event.action == PaletteAction.Background && event.kind == lab_ui_view::ACTIVATE { background++; return true; }
            let c = catalog(); let result = lab_ui_overlays_palette::reduce(view, palette, config, c, event); if result.invoked { count++; } result.changed
        }
        fn frame(events: const gfx::Event[:]) {
            lab_ui_render_scene::begin(canvas, 400.0, 240.0); lab_ui_view::frame(view, canvas, events, view.input.pointer * scale, true, scale, build, reduce);
        }
        var open_key = key("K"); open_key.mods = gfx::MOD_CTRL;
        view.input.focused = 2; view.input.captured = 1; view.drag.id = 1; lab_ui_view::field_state(view, 2).dragging = true;
        frame([open_key]); assert(palette.modal.opened && view.input.focused == 102 && view.input.captured == 0 && view.drag.id == 0 && !lab_ui_view::field_state(view, 2).dragging);
        var wheel = default<gfx::Event>(); wheel.kind = gfx::EVENT_MOUSE_WHEEL; wheel.y = -3.0;
        var motion = default<gfx::Event>(); motion.kind = gfx::EVENT_MOUSE_MOTION; motion.x = 390.0 * scale; motion.y = 230.0 * scale;
        frame([key("F5"), motion, wheel]); assert(background == 0 && lab_ui_view::scroll_state(view, 1).offset == 0.0);
        frame([key("Tab")]); assert(view.input.focused == 103);
        frame([key("Tab")]); assert(view.input.focused == 102);
        var shift_tab = key("Tab"); shift_tab.mods = gfx::MOD_SHIFT; frame([shift_tab]); assert(view.input.focused == 103);
        frame([key("Tab")]); assert(view.input.focused == 102);
        var repeated = key("Down"); repeated.repeat = true;
        frame([key("Down"), repeated, key("PageDown")]); assert(palette.selection.current == 4 && view.input.focused == 102 && lab_ui_view::scroll_state(view, 10).offset > 0.0);
        // Padding blocks dismissal, and focus is repaired before the next text event.
        frame([mouse(18.0 * scale, 20.0 * scale, true), mouse(18.0 * scale, 20.0 * scale, false), text(67)]);
        assert(palette.modal.opened && lab_ui_view::field_state(view, 102).text == "C" && lab_ui_view::field_state(view, 2).text.len == 0);
        allowed = false; frame([key("Return")]); assert(palette.modal.opened && count == 0);
        allowed = true; frame([key("Return")]); assert(!palette.modal.opened && count == 1 && view.input.focused == 2);
        // Closing on outside press cancels capture; its release cannot click Behind.
        frame([open_key, mouse(10.0 * scale, 10.0 * scale, true), mouse(10.0 * scale, 10.0 * scale, false)]);
        assert(!palette.modal.opened && background == 0 && view.input.focused == 2);
        frame([open_key]); field_shown = false; frame([key("Escape")]); assert(!palette.modal.opened && view.input.focused == 0);
        field_shown = true; view.input.focused = 2; frame([open_key, text(90), text(90), key("Return")]); assert(palette.modal.opened && count == 1);
        frame([key("Escape")]); assert(view.input.focused == 2);
        // Click the already-selected row: activation happens on release, once.
        frame([open_key]); let area = lab_ui_overlays_palette::list_rect(view.screen);
        frame([mouse((area.x + 20.0) * scale, (area.y + 12.0) * scale, true), mouse((area.x + 20.0) * scale, (area.y + 12.0) * scale, false)]);
        assert(!palette.modal.opened && count == 2);
        lab_ui_layout_engine::destroy(view.layout); lab_ui_render_scene::destroy(canvas);
    }
}
