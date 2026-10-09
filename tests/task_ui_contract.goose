import std;
import os;
import gfx;
import task_inbox.model;
import lab.fs.storage;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.ui.geometry;
import lab.ui.render.font;
import task_inbox.inbox;
fn tick(app: app_tasks_inbox::App&) { assert(gfx::frame()); app_tasks_inbox::frame(app); }
fn click(app: app_tasks_inbox::App&, rect: lab_ui_geometry::Rect) {
    let x = (rect.x + rect.w / 2.0) * app.scale; let y = (rect.y + rect.h / 2.0) * app.scale;
    gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, true); gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, false); tick(app);
}
fn key(app: app_tasks_inbox::App&, name: const u8[:]) {
    assert(gfx::inject_key(name, true)); assert(gfx::inject_key(name, false)); tick(app);
}
fn text(app: app_tasks_inbox::App&, value: const u8[:]) { assert(gfx::inject_text(value)); tick(app); }
fn main() {
    let argv = args(); assert(argv.len == 3 || argv.len == 4); let path = argv[1]; let screenshot = argv[2];
    var scale: f32 = 1.0;
    if argv.len == 4 { let value, valid = parse_flt(argv[3]); assert(valid); scale = value as f32; }
    assert(gfx::open_headless((1180.0 * scale) as i64, (820.0 * scale) as i64)); var app = app_tasks_inbox::create(path, lab_ui_render_font::default_font(), scale); tick(app);
    assert(app.model.journal.store.items.len == 0);
    click(app, app_tasks_inbox::bounds(app, "composer")); text(app, "Plan café visit"); key(app, "Return");
    assert(app.model.journal.store.items.len == 1 && app_tasks_inbox::composer(app).text.len == 0 && !app.model.dirty);
    let first = app.model.journal.store.items[0].id;
    click(app, app_tasks_inbox::bounds(app, "composer")); text(app, "Ship useful utilities"); click(app, app_tasks_inbox::bounds(app, "add"));
    assert(app.model.journal.store.items.len == 2);
    click(app, app_tasks_inbox::check(app_tasks_inbox::row(app, 0))); assert(app.model.journal.store.items[0].done);
    click(app, app_tasks_inbox::bounds(app, "filter-1")); assert(app_tasks_model::visible(app.model.journal.store, app.model.filter, app_tasks_inbox::search(app).text).len == 1);
    click(app, app_tasks_inbox::bounds(app, "search")); text(app, "UTIL");
    assert(app_tasks_model::visible(app.model.journal.store, app.model.filter, app_tasks_inbox::search(app).text).len == 1);
    key(app, "Home"); for i in 4 { key(app, "Delete"); }
    assert(app_tasks_inbox::search(app).text.len == 0);
    click(app, app_tasks_inbox::bounds(app, "filter-0"));
    // Edit and type within one platform batch: the action must precede later text.
    let edit = app_tasks_inbox::edit(app_tasks_inbox::row(app, 0));
    let edit_x = (edit.x + edit.w / 2.0) * app.scale; let edit_y = (edit.y + edit.h / 2.0) * app.scale;
    gfx::inject_mouse(edit_x, edit_y, gfx::MOUSE_LEFT, true); gfx::inject_mouse(edit_x, edit_y, gfx::MOUSE_LEFT, false);
    assert(gfx::inject_key("End", true)); assert(gfx::inject_key("End", false)); assert(gfx::inject_text(" tomorrow")); tick(app);
    assert(app.model.editing == first && app.view.input.focused == 1 && app_tasks_inbox::composer(app).text == "Plan café visit tomorrow");
    click(app, app_tasks_inbox::bounds(app, "add"));
    assert(app.model.editing == 0 && app.model.journal.store.items[0].title == "Plan café visit tomorrow");
    click(app, app_tasks_inbox::edit(app_tasks_inbox::row(app, 0))); let history = app.model.journal.past.len;
    click(app, app_tasks_inbox::bounds(app, "add")); assert(app.model.editing == 0 && app.model.journal.past.len == history);
    click(app, app_tasks_inbox::remove(app_tasks_inbox::row(app, 0))); assert(app.model.journal.store.items.len == 1);
    click(app, app_tasks_inbox::bounds(app, "undo")); assert(app.model.journal.store.items.len == 2 && app.model.journal.store.items[0].id == first);
    // A submit and more typing in the same frame must not merge or lose text.
    click(app, app_tasks_inbox::bounds(app, "composer"));
    assert(gfx::inject_text("Write down the next idea")); assert(gfx::inject_key("Return", true)); assert(gfx::inject_key("Return", false));
    assert(gfx::inject_text("Keep this draft")); tick(app);
    assert(app.model.journal.store.items.len == 3 && app.model.journal.store.items[2].title == "Write down the next idea" && app_tasks_inbox::composer(app).text == "Keep this draft");
    // An unwritable destination keeps the edited model and offers a real retry.
    app.path.resize(0); app.path.append(str(path, "/not-a-directory/inbox.gxt"));
    click(app, app_tasks_inbox::check(app_tasks_inbox::row(app, 2)));
    assert(app.model.dirty && app.model.error && app.model.journal.store.items[2].done);
    let old, old_code = app_tasks_model::load(path); assert(old_code == lab_fs_storage::OK && !old.items[2].done);
    app.path.resize(0); app.path.append(path); click(app, app_tasks_inbox::bounds(app, "retry"));
    assert(!app.model.dirty && !app.model.error);
    click(app, app_tasks_inbox::bounds(app, "undo")); assert(!app.model.journal.store.items[2].done);
    // Real wheel input and a later click share the library's updated geometry.
    let original = copy(app.model.journal);
    for i in 15 { assert(app_tasks_model::apply(app.model.journal, app_tasks_model::Command { kind: app_tasks_model::ADD, title: str("Scroll task ", i) }) == app_tasks_model::OK); }
    tick(app); let area = app_tasks_inbox::bounds(app, "list");
    gfx::inject_mouse((area.x + 20.0) * scale, (area.y + 20.0) * scale, 0, false);
    assert(gfx::inject_wheel(0.0, -1.0));
    let target = app_tasks_inbox::check(app_tasks_inbox::row(app, 1));
    let x = (target.x + target.w / 2.0) * scale; let y = (target.y + target.h / 2.0 - 44.0) * scale;
    gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, true); gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, false); tick(app);
    assert(app_tasks_inbox::scroll(app).offset == 44.0 && app.model.journal.store.items[1].done);
    gfx::inject_mouse(10.0, 10.0, 0, false); assert(gfx::inject_wheel(0.0, -1.0)); tick(app);
    assert(app_tasks_inbox::scroll(app).offset == 44.0);
    // A composite list keeps its focus while navigation crosses unrendered rows.
    assert(app.view.input.focused == 7 && app.model.selected == app.model.journal.store.items[1].id);
    key(app, "End"); assert(app.model.selected == app.model.journal.store.items[17].id && app.view.input.focused == 7);
    key(app, "Return"); assert(app.model.editing == app.model.selected && app.view.input.focused == 1);
    assert(app_tasks_inbox::composer(app).text == "Scroll task 14");
    click(app, app_tasks_inbox::bounds(app, "cancel"));
    // The shared scrollbar works here too and preserves a field's focus.
    app_tasks_inbox::scroll(app).offset = 0.0; tick(app);
    click(app, app_tasks_inbox::bounds(app, "composer")); assert(app.view.input.focused == 1);
    let thumb = lab_ui_layout_scroll::thumb(app_tasks_inbox::scroll(app), area, 18 * 82.0);
    gfx::inject_mouse((thumb.x + 3.0) * scale, (thumb.y + 6.0) * scale, gfx::MOUSE_LEFT, true); tick(app);
    assert(app.view.drag.id == 1 && app.view.input.focused == 1);
    gfx::inject_mouse((area.x - 20.0) * scale, (area.y + area.h + 100.0) * scale, 0, false); tick(app);
    gfx::inject_mouse((area.x - 20.0) * scale, (area.y + area.h + 100.0) * scale, gfx::MOUSE_LEFT, false); tick(app);
    assert(app.view.drag.id == 0 && app.view.input.focused == 1 && app_tasks_inbox::scroll(app).offset == 18 * 82.0 - area.h);
    // Shrinking the derived view clamps scrolling without an application prepass.
    app.model.journal = original; app_tasks_inbox::persist(app);
    app_tasks_inbox::scroll(app).offset = 900.0; tick(app); assert(app_tasks_inbox::scroll(app).offset == 0.0);
    let loaded, code = app_tasks_model::load(path); assert(code == lab_fs_storage::OK && loaded == app.model.journal.store);
    assert(gfx::screenshot(screenshot) && gfx::misuse_count() == 0);
    app_tasks_inbox::destroy(app); gfx::close();
    print("Task UI add/edit/complete/search/filter/delete/undo/persist contract passed");
}
