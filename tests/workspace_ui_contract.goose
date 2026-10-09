import std;
import os;
import gfx;
import workbench.editor.workspace;
import workbench.editor.single;
import lab.document.model;
import lab.document.file;
import lab.document.workspace;
import lab.collections.tree;
import lab.ui.view;
import lab.ui.controls.field;
import lab.ui.render.text_layout;
import lab.fs.path;
import lab.document.close;
fn main() {
    let argv = args(); assert(argv.len == 4); let scale, ok = parse_flt(argv[3]); assert(ok);
    contract(argv[1], argv[2], scale as f32);
}
fn tick(app: app_editor_workspace::App&) { assert(gfx::frame()); app_editor_workspace::frame(app); }
fn wait(app: app_editor_workspace::App&) {
    let until = clock_ns() + 5000000000;
    tick(app);
    while app_editor_workspace::busy(app) {
        assert(clock_ns() < until); sleep_ms(2); tick(app);
    }
    tick(app);
}
fn key(app: app_editor_workspace::App&, name: const u8[:], mods: i64 = 0) {
    if (mods & gfx::MOD_CTRL) != 0 { gfx::inject_key("Left Ctrl", true); }
    if (mods & gfx::MOD_SHIFT) != 0 { gfx::inject_key("Left Shift", true); }
    assert(gfx::inject_key(name, true) && gfx::inject_key(name, false));
    if (mods & gfx::MOD_SHIFT) != 0 { gfx::inject_key("Left Shift", false); }
    if (mods & gfx::MOD_CTRL) != 0 { gfx::inject_key("Left Ctrl", false); } tick(app);
}
fn click(app: app_editor_workspace::App&, name: const u8[:]) {
    for node in app.editor.view.nodes {
        if node.name != name { continue; } let r = node.rect; let scale = app.editor.scale;
        gfx::inject_mouse((r.x + r.w / 2.0) * scale, (r.y + r.h / 2.0) * scale, gfx::MOUSE_LEFT, true);
        gfx::inject_mouse((r.x + r.w / 2.0) * scale, (r.y + r.h / 2.0) * scale, gfx::MOUSE_LEFT, false); tick(app); return;
    } print("missing UI node: ", name); assert(false);
}
fn tree_click(app: app_editor_workspace::App&, path: const u8[:]) {
    let id = lab_collections_tree::index(app.explorer.tree, path); assert(id >= 0);
    let rows = lab_collections_tree::project(app.explorer.tree, app.explorer.state); let row = lab_collections_tree::row_index(rows, id); assert(row >= 0);
    click(app, str("tree-47-row-", row));
}
fn disk_idle(app: app_editor_workspace::App&) {
    let until = clock_ns() + 5000000000;
    while app.editor.workspace.reading.id != 0 { assert(clock_ns() < until); sleep_ms(2); tick(app); }
}
fn disk_wait(app: app_editor_workspace::App&, state: i32) {
    let until = clock_ns() + 5000000000;
    while app.editor.workspace.disk != state { assert(clock_ns() < until); sleep_ms(5); tick(app); }
}
fn contract(root: const u8[:], screenshot: const u8[:], scale: f32) {
    assert(make_dir(root)); let nested = str(root, "/nested"); let large = str(root, "/large"); assert(make_dir(nested) && make_dir(large));
    let a = str(root, "/a.txt"); let b = str(nested, "/日本語.txt"); let original = "first 日本語\r\nneedle here\r\n";
    assert(write_file_atomic(a, original) && write_file_atomic(b, "other needle\n"));
    let normalized = lab_fs_path::absolute(str(root, "/nested/../a.txt"), 512); let simple = lab_fs_path::absolute(a, 512); assert(normalized.code == 0 && normalized.bytes == simple.bytes);
    assert(lab_fs_path::absolute("bad\0path").code == lab_fs_path::INVALID && lab_fs_path::absolute(a, 1).code == lab_fs_path::LIMIT);
    assert(gfx::open_headless((1180.0 * scale) as i64, (820.0 * scale) as i64)); var app = app_editor_workspace::create(root, a, scale); tick(app); wait(app);
    assert(app.editor.file.code == 0 && lab_document_model::contents(app.editor.file.document) == original);
    assert(app.explorer.state.current == "a.txt");
    assert(lab_collections_tree::index(app.explorer.tree, "nested") >= 0 && lab_collections_tree::index(app.explorer.tree, "nested/日本語.txt") < 0);
    tree_click(app, "nested"); wait(app); assert(lab_collections_tree::index(app.explorer.tree, "nested/日本語.txt") >= 0);
    tree_click(app, "a.txt"); tick(app);
    // Same normalized file preserves local contents/history; focus returns to the editor.
    key(app, "End", gfx::MOD_CTRL); assert(gfx::inject_text("local")); tick(app); let generation = app.editor.file.generation;
    tree_click(app, "a.txt"); assert(!app.editor.modal.opened && app.editor.file.generation == generation && lab_document_model::dirty(app.editor.file.document)); tick(app);
    tree_click(app, "nested/日本語.txt"); assert(app.editor.modal.opened); key(app, "Escape"); assert(!app.editor.modal.opened && app.editor.file.path == simple.bytes);
    tree_click(app, "nested/日本語.txt"); click(app, "save-before-open"); wait(app);
    assert(app.editor.file.code == 0 && lab_document_model::contents(app.editor.file.document) == "other needle\n" && !lab_document_model::dirty(app.editor.file.document));
    var saved: u8[>..] = []; assert(read_file(a, saved) && saved == str(original, "local"));
    // Search activates exact byte selection in the editable document.
    click(app, "search-tab"); lab_ui_controls_field::set(lab_ui_view::field_state(app.editor.view, 40), "needle"); click(app, "run-search"); wait(app); assert(app.hits.len == 2);
    var selected: i64 = -1; for i in app.hits.len { if app.hits[i].path == "a.txt" { selected = i; } } assert(selected >= 0);
    click(app, str("hit-", selected)); wait(app); assert(app.editor.view.input.focused == 7 && lab_document_model::read(app.editor.file.document, lab_document_model::first(app.editor.file.document), lab_document_model::last(app.editor.file.document)) == "needle");
    assert(gfx::screenshot(str(screenshot, "-search.png")));
    // Search navigation inside a dirty active document does not discard edits/Undo.
    key(app, "End", gfx::MOD_CTRL); assert(gfx::inject_text("!")); tick(app); click(app, str("hit-", selected)); tick(app);
    assert(!app.editor.modal.opened && lab_document_model::dirty(app.editor.file.document)); key(app, "Z", gfx::MOD_CTRL); assert(!lab_document_model::dirty(app.editor.file.document));
    // Stale offsets never select unrelated bytes, but the file still opens.
    disk_idle(app); assert(write_file_atomic(b, "shifted other needle\n"));
    var other: i64 = -1; for i in app.hits.len { if app.hits[i].path != "a.txt" { other = i; } } assert(other >= 0);
    click(app, str("hit-", other)); wait(app); assert(app.editor.workspace.stale && lab_document_model::first(app.editor.file.document) == lab_document_model::last(app.editor.file.document));
    // Native watcher detects atomic replacement without a Refresh or Save action.
    disk_idle(app); assert(write_file_atomic(b, "external 日本語\n")); disk_wait(app, lab_document_workspace::CHANGED);
    assert(lab_document_model::contents(app.editor.file.document) == "shifted other needle\n"); click(app, "reload"); wait(app); assert(lab_document_model::contents(app.editor.file.document) == "external 日本語\n");
    // A dirty reload asks first. Save-and-switch conflicts keep the original buffer.
    key(app, "End", gfx::MOD_CTRL); assert(gfx::inject_text("local")); tick(app); disk_idle(app); assert(write_file_atomic(b, "changed again\n")); disk_wait(app, lab_document_workspace::CHANGED);
    click(app, "reload"); assert(app.editor.modal.opened); assert(gfx::screenshot(str(screenshot, "-reload.png"))); key(app, "Escape"); assert(lab_document_model::dirty(app.editor.file.document));
    click(app, "explorer-tab"); tree_click(app, "a.txt"); click(app, "save-before-open"); wait(app);
    assert(app.editor.file.code == lab_document_file::CONFLICT && lab_document_model::contents(app.editor.file.document) == "external 日本語\nlocal");
    tree_click(app, "a.txt"); click(app, "discard-open"); wait(app); assert(lab_document_model::contents(app.editor.file.document) == str(original, "local"));
    // Deleted targets and invalid text cannot replace a live document.
    disk_idle(app); assert(delete_file(b)); tree_click(app, "nested/日本語.txt"); wait(app); assert(app.editor.file.code != 0 && app.editor.file.path == simple.bytes);
    assert(write_file_atomic(b, "binary\0bytes")); tree_click(app, "nested/日本語.txt"); wait(app); assert(app.editor.file.code == lab_document_file::DOCUMENT && app.editor.file.path == simple.bytes);
    // A mutation after a read began also rejects adoption, even after Undo restores revision.
    assert(lab_document_file::open(app.editor.file, a, false, true)); let code, changed = lab_document_model::insert(app.editor.file.document, "x"); assert(code == 0 && changed); assert(lab_document_model::undo(app.editor.file.document)); wait(app);
    assert(app.editor.file.code == lab_document_file::DIRTY && app.editor.file.path == simple.bytes);
    // Directory limits report failure and preserve the last successful forest.
    disk_idle(app); for i in 513 { assert(write_file_atomic(str(large, "/", i, ".txt"), "")); }
    let nodes = app.explorer.tree.nodes.len; tree_click(app, "large"); wait(app); assert(app.explorer.code != 0 && app.explorer.tree.nodes.len == nodes);
    tree_click(app, "large"); // collapse the failed directory
    // Missing active file is reported without losing buffer or saved baseline.
    disk_idle(app); assert(delete_file(a)); disk_wait(app, lab_document_workspace::DELETED); assert(lab_document_model::contents(app.editor.file.document) == str(original, "local"));
    assert(write_file_atomic(a, str(original, "local"))); disk_wait(app, lab_document_workspace::SAME);
    click(app, "refresh-tree"); wait(app); assert(lab_collections_tree::index(app.explorer.tree, "nested/日本語.txt") >= 0);
    assert(lab_document_file::open(app.editor.file, a, false, true)); wait(app);
    app.editor.view.input.focused=7; assert(gfx::inject_text("unsaved") && gfx::inject_close()); tick(app);
    assert(app.editor.close_modal.opened && app.editor.closing.prompt); key(app,"Escape");
    assert(!app.editor.closing.ready && lab_document_model::dirty(app.editor.file.document));
    assert(gfx::inject_close()); tick(app); click(app,"close-discard"); assert(app.editor.closing.ready);
    assert(gfx::screenshot(screenshot)); app_editor_workspace::destroy(app); assert(lab_ui_render_text_layout::live_bytes() == 0 && gfx::misuse_count() == 0); gfx::close();
    print("Workspace: lazy tree, normalized paths, save/discard/keep navigation, live search selection, stale hits, atomic disk changes, conflicts, missing/binary targets, load mutation guard and listing limits passed");
}
