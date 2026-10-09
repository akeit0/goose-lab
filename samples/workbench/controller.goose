// One renderer, one search worker, one file session. Each page retains its view.
namespace app_workbench;
import std;
import os;
import gfx;
import workbench.editor.single;
import workbench.editor.workspace;
import workbench.git.viewer;
import lab.git.client;
import lab.document.file;
import lab.document.model;
import lab.fs.search;
import lab.ui.view;
import lab.ui.views.editor;
import lab.ui.layout.scroll;
import lab.ui.render.scene;
import lab.ui.render.font;
import lab.ui.controls.components;
struct State {
    worker: i64 = -1,
    changes: bool = false, next_changes: bool = false, switching: bool = false,
}
// Goose has one resizable tail per value: the two page owners stay in separate
// caller variables, passed by reference. State contains only coordination data.
fn init(app: State&, workspace: app_editor_workspace::App&, git: app_git_viewer::App&, mode: i32 = 0) {
    assert(lab_ui_render_scene::add_font(workspace.editor.canvas, lab_ui_render_font::default_font(), 12.0) == 2);
    git = app_git_viewer::attach(workspace.explorer.root, workspace.editor.canvas);
    app.worker = thread_spawn(lab_git_client::worker); app_git_viewer::refresh(git, mode);
}
fn busy(app: const State&, workspace: const app_editor_workspace::App&, git: const app_git_viewer::App&) -> bool { app_editor_workspace::busy(workspace) || git.client.busy || git.pending }
fn poll(app: State&, workspace: app_editor_workspace::App&, git: app_git_viewer::App&) {
    app_editor_workspace::poll(workspace); git.tabs = workspace.tabs; git.editor_dirty = lab_document_model::dirty(workspace.editor.file.document); app_git_viewer::poll(git); app_git_viewer::observe(git);
}
fn switch_page(app: State&, workspace: app_editor_workspace::App&, git: app_git_viewer::App&, changes: bool) { app.next_changes = changes; app.switching = true; }
fn editor_action(app: State&, workspace: app_editor_workspace::App&, git: app_git_viewer::App&, event: lab_ui_view::Event<app_editor_single::Action>) -> bool {
    if app.switching { return false; }
    let editor .= workspace.editor;
    if event.kind == lab_ui_view::CLOSE_REQUESTED || workspace.tab_modal.opened || editor.help.opened || editor.modal.opened || editor.close_modal.opened || editor.closing.pending || editor.closing.saving || editor.closing.ready { return app_editor_workspace::action(workspace, event); }
    if event.kind == lab_ui_view::ACTIVATE && event.action == app_editor_single::Action.WorkbenchEditor { workspace.searching = false; return true; }
    if event.kind == lab_ui_view::ACTIVATE && event.action == app_editor_single::Action.WorkbenchChanges { switch_page(app, workspace, git, true); return true; }
    app_editor_workspace::action(workspace, event)
}
fn git_action(app: State&, workspace: app_editor_workspace::App&, git: app_git_viewer::App&, event: lab_ui_view::Event<app_git_viewer::Action>) -> bool {
    if app.switching { return false; }
    if event.kind == lab_ui_view::CLOSE_REQUESTED {
        app_editor_single::request_close(workspace.editor); switch_page(app, workspace, git, false); return true;
    }
    if !git.help.opened && !git.palette.modal.opened && event.kind == lab_ui_view::ACTIVATE {
        if event.action == app_git_viewer::Action.SelectTab {
            let index = ((event.source - 920000) / 2) as i64;
            if app_editor_workspace::select_tab(workspace, index) { switch_page(app, workspace, git, false); } return true;
        }
        if event.action == app_git_viewer::Action.CloseTab {
            let index = if event.source >= 920001 && event.source < 920033 { ((event.source - 920001) / 2) as i64 } else { workspace.tabs.active };
            if app_editor_workspace::close_tab(workspace, index) { switch_page(app, workspace, git, false); } return true;
        }
        if event.action == app_git_viewer::Action.NextTab || event.action == app_git_viewer::Action.PreviousTab {
            if workspace.tabs.items.len > 0 {
                let index = (workspace.tabs.active + workspace.tabs.items.len + (if event.action == app_git_viewer::Action.NextTab { 1 } else { -1 })) % workspace.tabs.items.len;
                if app_editor_workspace::select_tab(workspace, index) { switch_page(app, workspace, git, false); }
            } return true;
        }
    }
    let changed = app_git_viewer::action(git, event);
    if git.request_file {
        git.request_file = false;
        // Reuse the editor's dirty-navigation decision, including same-file preservation.
        if lab_fs_search::relative(git.selected) && app_editor_workspace::open_path(workspace, str(git.repo, "/", git.selected)) { switch_page(app, workspace, git, false); }
    }
    if git.request_editor || git.request_search {
        workspace.searching = git.request_search;
        if git.request_search { workspace.editor.view.input.focused = 40; }
        git.request_editor = false; git.request_search = false; switch_page(app, workspace, git, false);
    } changed
}
fn frame(app: State&, workspace: app_editor_workspace::App&, git: app_git_viewer::App&) {
    poll(app, workspace, git); let editor .= workspace.editor; let canvas .= editor.canvas;
    let size = gfx::screen_size(); let w = size.x / editor.scale; let h = size.y / editor.scale;
    lab_ui_render_scene::begin(canvas, w, h);
    if app.changes {
        fn describe() { app_git_viewer::build(git, w, h); }
        fn reduce(event: lab_ui_view::Event<app_git_viewer::Action>) -> bool { git_action(app, workspace, git, event) }
        lab_ui_view::frame(git.view, canvas, gfx::events(), gfx::mouse_pos(), gfx::focused(), editor.scale, describe, reduce);
        app_git_viewer::paint_on(git, canvas); lab_ui_view::paint_overlays(git.view, canvas);
    } else {
        fn describe() { app_editor_workspace::build(workspace, w, h, app_git_viewer::repository_name(workspace.explorer.root)); }
        fn reduce(event: lab_ui_view::Event<app_editor_single::Action>) -> bool { editor_action(app, workspace, git, event) }
        lab_ui_view::frame(editor.view, canvas, gfx::events(), gfx::mouse_pos(), gfx::focused(), editor.scale, describe, reduce);
        lab_ui_views_editor::paint(canvas, editor.editor, editor.file.document, lab_ui_view::bounds(editor.view, "code"), app_editor_single::config(editor.compact), lab_ui_view::scroll_state(editor.view, 2).offset, editor.view.input.focused == 7);
        lab_ui_view::paint_overlays(editor.view, canvas);
    }
    lab_ui_render_scene::render(canvas, lab_ui_controls_components::Theme {}.background);
    if app.switching {
        // Release text ownership between views; preedit is never document content.
        gfx::text_input(false); gfx::clear_composition(); lab_ui_views_editor::cancel(editor.editor);
        editor.view.text_owner = 0; editor.view.input.composing = false; editor.view.input.text_pending = false;
        git.view.text_owner = 0; git.view.input.composing = false; git.view.input.text_pending = false;
        editor.view.input.captured = 0; git.view.input.captured = 0;
        app.changes = app.next_changes; app.switching = false;
    }
}
fn destroy(app: State&, workspace: app_editor_workspace::App&, git: app_git_viewer::App&) {
    // Join borrowers before destroying the file context, font sources or renderer.
    app_git_viewer::join(git, app.worker); app.worker = -1; app_git_viewer::destroy(git);
    app_editor_workspace::destroy(workspace);
}
