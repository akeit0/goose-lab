// A Goose component/scene prototype. Only gfx, Clay, FreeType and HarfBuzz.
import std;
import os;
import math;
import vec;
import gfx;
import lab.ui.geometry;
import lab.ui.render.font;
import lab.ui.layout.engine;
import lab.ui.render.scene;
import lab.ui.view;
import lab.ui.controls.components;

struct Model { notifications: bool = true, compact: bool = false, clicks: i64 = 0, tab: i64 = 0 }
enum Action { None, Create, Reset, Notifications, Quiet, Tab { index: i64 } }
fn build(view: lab_ui_view::View<Action>&, model: const Model&, width: f32, height: f32, scroll: f32) {
    lab_ui_view::begin(view, width, height, max(height, 1250.0));
    let theme = lab_ui_controls_components::Theme {};
    let labels: const u8[:][3] = ["Overview", "States", "Details"];
    let narrow = width < 900.0;
    lab_ui_view::box(view, "root", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }) {
        if !narrow { lab_ui_view::decoration(view, "sidebar", lab_ui_view::FILL, theme.surface); lab_ui_view::leaf(view, "sidebar", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(220.0), height: lab_ui_layout_engine::grow() }); }
        lab_ui_view::viewport(view, "main", float2 { 0.0, -scroll }) {
            lab_ui_view::box(view, "main", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), padding: lab_ui_layout_engine::padding(32), gap: 20 }) {
                lab_ui_view::label(view, "kicker", "COMPONENTS   /   NATIVE PREVIEW", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) }, 3, theme.muted);
                lab_ui_view::label(view, "title", "Make it feel like Goose.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(44.0) }, 1, theme.text);
                lab_ui_view::paragraph(view, "description", "A native interface built in Goose. Clay arranges the pieces; Goose owns the pixels and interaction.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit() });
                lab_ui_view::box(view, "tabs", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit(), gap: 8 }) {
                    for i in 3 { lab_ui_view::button(view, str("tab-", i), (10 + i) as u64, Action.Tab { index: i }, labels[i], lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(0.0, 120.0), height: lab_ui_layout_engine::fixed(40.0) }, model.tab == i); }
                };
                lab_ui_view::box(view, "cards", lab_ui_layout_engine::Config { direction: if narrow { lab_ui_layout_engine::COLUMN } else { lab_ui_layout_engine::ROW }, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit(), gap: 20 }) {
                    lab_ui_view::decoration(view, "interaction-card");
                    lab_ui_view::box(view, "interaction-card", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit(), padding: lab_ui_layout_engine::padding(24), gap: 16 }) {
                        lab_ui_view::label(view, "interaction-heading", "Actions", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(30.0) }, 2, theme.text);
                        lab_ui_view::label(view, "interaction-note", "Pointer, keyboard, and visible focus.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) }, 3, theme.muted);
                        lab_ui_view::button(view, "primary", 1, Action.Create, "Create something", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(44.0) }, true);
                        lab_ui_view::button(view, "secondary", 2, Action.Reset, "Reset counter", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(44.0) });
                        lab_ui_view::button(view, "disabled", 3, Action.None, "Unavailable", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(44.0) }, false, false);
                    };
                    lab_ui_view::decoration(view, "settings-card");
                    lab_ui_view::box(view, "settings-card", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit(), padding: lab_ui_layout_engine::padding(24), gap: 16 }) {
                        lab_ui_view::label(view, "settings-heading", "Preferences", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(30.0) }, 2, theme.text);
                        lab_ui_view::label(view, "settings-note", "State belongs to the application.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) }, 3, theme.muted);
                        lab_ui_view::toggle(view, "notifications", 4, Action.Notifications, "Notifications", model.notifications, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(44.0) });
                        lab_ui_view::toggle(view, "compact", 5, Action.Quiet, "Quiet mode", model.compact, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(44.0) });
                        lab_ui_view::label(view, "state", str(model.clicks, " creations  /  ", if model.notifications { "notifications on" } else { "notifications off" }), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(44.0) }, 3, theme.muted);
                    };
                };
                lab_ui_view::decoration(view, "type-card");
                lab_ui_view::box(view, "type-card", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit(), padding: lab_ui_layout_engine::padding(24), gap: 12 }) {
                    lab_ui_view::label(view, "type-heading", "Typography", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(30.0) }, 2, theme.text);
                    lab_ui_view::label(view, "type-sample", if model.tab == 1 { "Hover · press · focus · disable" } else if model.tab == 2 { "Describe → layout → actions → paint" } else { "Office · affinity · café · Ελληνικά" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(30.0) }, 2, theme.text);
                    lab_ui_view::label(view, "type-note", "HarfBuzz shaping + FreeType glyphs, aligned to physical pixels.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) }, 3, theme.muted);
                    lab_ui_view::label(view, "emoji-sample", "日本語 · 😀 👍🏽 👨‍👩‍👧‍👦 🇯🇵 · ❤︎ ❤️", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0) }, 2, theme.text);
                };
                lab_ui_view::label(view, "footer", "Tab to move focus. Enter or Space to activate. Scroll to explore.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(22.0) }, 3, theme.muted);
            };
        };
    };
    lab_ui_view::solve(view);
    describe_sidebar(view, height);
}
fn describe_sidebar(view: lab_ui_view::View<Action>&, height: f32) {
    let sidebar, present = lab_ui_layout_engine::bounds(view.layout, "sidebar");
    if !present { return; }
    let theme = lab_ui_controls_components::Theme {};
    lab_ui_view::at_label(view, "brand", lab_ui_geometry::rect(24.0, 29.0, 180.0, 24.0), "GOOSE", 2);
    lab_ui_view::at_label(view, "brand-note", lab_ui_geometry::rect(24.0, 62.0, 180.0, 20.0), "INTERFACE LAB", 3, theme.muted);
    lab_ui_view::at_decoration(view, "sidebar-selected", lab_ui_geometry::rect(16.0, 126.0, sidebar.w - 32.0, 42.0), lab_ui_view::FILL, float4 { 0.13, 0.12, 0.25, 1.0 });
    lab_ui_view::at_label(view, "sidebar-components", lab_ui_geometry::rect(32.0, 136.0, 170.0, 24.0), "Components", 0, float4 { 0.70, 0.67, 1.0, 1.0 });
    lab_ui_view::at_label(view, "sidebar-layout", lab_ui_geometry::rect(32.0, 190.0, 170.0, 24.0), "Layout", 0, theme.muted);
    lab_ui_view::at_label(view, "sidebar-type", lab_ui_geometry::rect(32.0, 238.0, 170.0, 24.0), "Typography", 0, theme.muted);
    lab_ui_view::at_label(view, "sidebar-motion", lab_ui_geometry::rect(32.0, 286.0, 170.0, 24.0), "Motion", 0, theme.muted);
    lab_ui_view::at_label(view, "version", lab_ui_geometry::rect(24.0, height - 62.0, 180.0, 24.0), "Experimental / v0.1", 3, theme.muted);
}
fn action(model: Model&, event: lab_ui_view::Event<Action>) -> bool {
    if event.kind != lab_ui_view::ACTIVATE { return false; }
    match event.action {
        Create => { model.clicks++; }, Reset => { model.clicks = 0; },
        Notifications => { model.notifications = !model.notifications; },
        Quiet => { model.compact = !model.compact; }, Tab t => { model.tab = t.index; }, None => {},
    }
    false
}
fn main() {
    let argv = args(); var frames: i64 = -1; var headless = false;
    var width: i64 = 1280; var height: i64 = 860; var scale: f32 = 1.0;
    var screenshot: u8[..2048] = "component_gallery.png";
    var path: u8[..4096] = []; path.append(lab_ui_render_font::default_font());
    var i = 1;
    while i < argv.len {
        if argv[i] == "--headless" { headless = true; }
        else if argv[i] == "--frames" && i + 1 < argv.len { i++; let n, ok = parse_int(argv[i]); if ok && n > 0 { frames = n; } }
        else if argv[i] == "--width" && i + 1 < argv.len { i++; let n, ok = parse_int(argv[i]); if ok && n >= 480 && n <= 8192 { width = n; } }
        else if argv[i] == "--height" && i + 1 < argv.len { i++; let n, ok = parse_int(argv[i]); if ok && n >= 320 && n <= 8192 { height = n; } }
        else if argv[i] == "--scale" && i + 1 < argv.len { i++; let n, ok = parse_flt(argv[i]); if ok && n >= 0.5 && n <= 4.0 { scale = n as f32; } }
        else if argv[i] == "--screenshot" && i + 1 < argv.len { i++; screenshot.resize(0); screenshot.append(argv[i][..min(argv[i].len, 2048)]); }
        else if argv[i] == "--font" && i + 1 < argv.len { i++; path.resize(0); path.append(argv[i][..min(argv[i].len, 4096)]); }
        i++;
    }
    gfx::text_transactions(true);
    assert(if headless { gfx::open_headless(width, height) } else { gfx::open("Goose / Interface Lab", width, height, gfx::WINDOW_RESIZABLE) });
    var canvas = lab_ui_render_scene::create(path, scale);
    guard canvas.fonts.len > 0 else { write_stderr(str("font: ", lab_ui_render_font::error(), "\n")); gfx::close(); return; }
    assert(lab_ui_render_scene::add_font(canvas, path, 30.0) == 1);
    assert(lab_ui_render_scene::add_font(canvas, path, 20.0) == 2);
    assert(lab_ui_render_scene::add_font(canvas, path, 13.0) == 3);
    var view = lab_ui_view::View<Action> { layout: lab_ui_layout_engine::create(canvas.fonts[0].font) }; assert(view.layout.id != 0);
    var model = Model {}; var scroll: f32 = 0.0; var drawn: i64 = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") { break; }
        let size = gfx::screen_size(); let w: f32 = size.x / scale; let h: f32 = size.y / scale;
        lab_ui_render_scene::begin(canvas, w, h); build(view, model, w, h, scroll);
        let footer = lab_ui_view::bounds(view, "footer");
        scroll = clamp(scroll - gfx::mouse_wheel() * 42.0, 0.0, max(0.0, footer.y + footer.h + 32.0 - h));
        fn describe() { build(view, model, w, h, scroll); }
        fn reduce(event: lab_ui_view::Event<Action>) -> bool { action(model, event) }
        lab_ui_view::frame(view, canvas, gfx::events(), gfx::mouse_pos(), gfx::focused(), scale, describe, reduce);
        lab_ui_render_scene::render(canvas, lab_ui_controls_components::Theme {}.background);
        drawn++; if drawn == frames { break; } sleep_ms(8);
    }
    let saved = gfx::screenshot(screenshot);
    print("frames=", drawn, " gallery=true screenshot=", saved);
    lab_ui_layout_engine::destroy(view.layout); lab_ui_render_scene::destroy(canvas); gfx::close();
}
