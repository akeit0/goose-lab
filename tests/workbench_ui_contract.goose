import std;
import gfx;
import workbench.controller;
import workbench.editor.workspace;
import workbench.git.viewer;
import lab.document.model;
import lab.ui.view;
import lab.ui.render.scene;
import lab.ui.render.font;
import lab.ui.layout.engine;
import lab.ui.render.text_layout;
import lab.text.strings;
fn tick(state: app_workbench::State&, workspace: app_editor_workspace::App&, git: app_git_viewer::App&) { assert(gfx::frame()); app_workbench::frame(state, workspace, git); }
fn wait(state: app_workbench::State&, workspace: app_editor_workspace::App&, git: app_git_viewer::App&) {
    let until = clock_ns() + 10000000000; tick(state, workspace, git);
    while app_workbench::busy(state, workspace, git) { assert(clock_ns() < until); sleep_ms(2); tick(state, workspace, git); }
    tick(state, workspace, git);
}
fn click<A>(view: const lab_ui_view::View<A>&, name: const u8[:], scale: f32) {
    for node in view.nodes {
        if node.name != name { continue; } assert(node.enabled);
        let r = node.rect; let x = (r.x + r.w / 2.0) * scale; let y = (r.y + r.h / 2.0) * scale;
        gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, true); gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, false); return;
    } print("missing node: ", name); assert(false);
}
fn key(name: const u8[:], mods: i64 = 0) {
    if (mods & gfx::MOD_CTRL) != 0 { assert(gfx::inject_key("Left Ctrl", true)); }
    if (mods & gfx::MOD_SHIFT) != 0 { assert(gfx::inject_key("Left Shift", true)); }
    assert(gfx::inject_key(name, true) && gfx::inject_key(name, false));
    if (mods & gfx::MOD_SHIFT) != 0 { assert(gfx::inject_key("Left Shift", false)); }
    if (mods & gfx::MOD_CTRL) != 0 { assert(gfx::inject_key("Left Ctrl", false)); }
}
fn main() {
    let argv = args(); assert(argv.len == 4 || argv.len == 5); let n, ok = parse_flt(argv[3]); assert(ok); let scale = n as f32;
    gfx::text_transactions(true); assert(gfx::open_headless((1180.0 * scale) as i64, (820.0 * scale) as i64));
    let initial: u8[>..] = if argv.len == 5 { argv[4] } else { str(argv[1], "/a.txt") };
    var workspace = app_editor_workspace::create(argv[1], initial, scale);
    var git = app_git_viewer::App { canvas: default<lab_ui_render_scene::Canvas>() }; var state = app_workbench::State {};
    app_workbench::init(state, workspace, git); wait(state, workspace, git);
    assert(git.attached && git.search.worker == -1 && git.canvas.stamp == 0 && workspace.editor.canvas.fonts.len == 3);
    key("End", gfx::MOD_CTRL); tick(state, workspace, git); assert(gfx::inject_text("local 日本語")); tick(state, workspace, git);
    let edited = lab_document_model::contents(workspace.editor.file.document); let selection = workspace.editor.file.document.selection;
    assert(lab_document_model::dirty(workspace.editor.file.document));
    click(workspace.editor.view, "workbench-changes", scale); tick(state, workspace, git); wait(state, workspace, git); assert(state.changes);
    assert(lab_document_model::contents(workspace.editor.file.document) == edited && workspace.editor.file.document.selection == selection);
    click(git.view, "search", scale); tick(state, workspace, git); key("A", gfx::MOD_CTRL); tick(state, workspace, git); assert(gfx::inject_text("b.txt")); tick(state, workspace, git); wait(state, workspace, git); assert(git.selected == "b.txt");
    click(git.view, "workbench-open-file", scale); tick(state, workspace, git); tick(state, workspace, git);
    assert(!state.changes && workspace.editor.modal.opened); key("Escape"); tick(state, workspace, git);
    assert(!workspace.editor.modal.opened && lab_document_model::contents(workspace.editor.file.document) == edited);
    click(workspace.editor.view, "workbench-changes", scale); tick(state, workspace, git); tick(state, workspace, git);
    click(git.view, "workbench-open-file", scale); tick(state, workspace, git); tick(state, workspace, git);
    click(workspace.editor.view, "save-before-open", scale); tick(state, workspace, git); wait(state, workspace, git);
    var disk: u8[>..] = []; assert(read_file(str(git.repo, "/a.txt"), disk) && disk == edited);
    assert(ends_with(workspace.editor.file.path, "/b.txt") && !lab_document_model::dirty(workspace.editor.file.document));
    key("End", gfx::MOD_CTRL); tick(state, workspace, git); assert(gfx::inject_text("🪿")); tick(state, workspace, git); key("S", gfx::MOD_CTRL); tick(state, workspace, git); wait(state, workspace, git);
    // A save is observed while the Git page is inactive.
    let until = clock_ns() + 10000000000;
    while !lab_text_strings::contains_folded(git.diff.patch.source, "🪿") { assert(clock_ns() < until); sleep_ms(8); tick(state, workspace, git); }
    assert(!lab_document_model::dirty(workspace.editor.file.document));
    click(workspace.editor.view, "search-tab", scale); tick(state, workspace, git); click(workspace.editor.view, "project-query", scale); tick(state, workspace, git);
    assert(gfx::inject_text("needle")); tick(state, workspace, git); click(workspace.editor.view, "run-search", scale); tick(state, workspace, git);
    click(workspace.editor.view, "workbench-changes", scale); tick(state, workspace, git); wait(state, workspace, git); assert(workspace.hits.len == 2);
    // Git's find-in-files shortcut returns to the shared editable search view.
    key("F", gfx::MOD_CTRL | gfx::MOD_SHIFT); tick(state, workspace, git); tick(state, workspace, git); assert(!state.changes && workspace.searching);
    click(workspace.editor.view, "workbench-changes", scale); tick(state, workspace, git); tick(state, workspace, git);
    assert(gfx::screenshot(argv[2]));
    // Stable Git view uses the shared renderer's on-demand presentation.
    tick(state, workspace, git); let renders = workspace.editor.canvas.renders;
    for i in 12 { tick(state, workspace, git); } assert(workspace.editor.canvas.renders == renders);
    click(git.view, "workbench-editor", scale); tick(state, workspace, git); tick(state, workspace, git);
    workspace.editor.view.input.focused = 7; assert(gfx::inject_text("unsaved")); tick(state, workspace, git);
    click(workspace.editor.view, "workbench-changes", scale); tick(state, workspace, git); tick(state, workspace, git);
    assert(gfx::inject_close()); tick(state, workspace, git); tick(state, workspace, git); assert(!state.changes && workspace.editor.close_modal.opened);
    click(workspace.editor.view, "close-cancel", scale); tick(state, workspace, git); assert(!workspace.editor.closing.ready);
    app_workbench::destroy(state, workspace, git);
    assert(lab_ui_render_font::source_bytes() == 0 && lab_ui_render_font::atlas_bytes() == 0 && lab_ui_render_scene::live_bytes() == 0 && lab_ui_layout_engine::live_bytes() == 0 && lab_ui_render_text_layout::live_bytes() == 0);
    gfx::close(); print("Workbench: dirty navigation, save/watch/diff, search across pages, close from Git, idle rendering and cleanup passed");
}
