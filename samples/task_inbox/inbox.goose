// Application assembly: domain commands and persistence precede painting.
namespace app_tasks_inbox;
import std;
import os;
import math;
import vec;
import gfx;
import task_inbox.model;
import lab.fs.storage;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.ui.render.font;
import lab.ui.geometry;
import lab.ui.layout.engine;
import lab.ui.render.scene;
import lab.ui.view;
import lab.ui.controls.components;
struct Model {
    journal: app_tasks_model::Journal = app_tasks_model::Journal {}, filter: i32 = app_tasks_model::ALL,
    editing: u32 = 0, selected: u32 = 0, dirty: bool = false, blocked: bool = false, error: bool = false,
    message: u8[..192] = "Saved locally. Your inbox stays on this device.",
}
enum Action { None, Compose, Search, Add, Undo, Retry, Cancel, Select, Filter { value: i32 }, Toggle { id: u32 }, Edit { id: u32 }, Delete { id: u32 } }
struct App {
    canvas: lab_ui_render_scene::Canvas, view: lab_ui_view::View<Action> = lab_ui_view::View<Action> {},
    model: Model = Model {},
    path: u8[..2048] = [], scale: f32 = 1.0,
}
fn composer(app: App&) -> lab_ui_controls_field::State& { lab_ui_view::field_state(app.view, 1) }
fn search(app: App&) -> lab_ui_controls_field::State& { lab_ui_view::field_state(app.view, 2) }
fn scroll(app: App&) -> lab_ui_layout_scroll::State& { lab_ui_view::scroll_state(app.view, 1) }
fn bounds(app: const App&, name: const u8[:]) -> lab_ui_geometry::Rect {
    let r, found = lab_ui_layout_engine::bounds(app.view.layout, name); assert(found); r
}
fn notice(m: Model&, text: const u8[:], error: bool = false) { m.message.resize(0); m.message.append(text); m.error = error; }
fn reload(app: App&) {
    let store, code = app_tasks_model::load(app.path);
    if code == lab_fs_storage::OK || code == lab_fs_storage::MISSING {
        app.model.journal.store = store; app.model.journal.past.resize(0); app.model.blocked = false; app.model.dirty = false;
        notice(app.model, if code == lab_fs_storage::MISSING { "New inbox. Add your first task above." } else { "Saved locally. Your inbox stays on this device." });
    } else {
        app.model.blocked = true;
        notice(app.model, if code == lab_fs_storage::VERSION { "This inbox uses another version. Its file was left untouched." }
        else { "Could not load this inbox. Its file was left untouched. Retry after fixing the file." }, true);
    }
}
fn persist(app: App&) {
    assert(!app.model.blocked);
    let code = app_tasks_model::save(app.path, app.model.journal.store);
    app.model.dirty = code != lab_fs_storage::OK;
    notice(app.model, if app.model.dirty { "Changes are in memory, but could not be saved. Use Retry save." }
    else { "Saved locally. Your inbox stays on this device." }, app.model.dirty);
}
fn command(app: App&, value: app_tasks_model::Command) -> bool {
    if app.model.blocked { return false; }
    let code = app_tasks_model::apply(app.model.journal, value);
    if code == app_tasks_model::OK { app.model.dirty = true; persist(app); return true; }
    if code == app_tasks_model::UNCHANGED { return true; }
    if code != app_tasks_model::UNCHANGED {
        notice(app.model, if code == app_tasks_model::FULL { "This inbox holds up to 128 tasks. Remove a task before adding another." }
        else if code == app_tasks_model::INVALID { "Use a non-empty title on one line, up to 240 UTF-8 bytes." }
        else { "That task is no longer in the inbox." }, true);
    }
    false
}
fn cancel(app: App&) { app.model.editing = 0; lab_ui_controls_field::set(composer(app), ""); }
fn create(path: const u8[:], font_path: const u8[:], scale: f32 = 1.0, demo: bool = false) -> App {
    var app = default<App>(); app.scale = scale; app.path.append(path);
    app.canvas = lab_ui_render_scene::create(font_path, scale); assert(app.canvas.fonts.len == 1);
    assert(lab_ui_render_scene::add_font(app.canvas, font_path, 30.0) == 1);
    assert(lab_ui_render_scene::add_font(app.canvas, font_path, 13.0) == 2);
    app.view.layout = lab_ui_layout_engine::create(app.canvas.fonts[0].font); assert(app.view.layout.id != 0);
    reload(app);
    if demo && !app.model.blocked && !file_exists(path) {
        for title in ["Plan the next Goose experiment", "Ship a useful utility", "Take a break and get some fresh air"] {
            command(app, app_tasks_model::Command { kind: app_tasks_model::ADD, title: title });
        }
        command(app, app_tasks_model::Command { kind: app_tasks_model::TOGGLE, id: 2 }); app.model.journal.past.resize(0);
    }
    app
}
fn destroy(app: App&) { gfx::text_input(false); lab_ui_layout_engine::destroy(app.view.layout); lab_ui_render_scene::destroy(app.canvas); }
fn build(app: App&, w: f32, h: f32) {
    lab_ui_view::begin(app.view, w, h);
    let theme = lab_ui_controls_components::Theme {}; let done = app_tasks_model::completed(app.model.journal.store); let total = app.model.journal.store.items.len;
    let enabled = !app.model.blocked;
    let labels: const u8[:][3] = ["All tasks", "Active", "Completed"]; let counts: i64[3] = [total, total - done, done];
    let wide = w >= 900.0;
    if wide { lab_ui_view::decoration(app.view, "sidebar", lab_ui_view::FILL, theme.surface); }
    lab_ui_view::box(app.view, "root", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }) {
        if wide {
            lab_ui_view::box(app.view, "sidebar", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(224.0), height: lab_ui_layout_engine::grow(), padding: lab_ui_layout_engine::padding(20), gap: 12 }) {
                lab_ui_view::leaf(app.view, "brand", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(84.0) });
                for i in 3 { lab_ui_view::button(app.view, str("filter-", i), (10 + i) as u64, Action.Filter { value: i as i32 }, str(labels[i], "  ", counts[i]), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(44.0) }, app.model.filter == i); }
                lab_ui_view::leaf(app.view, "sidebar-fill", lab_ui_layout_engine::Config { height: lab_ui_layout_engine::grow() });
                lab_ui_view::leaf(app.view, "local-note", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(60.0) });
            };
        }
        lab_ui_view::box(app.view, "main", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), padding: lab_ui_layout_engine::padding(if wide { 32 } else { 20 }), gap: 14 }) {
            lab_ui_view::label(app.view, "kicker", "YOUR DAY   /   TASK INBOX", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(20.0) }, 2, theme.muted);
            lab_ui_view::label(app.view, "heading", "Make room for progress.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(42.0) }, 1, theme.text);
            lab_ui_view::label(app.view, "intro", str(total - done, " active · ", done, " completed · one thing at a time"), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(22.0) }, 0, theme.muted);
            lab_ui_view::box(app.view, "compose", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(46.0), gap: 10 }) {
                lab_ui_view::field(app.view, "composer", 1, Action.Compose, "What needs doing?", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, enabled, 240, true);
                lab_ui_view::button(app.view, "add", 3, Action.Add, if app.model.editing != 0 { "Save task" } else { "+ Add task" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(106.0), height: lab_ui_layout_engine::grow() }, true, enabled);
                if app.model.editing != 0 { lab_ui_view::button(app.view, "cancel", 6, Action.Cancel, "Cancel", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(76.0), height: lab_ui_layout_engine::grow() }); }
            };
            lab_ui_view::box(app.view, "tools", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(42.0), gap: 10 }) {
                lab_ui_view::field(app.view, "search", 2, Action.Search, "Search your tasks…", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
                lab_ui_view::button(app.view, "undo", 4, Action.Undo, "Undo", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(84.0), height: lab_ui_layout_engine::grow() }, false, enabled && app.model.journal.past.len > 0);
                if app.model.dirty || app.model.blocked { lab_ui_view::button(app.view, "retry", 5, Action.Retry, if app.model.blocked { "Retry load" } else { "Retry save" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(114.0), height: lab_ui_layout_engine::grow() }); }
            };
            if !wide {
                lab_ui_view::box(app.view, "filters", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(38.0), gap: 8 }) {
                    for i in 3 { lab_ui_view::button(app.view, str("filter-", i), (10 + i) as u64, Action.Filter { value: i as i32 }, str(labels[i], "  ", counts[i]), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, app.model.filter == i); }
                };
            }
            lab_ui_view::label(app.view, "status", app.model.message, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(22.0) }, 2, if app.model.error { float4 { 1.0, 0.58, 0.49, 1.0 } } else { theme.muted });
            lab_ui_view::leaf(app.view, "list", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
            lab_ui_view::label(app.view, "footer", str(app_tasks_model::visible(app.model.journal.store, app.model.filter, search(app).text).len, " shown · Arrows to select · Enter to edit · Tab to move focus"), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(22.0) }, 2, theme.muted);
        };
    };
    lab_ui_view::solve(app.view);
    let ids = app_tasks_model::visible(app.model.journal.store, app.model.filter, search(app).text);
    describe_details(app, ids);
}
fn control(id: u32, action: i64) -> u64 { 1000 + id as u64 * 4 + action as u64 }
fn selected_index(app: const App&, ids: const u32[:]) -> i64 {
    for i in ids.len { if ids[i] == app.model.selected { return i; } } -1
}
// Unscrolled content coordinates; the view applies the viewport translation once.
fn row(app: const App&, i: i64) -> lab_ui_geometry::Rect {
    let area = bounds(app, "list"); lab_ui_geometry::rect(area.x, area.y + i * 82.0, area.w - 12.0, 72.0)
}
fn check(r: lab_ui_geometry::Rect) -> lab_ui_geometry::Rect { lab_ui_geometry::rect(r.x + 12.0, r.y + 12.0, 40.0, 48.0) }
fn edit(r: lab_ui_geometry::Rect) -> lab_ui_geometry::Rect { lab_ui_geometry::rect(r.x + r.w - 134.0, r.y + 18.0, 66.0, 36.0) }
fn remove(r: lab_ui_geometry::Rect) -> lab_ui_geometry::Rect { lab_ui_geometry::rect(r.x + r.w - 58.0, r.y + 18.0, 44.0, 36.0) }
fn describe_details(app: App&, ids: const u32[:]) {
    let theme = lab_ui_controls_components::Theme {}; let done = app_tasks_model::completed(app.model.journal.store); let total = app.model.journal.store.items.len;
    let sidebar, wide = lab_ui_layout_engine::bounds(app.view.layout, "sidebar");
    if wide {
        let brand = bounds(app, "brand"); lab_ui_view::at_label(app.view, "brand-title", lab_ui_geometry::rect(brand.x + 4.0, brand.y + 10.0, 210.0, 20.0), "GOOSE", 0, theme.text);
        lab_ui_view::at_label(app.view, "brand-note", lab_ui_geometry::rect(brand.x + 4.0, brand.y + 40.0, 210.0, 20.0), "A LITTLE MORE FOCUS", 2, theme.muted);
        let note = bounds(app, "local-note"); lab_ui_view::at_label(app.view, "local-title", lab_ui_geometry::rect(note.x + 4.0, note.y, 210.0, 20.0), "LOCAL INBOX", 2, theme.muted);
        lab_ui_view::at_label(app.view, "local-note-detail", lab_ui_geometry::rect(note.x + 4.0, note.y + 24.0, 210.0, 20.0), "Small steps, kept safely.", 2, theme.muted);
    }
    let area = bounds(app, "list");
    lab_ui_view::list(app.view, "list", lab_ui_view::ListConfig<Action> { id: 7, scroll_id: 1, count: ids.len, stride: 82.0,
        selected: selected_index(app, ids), action: Action.Select, enabled: !app.model.blocked }) {
        if ids.len == 0 {
            let heading = lab_ui_geometry::rect(area.x, area.y + max(12.0, area.h * 0.30), area.w, 32.0);
            lab_ui_view::at_label(app.view, "empty-heading", heading, if app.model.blocked { "Your inbox could not be loaded." } else if total == 0 { "Nothing here yet." } else { "No matching tasks." }, 0, theme.text, true);
            lab_ui_view::at_label(app.view, "empty-note", lab_ui_geometry::rect(heading.x, heading.y + 32.0, heading.w, 28.0), if app.model.blocked { "Fix the file problem, then choose Retry load." } else if total == 0 { "Add your first task above. A little progress starts here." } else { "Try another search or switch the filter." }, 2, theme.muted, true);
        }
        let visible = lab_ui_layout_scroll::visible(scroll(app), area.h, 82.0, ids.len);
        for i in visible.first..visible.end {
            let r = row(app, i);
            let task = app.model.journal.store.items[app_tasks_model::index(app.model.journal.store, ids[i])];
            lab_ui_view::at_list_item(app.view, str("row-", ids[i]), control(task.id, 3), i, r);
            lab_ui_view::at_button(app.view, str("check-", task.id), control(task.id, 0), Action.Toggle { id: task.id }, check(r), "", !app.model.blocked, true, task.done);
            let title = lab_ui_geometry::rect(r.x + 62.0, r.y + 12.0, max(0.0, r.w - 208.0), 28.0);
            lab_ui_view::at_label(app.view, str("title-", task.id), title, task.title, 0, if task.done { theme.muted } else { theme.text });
            lab_ui_view::at_label(app.view, str("note-", task.id), lab_ui_geometry::rect(title.x, title.y + 27.0, title.w, 20.0), if task.done { "Completed. Nicely done." } else { "Ready when you are." }, 2, theme.muted);
            lab_ui_view::at_button(app.view, str("edit-", task.id), control(task.id, 1), Action.Edit { id: task.id }, edit(r), "Edit", !app.model.blocked);
            lab_ui_view::at_button(app.view, str("delete-", task.id), control(task.id, 2), Action.Delete { id: task.id }, remove(r), "×", !app.model.blocked);
        }
    };
}
// The controller receives application actions, without widget bounds or painting.
fn submit(app: App&, title: const u8[:]) {
    let kind = if app.model.editing == 0 { app_tasks_model::ADD } else { app_tasks_model::RENAME };
    if command(app, app_tasks_model::Command { kind: kind, id: app.model.editing, title: title }) { app.model.editing = 0; }
    else if composer(app).text.len == 0 { lab_ui_controls_field::set(composer(app), title); }
}
fn start_edit(app: App&, id: u32) {
    let i = app_tasks_model::index(app.model.journal.store, id);
    if i >= 0 && !app.model.blocked { app.model.editing = id; lab_ui_controls_field::set(composer(app), app.model.journal.store.items[i].title); app.view.input.focused = 1; }
}
fn action(app: App&, event: lab_ui_view::Event<Action>) -> bool {
    if event.action == Action.Select {
        let ids = app_tasks_model::visible(app.model.journal.store, app.model.filter, search(app).text);
        if event.index >= 0 && event.index < ids.len {
            app.model.selected = ids[event.index];
            if event.kind == lab_ui_view::ACTIVATE { start_edit(app, app.model.selected); return true; }
        } return false;
    }
    if event.kind == lab_ui_view::REJECTED { notice(app.model, "Text must fit on one line, up to 240 UTF-8 bytes.", true); return true; }
    if event.kind == lab_ui_view::CHANGE {
        if event.action == Action.Search { scroll(app).offset = 0.0; return true; }
        return false;
    }
    if event.kind == lab_ui_view::SUBMIT {
        if event.action == Action.Compose { submit(app, event.text); return true; }
        return false;
    }
    match event.action {
        Add => {
            let title = copy(composer(app).text);
            let kind = if app.model.editing == 0 { app_tasks_model::ADD } else { app_tasks_model::RENAME };
            if command(app, app_tasks_model::Command { kind: kind, id: app.model.editing, title: title }) { cancel(app); }
        },
        Undo => { if !app.model.blocked && app_tasks_model::undo(app.model.journal) { app.model.dirty = true; persist(app); } },
        Retry => { if app.model.blocked { reload(app); } else { persist(app); } },
        Cancel => { cancel(app); },
        Filter f => { app.model.filter = f.value; scroll(app).offset = 0.0; },
        Toggle t => { command(app, app_tasks_model::Command { kind: app_tasks_model::TOGGLE, id: t.id }); },
        Delete t => { command(app, app_tasks_model::Command { kind: app_tasks_model::DELETE, id: t.id }); },
        Edit t => { start_edit(app, t.id); },
        None => {}, Compose => {}, Search => {}, Select => {},
    }
    if app.model.editing != 0 && app_tasks_model::index(app.model.journal.store, app.model.editing) < 0 { cancel(app); }
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
