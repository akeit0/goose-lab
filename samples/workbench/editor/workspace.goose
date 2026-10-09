// Explorer and project search surround the same reusable single-document editor.
namespace app_editor_workspace;
import std;
import os;
import gfx;
import workbench.editor.single;
import lab.ui.views.editor;
import lab.document.model;
import lab.document.file;
import lab.document.workspace;
import lab.fs.explorer;
import lab.collections.tree;
import lab.ui.views.tree;
import lab.fs.search_client;
import lab.fs.search;
import lab.ui.view;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.ui.geometry;
import lab.ui.render.scene;
import lab.ui.controls.components;
import lab.ui.overlays.modal;
import lab.text.strings;
struct App {
    explorer: lab_fs_explorer::State = lab_fs_explorer::State {}, search: lab_fs_search_client::State = lab_fs_search_client::State {},
    searching: bool = false, query: u8[..512] = [], hits: lab_fs_search::Hit[..256] = [], selected: i64 = -1,
    progress: lab_fs_search::Progress = lab_fs_search::Progress {}, result: i32 = -1,
    active_generation: u64 = 0, desired: u8[..512] = [], reveal_tree: bool = false,
    editor: app_editor_single::App,
}
fn create(root: const u8[:], path: const u8[:] = [], scale: f32 = 1.0) -> App {
    var app = App { editor: app_editor_single::create(path, scale) };
    app.explorer = lab_fs_explorer::create(app.editor.file.context, root); app.search = lab_fs_search_client::create();
    app.editor.editing_path = false; lab_ui_controls_field::set(lab_ui_view::field_state(app.editor.view, 40), ""); app
}
// Finite foreground work only; periodic observation is deliberately excluded.
fn busy(app: const App&) -> bool {
    lab_document_file::busy(app.editor.file) || lab_fs_explorer::busy(app.explorer) || app.search.busy ||
        app.editor.workspace.saving || app.editor.workspace.opening || app.desired.len > 0
}
fn poll(app: App&) {
    app_editor_single::poll(app.editor); lab_fs_explorer::poll(app.explorer, app.editor.file.context);
    if app.active_generation != app.editor.file.generation {
        app.active_generation = app.editor.file.generation; let prefix = str(app.explorer.root, if ends_with(app.explorer.root, "/") { "" } else { "/" });
        app.desired = if starts_with(app.editor.file.path, prefix) { app.editor.file.path[prefix.len..] } else { "" };
    }
    if app.desired.len > 0 {
        // Resolve only the ancestors needed to locate the active file, even from --file/search.
        var waiting = app.explorer.listing.id != 0;
        for i in app.explorer.tree.nodes.len {
            let node = app.explorer.tree.nodes[i];
            if node.branch && starts_with(app.desired, str(node.key, "/")) {
                lab_collections_tree::set_expanded(app.explorer.state, node, true);
                waiting = waiting || (!app.explorer.loaded[i] && app.explorer.blocked != i);
            }
        }
        let id = lab_collections_tree::index(app.explorer.tree, app.desired);
        if id >= 0 { app.explorer.state.current = app.desired; app.desired = []; app.reveal_tree = true; }
        else if !waiting { app.desired = []; } // Deleted, omitted or over-limit path: no endless traversal.
    }
    loop {
        let update, available = qpoll<lab_fs_search_client::Update>(); if !available { break; }
        if !lab_fs_search_client::accept(app.search, update) || update.root != app.explorer.root || update.query != app.query { continue; }
        for hit in update.batch.hits { if app.hits.len < 256 { app.hits.push(hit); } }
        app.progress = update.batch.progress; if update.batch.done { app.result = update.batch.result; }
    }
}
fn list_area(app: const App&) -> lab_ui_geometry::Rect {
    let r = lab_ui_view::bounds(app.editor.view, "project"); let top: f32 = if app.searching { 116.0 } else { 62.0 };
    lab_ui_geometry::rect(r.x, r.y + top, r.w, max(0.0, r.h - top))
}
fn build(app: App&, width: f32, height: f32, project_name: const u8[:] = []) {
    let editor .= app.editor; let theme = lab_ui_controls_components::Theme {}; app_editor_single::build(editor, width, height, true, project_name);
    let panel = lab_ui_view::bounds(editor.view, "project"); let r = list_area(app);
    lab_ui_view::shortcut(editor.view, "F", gfx::MOD_CTRL | gfx::MOD_SHIFT, app_editor_single::Action.ProjectSearch);
    lab_ui_view::record(editor.view, lab_ui_view::Node<app_editor_single::Action> { name: "explorer-tab", text: "Files", id: 38, kind: lab_ui_view::BUTTON, action: app_editor_single::Action.Files, rect: lab_ui_geometry::rect(panel.x, panel.y, 68.0, 28.0), placed: true, primary: !app.searching });
    lab_ui_view::record(editor.view, lab_ui_view::Node<app_editor_single::Action> { name: "search-tab", text: "Search", id: 39, kind: lab_ui_view::BUTTON, action: app_editor_single::Action.ProjectSearch, rect: lab_ui_geometry::rect(panel.x + 76.0, panel.y, 76.0, 28.0), placed: true, primary: app.searching });
    lab_ui_view::at_button(editor.view, "refresh-tree", 44, app_editor_single::Action.Refresh, lab_ui_geometry::rect(panel.x + panel.w - 76.0, panel.y, 76.0, 28.0), "Refresh", app.explorer.listing.id == 0);
    if app.searching {
        lab_ui_view::at_field(editor.view, "project-query", 40, app_editor_single::Action.RunSearch, lab_ui_geometry::rect(panel.x, panel.y + 36.0, panel.w - 70.0, 28.0), "Find in files…", true, 512);
        lab_ui_view::at_button(editor.view, "run-search", 42, app_editor_single::Action.RunSearch, lab_ui_geometry::rect(panel.x + panel.w - 62.0, panel.y + 36.0, 62.0, 28.0), "Find");
        lab_ui_view::at_button(editor.view, "cancel-search", 43, app_editor_single::Action.CancelSearch, lab_ui_geometry::rect(panel.x + panel.w - 62.0, panel.y + 72.0, 62.0, 24.0), "Stop", app.search.busy);
        lab_ui_view::at_label(editor.view, "search-summary", lab_ui_geometry::rect(panel.x, panel.y + 72.0, panel.w - 68.0, 22.0), str(app.hits.len, " hits · ", app.progress.searched, " files"), 0, theme.muted);
        let skipped: u8[>..] = if app.progress.skipped > 0 { str(" · ", app.progress.skipped, " skipped") } else { "" };
        let status: u8[>..] = if app.search.busy { str("Searching disk files…") } else if app.result >= 0 { str(lab_fs_search::message(app.result), skipped) } else { str("Literal search · Unsaved edits excluded") };
        lab_ui_view::at_label(editor.view, "project-status", lab_ui_geometry::rect(panel.x, panel.y + 96.0, panel.w, 20.0), status, 0, theme.muted);
        lab_ui_view::at_list(editor.view, r, lab_ui_view::ListConfig<app_editor_single::Action> { id: 46, scroll_id: 4, count: app.hits.len, stride: 48.0, selected: app.selected, action: app_editor_single::Action.SelectHit, enabled: !lab_document_file::busy(editor.file), framed: false, activate_on_click: true }) {
            let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(editor.view, 4), r.h, 48.0, app.hits.len);
            for i in range.first..range.end {
                let hit = app.hits[i]; let row = lab_ui_geometry::rect(r.x + 4.0, r.y + i * 48.0, max(0.0, r.w - 20.0), 48.0);
                lab_ui_view::at_list_item(editor.view, str("hit-", i), 70000 + i as u64, i, row);
                lab_ui_view::at_label(editor.view, str("hit-path-", i), lab_ui_geometry::rect(row.x + 8.0, row.y, row.w - 16.0, 26.0), str(lab_text_strings::display_bytes(hit.path, 400), ":", hit.line, ":", hit.column));
                lab_ui_view::at_label(editor.view, str("hit-preview-", i), lab_ui_geometry::rect(row.x + 8.0, row.y + 26.0, row.w - 16.0, 20.0), hit.preview, 0, theme.muted);
            }
        };
    } else {
        let status: u8[>..] = if app.explorer.code == 0 && app.explorer.skipped > 0 { str(app.explorer.skipped, " excluded entries · Expand folders") } else { lab_fs_explorer::message(app.explorer) };
        lab_ui_view::at_label(editor.view, "project-status", lab_ui_geometry::rect(panel.x, panel.y + 34.0, panel.w, 22.0), status, 0, theme.muted);
        let rows = lab_collections_tree::project(app.explorer.tree, app.explorer.state);
        if app.reveal_tree { lab_ui_views_tree::reveal(editor.view, app.explorer.tree, app.explorer.state, rows, r, 3); app.reveal_tree = false; }
        lab_ui_views_tree::at_tree(editor.view, r, lab_ui_views_tree::Config<app_editor_single::Action> { id: 47, scroll_id: 3, row_base: 50000, action: app_editor_single::Action.SelectFile, enabled: !lab_document_file::busy(editor.file) }, app.explorer.tree, app.explorer.state, rows) { node, index, rect => };
    }
}
fn open_relative(app: App&, path: const u8[:], start: i64 = -1, end: i64 = -1, query: const u8[:] = []) -> bool {
    if !lab_fs_search::relative(path) { return false; }
    open_path(app, str(app.explorer.root, "/", path), start, end, query)
}
fn open_path(app: App&, full: const u8[:], start: i64 = -1, end: i64 = -1, query: const u8[:] = []) -> bool {
    if full.len > 512 { app.editor.file.notice = "File path exceeds 512 bytes"; return false; }
    let requested = lab_document_workspace::request(app.editor.workspace, app.editor.file, lab_document_workspace::Intent { path: full, start: start, end: end, query: query });
    if app.editor.workspace.prompt { lab_ui_overlays_modal::open(app.editor.view, app.editor.modal, 1002); }
    else if requested && !lab_document_file::busy(app.editor.file) { app.editor.reveal_pending = true; app.editor.view.input.focused = 7; }
    requested
}
fn action(app: App&, event: lab_ui_view::Event<app_editor_single::Action>) -> bool {
    if event.kind==lab_ui_view::CLOSE_REQUESTED || app.editor.modal.opened || app.editor.close_modal.opened || app.editor.closing.pending || app.editor.closing.saving || app.editor.closing.ready { return app_editor_single::action(app.editor, event); }
    if event.action == app_editor_single::Action.SelectFile {
        let rows = lab_collections_tree::project(app.explorer.tree, app.explorer.state);
        let result = lab_ui_views_tree::reduce(app.explorer.tree, app.explorer.state, rows, event);
        // Arrow selection navigates the explorer; pointer selection/Enter opens leaves.
        if result.leaf >= 0 && ((event.kind == lab_ui_view::SELECT && event.pointer) || event.kind == lab_ui_view::ACTIVATE) { open_relative(app, app.explorer.tree.nodes[result.leaf].key); }
        if result.changed { app.explorer.blocked = -2; }
        if event.reveal { let after = lab_collections_tree::project(app.explorer.tree, app.explorer.state); lab_ui_views_tree::reveal(app.editor.view, app.explorer.tree, app.explorer.state, after, list_area(app), 3); }
        return result.changed || result.leaf >= 0;
    }
    if event.action == app_editor_single::Action.SelectHit && (event.kind == lab_ui_view::SELECT || event.kind == lab_ui_view::ACTIVATE) {
        if event.index >= 0 && event.index < app.hits.len {
            app.selected = event.index; let hit = app.hits[event.index];
            if event.kind == lab_ui_view::ACTIVATE { open_relative(app, hit.path, hit.start, hit.end, app.query); }
            if event.reveal { lab_ui_layout_scroll::reveal(lab_ui_view::scroll_state(app.editor.view, 4), event.index * 48.0, (event.index + 1) * 48.0, list_area(app).h, app.hits.len * 48.0); }
        } return true;
    }
    if event.kind == lab_ui_view::ACTIVATE || event.kind == lab_ui_view::SUBMIT {
        match event.action {
            Files => { app.searching = false; return true; },
            ProjectSearch => { app.searching = true; app.editor.view.input.focused = 40; return true; },
            Refresh => { lab_fs_explorer::refresh(app.explorer, app.editor.file.context); lab_document_workspace::check(app.editor.workspace); return true; },
            RunSearch => {
                let query = lab_ui_view::field_state(app.editor.view, 40).text;
                if query.len == 0 { return true; }
                app.query = query; app.hits.resize(0); app.selected = -1; app.result = -1; app.progress = lab_fs_search::Progress {};
                lab_ui_view::scroll_state(app.editor.view, 4).offset = 0.0;
                let options = lab_fs_search::Options { max_matches: 256 };
                let job = lab_fs_search_client::Job { root: app.explorer.root, query: query, options: options };
                if !lab_fs_search_client::start(app.search, job) { app.result = app.search.code; }
                return true;
            },
            CancelSearch => { lab_fs_search_client::cancel(app.search); return true; }, _ => {},
        }
    }
    app_editor_single::action(app.editor, event)
}
fn frame(app: App&) {
    poll(app); let size = gfx::screen_size(); let scale = app.editor.scale; let w = size.x / scale; let h = size.y / scale;
    lab_ui_render_scene::begin(app.editor.canvas, w, h);
    fn describe() { build(app, w, h); } fn reduce(event: lab_ui_view::Event<app_editor_single::Action>) -> bool { action(app, event) }
    lab_ui_view::frame(app.editor.view, app.editor.canvas, gfx::events(), gfx::mouse_pos(), gfx::focused(), scale, describe, reduce);
    lab_ui_views_editor::paint(app.editor.canvas, app.editor.editor, app.editor.file.document, lab_ui_view::bounds(app.editor.view, "code"), app_editor_single::config(), lab_ui_view::scroll_state(app.editor.view, 2).offset, app.editor.view.input.focused == 7);
    lab_ui_view::paint_overlays(app.editor.view, app.editor.canvas); lab_ui_render_scene::render(app.editor.canvas, lab_ui_controls_components::Theme {}.background);
}
fn destroy(app: App&) { lab_fs_search_client::close(app.search); lab_fs_explorer::close(app.explorer); app_editor_single::destroy(app.editor); }
