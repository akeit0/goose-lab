// End-to-end consumer of nested scroll routing, stable state and uniform-row windows.
namespace app_scroll_demo;
import std;
import vec;
import gfx;
import lab.ui.render.font;
import lab.ui.render.scene;
import lab.ui.layout.engine;
import lab.ui.geometry;
import lab.ui.view;
import lab.ui.layout.scroll;
import lab.ui.controls.components;
let COUNT: i64 = 2000;
let STRIDE: f32 = 44.0;
let OUTER_CONTENT: f32 = 920.0;
enum Action { None, First, Last, Reset, Select }
struct App {
    canvas: lab_ui_render_scene::Canvas, view: lab_ui_view::View<Action> = lab_ui_view::View<Action> {},
    selected: i64 = -1, scale: f32 = 1.0,
}
fn create(font: const u8[:], scale: f32 = 1.0) -> App {
    var app = default<App>(); app.scale = scale; app.canvas = lab_ui_render_scene::create(font, scale);
    assert(app.canvas.fonts.len == 1); assert(lab_ui_render_scene::add_font(app.canvas, font, 28.0) == 1);
    assert(lab_ui_render_scene::add_font(app.canvas, font, 13.0) == 2);
    app.view.layout = lab_ui_layout_engine::create(app.canvas.fonts[0].font); assert(app.view.layout.id != 0); app
}
fn destroy(app: App&) { gfx::text_input(false); lab_ui_layout_engine::destroy(app.view.layout); lab_ui_render_scene::destroy(app.canvas); }
fn inner_bounds(app: const App&) -> lab_ui_geometry::Rect {
    let area = lab_ui_view::bounds(app.view, "workspace");
    lab_ui_geometry::rect(area.x + 20.0, area.y + 90.0, max(0.0, area.w - 40.0), 240.0)
}
fn build(app: App&, width: f32, height: f32) {
    let theme = lab_ui_controls_components::Theme {}; lab_ui_view::begin(app.view, width, height);
    let selection: u8[>..] = if app.selected < 0 { "none" } else { str("Item ", app.selected + 1) };
    let detail: u8[>..] = if app.selected < 0 { "Choose an item above, or jump to the first or last item." }
        else { str("Item ", app.selected + 1, " keeps its identity while the visible rows change.") };
    lab_ui_view::box(app.view, "root", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), padding: lab_ui_layout_engine::padding(24), gap: 12 }) {
        lab_ui_view::label(app.view, "kicker", "GOOSE   /   SCROLL LAB", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(20.0) }, 2, theme.muted);
        lab_ui_view::label(app.view, "heading", "A list inside a workspace.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(40.0) }, 1);
        lab_ui_view::label(app.view, "intro", "Scroll or drag a bar. Arrows and Page Up/Down move the selection.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) }, 2, theme.muted);
        lab_ui_view::box(app.view, "tools", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(40.0), gap: 10 }) {
            lab_ui_view::button(app.view, "first", 1, Action.First, "First item", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
            lab_ui_view::button(app.view, "last", 2, Action.Last, "Last item", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
            lab_ui_view::button(app.view, "reset", 3, Action.Reset, "Reset scroll", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
        };
        lab_ui_view::leaf(app.view, "workspace", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
        lab_ui_view::label(app.view, "status", str("Selected: ", selection, "   ·   2,000 items"), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) }, 2, theme.muted);
    };
    lab_ui_view::solve(app.view);
    let area = lab_ui_view::bounds(app.view, "workspace"); let inner = inner_bounds(app);
    lab_ui_view::at_decoration(app.view, "workspace-card", area);
    lab_ui_view::scroll_viewport(app.view, "workspace", 1, OUTER_CONTENT) {
        lab_ui_view::at_label(app.view, "list-title", lab_ui_geometry::rect(area.x + 20.0, area.y + 18.0, area.w - 40.0, 28.0), "Browse the collection", 0);
        lab_ui_view::at_label(app.view, "list-note", lab_ui_geometry::rect(area.x + 20.0, area.y + 48.0, area.w - 40.0, 24.0), "At the list boundary, remaining wheel movement reaches the workspace.", 2, theme.muted);
        lab_ui_view::at_decoration(app.view, "list-background", inner, lab_ui_view::FILL, theme.background);
        lab_ui_view::at_list(app.view, inner, lab_ui_view::ListConfig<Action> { id: 4, scroll_id: 2, count: COUNT, stride: STRIDE, selected: app.selected, action: Action.Select }) {
            let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(app.view, 2), inner.h, STRIDE, COUNT);
            for i in range.end - range.first {
                let index = range.first + i;
                let row = lab_ui_geometry::rect(inner.x + 8.0, inner.y + index * STRIDE + 4.0, inner.w - 24.0, 36.0);
                lab_ui_view::at_list_item(app.view, str("item-", index), (1000 + index) as u64, index, row,
                    str(if app.selected == index { "Selected · " } else { "" }, "Item ", index + 1));
            }
        };
        lab_ui_view::at_label(app.view, "details-heading", lab_ui_geometry::rect(area.x + 20.0, area.y + 370.0, area.w - 40.0, 32.0), "Selection details", 0);
        lab_ui_view::at_label(app.view, "details", lab_ui_geometry::rect(area.x + 20.0, area.y + 408.0, area.w - 40.0, 28.0),
            detail, 2, theme.muted);
        for i in 3 {
            let row = lab_ui_geometry::rect(area.x + 20.0, area.y + 480.0 + i * 120.0, area.w - 40.0, 100.0);
            lab_ui_view::at_decoration(app.view, str("section-", i), row);
            lab_ui_view::at_label(app.view, str("section-title-", i), lab_ui_geometry::rect(row.x + 16.0, row.y + 14.0, row.w - 32.0, 28.0),
                if i == 0 { "Move through the workspace" } else if i == 1 { "Keep your place" } else { "A little more room" });
            lab_ui_view::at_label(app.view, str("section-note-", i), lab_ui_geometry::rect(row.x + 16.0, row.y + 50.0, row.w - 32.0, 24.0),
                if i == 0 { "The outer workspace has its own scroll position." } else if i == 1 { "The list keeps its position when you scroll outside it." } else { "First item and Last item bring the selection into view." }, 2, theme.muted);
        }
    };
}
fn action(app: App&, event: lab_ui_view::Event<Action>) -> bool {
    if event.action == Action.Select && (event.kind == lab_ui_view::SELECT || event.kind == lab_ui_view::ACTIVATE) {
        app.selected = event.index; return false;
    }
    if event.kind != lab_ui_view::ACTIVATE { return false; }
    match event.action {
        First => { app.selected = 0; }, Last => { app.selected = COUNT - 1; },
        Reset => { lab_ui_view::scroll_state(app.view, 1).offset = 0.0; lab_ui_view::scroll_state(app.view, 2).offset = 0.0; return true; },
        Select => { return false; }, None => { return false; },
    }
    lab_ui_view::scroll_state(app.view, 1).offset = 0.0;
    lab_ui_layout_scroll::reveal(lab_ui_view::scroll_state(app.view, 2), app.selected * STRIDE, (app.selected + 1) * STRIDE, inner_bounds(app).h, COUNT * STRIDE);
    app.view.input.focused = 4;
    true
}
fn frame(app: App&) {
    let size = gfx::screen_size(); let w: f32 = size.x / app.scale; let h: f32 = size.y / app.scale;
    lab_ui_render_scene::begin(app.canvas, w, h);
    fn describe() { build(app, w, h); }
    fn reduce(event: lab_ui_view::Event<Action>) -> bool { action(app, event) }
    lab_ui_view::frame(app.view, app.canvas, gfx::events(), gfx::mouse_pos(), gfx::focused(), app.scale, describe, reduce);
    lab_ui_render_scene::render(app.canvas, lab_ui_controls_components::Theme {}.background);
}
