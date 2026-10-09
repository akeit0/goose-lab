// Explorer and project search surround the same reusable single-document editor.
namespace app_editor_workspace;
import std;
import os;
import gfx;
import lab.ui.input.shortcuts;
import workbench.editor.single;
import workbench.navigation;
import lab.fs.path;
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
    tabs: app_workbench_navigation::Tabs = app_workbench_navigation::Tabs {}, tab_generation: u64 = 0, restore_tab: bool = false,
    closing_tab: i64 = -1, saving_tab: bool = false, tab_modal: lab_ui_overlays_modal::State = lab_ui_overlays_modal::State {},
    explorer: lab_fs_explorer::State = lab_fs_explorer::State {}, search: lab_fs_search_client::State = lab_fs_search_client::State {},
    searching: bool = false, query: u8[..512] = [], hits: lab_fs_search::Hit[..256] = [], selected: i64 = -1,
    progress: lab_fs_search::Progress = lab_fs_search::Progress {}, result: i32 = -1,
    active_generation: u64 = 0, desired: u8[..512] = [], reveal_tree: bool = false,
    editor: app_editor_single::App,
}
fn create(root: const u8[:], path: const u8[:] = [], scale: f32 = 1.0, compact: bool = false) -> App {
    var app = App { editor: app_editor_single::create(path, scale, compact) };
    app.explorer = lab_fs_explorer::create(app.editor.file.context, root); app.search = lab_fs_search_client::create();
    app.editor.editing_path = false; lab_ui_controls_field::set(lab_ui_view::field_state(app.editor.view, 40), ""); app
}
// Finite foreground work only; periodic observation is deliberately excluded.
fn busy(app: const App&) -> bool {
    lab_document_file::busy(app.editor.file) || lab_fs_explorer::busy(app.explorer) || app.search.busy ||
        app.editor.workspace.saving || app.editor.workspace.opening || app.desired.len > 0
}
fn poll(app: App&) {
    app_editor_single::poll(app.editor); sync_tabs(app);
    if app.saving_tab && !lab_document_file::busy(app.editor.file) { app.saving_tab = false; if app.editor.file.code == 0 && !lab_document_model::dirty(app.editor.file.document) { finish_close_tab(app); } } lab_fs_explorer::poll(app.explorer, app.editor.file.context);
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
    let r = lab_ui_view::bounds(app.editor.view, "project"); let top: f32 = if app.searching { 116.0 } else if app.editor.compact { 34.0 } else { 62.0 };
    lab_ui_geometry::rect(r.x, r.y + top, r.w, max(0.0, r.h - top))
}
fn build(app: App&, width: f32, height: f32, project_name: const u8[:] = []) {
    let editor .= app.editor; editor.searching = app.searching; let theme = lab_ui_controls_components::Theme {}; app_editor_single::build(editor, width, height, true, project_name);
    let panel = lab_ui_view::bounds(editor.view, "project"); let r = list_area(app);
    lab_ui_view::shortcut(editor.view, "F", lab_ui_input_shortcuts::primary() | gfx::MOD_SHIFT, app_editor_single::Action.ProjectSearch);
    if !editor.compact { lab_ui_view::record(editor.view, lab_ui_view::Node<app_editor_single::Action> { name: "explorer-tab", text: "Files", id: 38, kind: lab_ui_view::BUTTON, action: app_editor_single::Action.Files, rect: lab_ui_geometry::rect(panel.x, panel.y, 68.0, 28.0), placed: true, primary: !app.searching });
    lab_ui_view::record(editor.view, lab_ui_view::Node<app_editor_single::Action> { name: "search-tab", text: "Search", id: 39, kind: lab_ui_view::BUTTON, action: app_editor_single::Action.ProjectSearch, rect: lab_ui_geometry::rect(panel.x + 76.0, panel.y, 76.0, 28.0), placed: true, primary: app.searching });
    } else { lab_ui_view::at_label(editor.view, "sidebar-title", lab_ui_geometry::rect(panel.x + 12.0, panel.y, panel.w - 80.0, 28.0), if app.searching { "SEARCH" } else { "EXPLORER" }, 0, theme.muted); }
    lab_ui_view::at_button(editor.view, "refresh-tree", 44, app_editor_single::Action.Refresh, lab_ui_geometry::rect(panel.x + panel.w - 76.0, panel.y, 76.0, 28.0), "Refresh", app.explorer.listing.id == 0, false, false, editor.compact);
    if app.searching {
        lab_ui_view::at_field(editor.view, "project-query", 40, app_editor_single::Action.RunSearch, lab_ui_geometry::rect(panel.x, panel.y + 36.0, panel.w - 70.0, 28.0), "Find in files…", true, 512);
        lab_ui_view::at_button(editor.view, "run-search", 42, app_editor_single::Action.RunSearch, lab_ui_geometry::rect(panel.x + panel.w - 62.0, panel.y + 36.0, 62.0, 28.0), "Find");
        lab_ui_view::at_button(editor.view, "cancel-search", 43, app_editor_single::Action.CancelSearch, lab_ui_geometry::rect(panel.x + panel.w - 62.0, panel.y + 72.0, 62.0, 24.0), "Stop", app.search.busy);
        lab_ui_view::at_label(editor.view, "search-summary", lab_ui_geometry::rect(panel.x, panel.y + 72.0, panel.w - 68.0, 22.0), str(app.hits.len, " hits · ", app.progress.searched, " files"), 0, theme.muted);
        let skipped: u8[>..] = if app.progress.skipped > 0 { str(" · ", app.progress.skipped, " skipped") } else { "" };
        let status: u8[>..] = if app.search.busy { str("Searching disk files…") } else if app.result >= 0 { str(lab_fs_search::message(app.result), skipped) } else { str("Literal search · Unsaved edits excluded") };
        lab_ui_view::at_label(editor.view, "project-status", lab_ui_geometry::rect(panel.x, panel.y + 96.0, panel.w, 20.0), status, 0, theme.muted);
        lab_ui_view::at_list(editor.view, r, lab_ui_view::ListConfig<app_editor_single::Action> { id: 46, scroll_id: 4, count: app.hits.len, stride: 48.0, selected: app.selected, action: app_editor_single::Action.SelectHit, blocked: lab_document_file::busy(editor.file), framed: false, activate_on_click: true }) {
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
        if !editor.compact { lab_ui_view::at_label(editor.view, "project-status", lab_ui_geometry::rect(panel.x, panel.y + 34.0, panel.w, 22.0), status, 0, theme.muted); }
        let rows = lab_collections_tree::project(app.explorer.tree, app.explorer.state);
        if app.reveal_tree { lab_ui_views_tree::reveal(editor.view, app.explorer.tree, app.explorer.state, rows, r, 3); app.reveal_tree = false; }
        lab_ui_views_tree::at_tree(editor.view, r, lab_ui_views_tree::Config<app_editor_single::Action> { id: 47, scroll_id: 3, row_base: 50000, stride: if editor.compact { 22.0 } else { 28.0 }, action: app_editor_single::Action.SelectFile, blocked: lab_document_file::busy(editor.file) }, app.explorer.tree, app.explorer.state, rows) { node, index, rect => };
    }
    if editor.compact { app_workbench_navigation::tabs(editor.view, app.tabs, app_editor_single::Action.SelectTab, app_editor_single::Action.CloseTab, lab_document_model::dirty(editor.file.document), false, "", app_editor_single::Action.WorkbenchChanges, app_editor_single::Action.PreviousTab, app_editor_single::Action.NextTab); }
    close_tab_panel(app, width, height);
}
fn open_relative(app: App&, path: const u8[:], start: i64 = -1, end: i64 = -1, query: const u8[:] = []) -> bool {
    if !lab_fs_search::relative(path) { return false; }
    open_path(app, str(app.explorer.root, "/", path), start, end, query)
}
fn open_path(app: App&, full: const u8[:], start: i64 = -1, end: i64 = -1, query: const u8[:] = []) -> bool {
    if full.len > 512 { app.editor.file.notice = "File path exceeds 512 bytes"; return false; }
    let absolute = lab_fs_path::absolute(full, 512); if absolute.code != 0 { app.editor.file.code = absolute.code; return false; }
    if app.editor.compact && tab_index(app, absolute.bytes) < 0 && app.tabs.items.len == 16 { app.editor.file.notice = "16 open tabs · Close a tab first"; return false; }
    remember_tab(app); app.restore_tab = start < 0 && tab_index(app, absolute.bytes) >= 0 && absolute.bytes != app.editor.file.path;
    let requested = lab_document_workspace::request(app.editor.workspace, app.editor.file, lab_document_workspace::Intent { path: full, start: start, end: end, query: query });
    if app.editor.workspace.prompt { lab_ui_overlays_modal::open(app.editor.view, app.editor.modal, 1002); }
    else if requested && !lab_document_file::busy(app.editor.file) { app.editor.reveal_pending = true; app.editor.view.input.focused = 7; }
    requested
}
fn action(app: App&, event: lab_ui_view::Event<app_editor_single::Action>) -> bool {
    if app.editor.compact && event.kind != lab_ui_view::CLOSE_REQUESTED {
        if app.tab_modal.opened {
            if event.kind == lab_ui_view::ACTIVATE || lab_ui_overlays_modal::backdrop(event) {
                if event.action == app_editor_single::Action.TabKeep { app.closing_tab = -1; lab_ui_overlays_modal::close(app.editor.view, app.tab_modal); }
                else if !app.saving_tab && event.action == app_editor_single::Action.TabDiscard { finish_close_tab(app); }
                else if !app.saving_tab && event.action == app_editor_single::Action.TabSave { app.saving_tab = lab_document_file::save(app.editor.file); }
            } return true;
        }
        if !app.editor.modal.opened && !app.editor.close_modal.opened && !app.editor.help.opened && (event.kind == lab_ui_view::ACTIVATE || event.kind == lab_ui_view::SUBMIT) && event.action == app_editor_single::Action.Open && app.editor.file.exists {
            let requested = open_path(app, lab_ui_view::field_state(app.editor.view, 1).text);
            if requested { app.editor.editing_path = false; } return true;
        }
        if !app.editor.modal.opened && !app.editor.close_modal.opened && !app.editor.help.opened && event.kind == lab_ui_view::ACTIVATE {
            if event.action == app_editor_single::Action.SelectTab { let index = ((event.source - 920000) / 2) as i64; return select_tab(app, index); }
            if event.action == app_editor_single::Action.CloseTab { let index = if event.source >= 920001 && event.source < 920033 { ((event.source - 920001) / 2) as i64 } else { app.tabs.active }; return close_tab(app, index); }
            if event.action == app_editor_single::Action.NextTab || event.action == app_editor_single::Action.PreviousTab {
                if app.tabs.items.len == 0 { return false; }
                return select_tab(app, (app.tabs.active + app.tabs.items.len + (if event.action == app_editor_single::Action.NextTab { 1 } else { -1 })) % app.tabs.items.len);
            }
        }
    }
    if event.kind == lab_ui_view::CLOSE_REQUESTED { app.closing_tab = -1; app.saving_tab = false; lab_ui_overlays_modal::close(app.editor.view, app.tab_modal); }
    if event.action == app_editor_single::Action.Keep { app.restore_tab = false; }
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
    lab_ui_views_editor::paint(app.editor.canvas, app.editor.editor, app.editor.file.document, lab_ui_view::bounds(app.editor.view, "code"), app_editor_single::config(app.editor.compact), lab_ui_view::scroll_state(app.editor.view, 2).offset, app.editor.view.input.focused == 7);
    lab_ui_view::paint_overlays(app.editor.view, app.editor.canvas); lab_ui_render_scene::render(app.editor.canvas, lab_ui_controls_components::Theme {}.background);
}
fn destroy(app: App&) { lab_fs_search_client::close(app.search); lab_fs_explorer::close(app.explorer); app_editor_single::destroy(app.editor); }

fn tab_index(app: const App&, path: const u8[:]) -> i64 { for i in app.tabs.items.len { if app.tabs.items[i].path == path { return i; } } -1 }
fn remember_tab(app: App&) {
    if app.tabs.active < 0 || app.tabs.active >= app.tabs.items.len { return; }
    let tab .= app.tabs.items[app.tabs.active]; let editor .= app.editor;
    if tab.path != editor.file.path { return; }
    tab.cursor = editor.file.document.selection.cursor; tab.anchor = editor.file.document.selection.anchor;
    tab.vertical = lab_ui_view::scroll_state(editor.view, 2).offset; tab.horizontal = editor.editor.horizontal.offset;
}
fn sync_tabs(app: App&) {
    if !app.editor.compact { return; }
    let path = app.editor.file.path; if path.len == 0 { return; }
    if app.tab_generation == app.editor.file.generation && app.tabs.active >= 0 && app.tabs.items[app.tabs.active].path == path { return; }
    app.tab_generation = app.editor.file.generation;
    var index = tab_index(app, path);
    if index < 0 { if app.tabs.items.len == 16 { return; } index = app.tabs.items.len; let name = app_editor_single::basename(path); app.tabs.items.push(app_workbench_navigation::Tab { path: path, name: name }); }
    app.tabs.active = index; let tab = app.tabs.items[index]; let d .= app.editor.file.document;
    if !app.restore_tab { return; } app.restore_tab = false; app.editor.reveal_pending = false;
    let cursor = min(tab.cursor, lab_document_model::size(d)); let anchor = min(tab.anchor, lab_document_model::size(d));
    if lab_document_model::boundary(d, cursor) && lab_document_model::boundary(d, anchor) { lab_document_model::select(d, cursor, anchor); }
    lab_ui_view::scroll_state(app.editor.view, 2).offset = tab.vertical; app.editor.editor.horizontal.offset = tab.horizontal;
}
fn select_tab(app: App&, index: i64) -> bool {
    if index < 0 || index >= app.tabs.items.len { return false; }
    open_path(app, app.tabs.items[index].path)
}
fn remove_tab(app: App&, index: i64) {
    for i in index..app.tabs.items.len - 1 { app.tabs.items[i] = app.tabs.items[i + 1]; }
    app.tabs.items.resize(app.tabs.items.len - 1);
    if app.tabs.active > index { app.tabs.active--; } else if app.tabs.active == index { app.tabs.active = -1; }
}
fn finish_close_tab(app: App&) {
    let index = app.closing_tab; app.closing_tab = -1; app.saving_tab = false;
    lab_ui_overlays_modal::close(app.editor.view, app.tab_modal);
    if index < 0 || index >= app.tabs.items.len { return; }
    let active = index == app.tabs.active; remove_tab(app, index); if !active { return; }
    lab_document_workspace::close(app.editor.workspace); app.editor.workspace = lab_document_workspace::State {};
    lab_ui_views_editor::clear(app.editor.editor); app.editor.editor = lab_ui_views_editor::State {};
    app.editor.file.document = lab_document_model::create(""); app.editor.file.path = []; app.editor.file.exists = false; app.editor.file.notice = []; app.editor.file.code = 0; app.editor.file.generation++;
    app.editor.editing_path = false; lab_ui_view::scroll_state(app.editor.view, 2).offset = 0.0;
    if app.tabs.items.len > 0 { select_tab(app, min(index, app.tabs.items.len - 1)); }
}
fn close_tab(app: App&, index: i64) -> bool {
    if index < 0 || index >= app.tabs.items.len || lab_document_file::busy(app.editor.file) || app.editor.workspace.opening || app.editor.workspace.saving { return false; }
    app.closing_tab = index;
    if index == app.tabs.active && lab_document_model::dirty(app.editor.file.document) { lab_ui_overlays_modal::open(app.editor.view, app.tab_modal, 940002); }
    else { finish_close_tab(app); } true
}
fn close_tab_panel(app: App&, width: f32, height: f32) {
    if !app.tab_modal.opened { return; }
    let panel = lab_ui_geometry::rect(max(8.0, (width - 460.0) / 2.0), max(8.0, (height - 180.0) / 2.0), min(460.0, width - 16.0), 180.0);
    lab_ui_overlays_modal::at_panel(app.editor.view, 940000, 940002, panel, app_editor_single::Action.TabKeep) {
        lab_ui_view::shortcut(app.editor.view, "Escape", 0, app_editor_single::Action.TabKeep);
        lab_ui_view::at_label(app.editor.view, "tab-close-title", lab_ui_geometry::rect(panel.x + 16.0, panel.y + 12.0, panel.w - 32.0, 28.0), "Save changes before closing this tab?");
        lab_ui_view::at_label(app.editor.view, "tab-close-status", lab_ui_geometry::rect(panel.x + 16.0, panel.y + 52.0, panel.w - 32.0, 36.0), lab_document_file::message(app.editor.file));
        lab_ui_view::at_button(app.editor.view, "tab-keep", 940002, app_editor_single::Action.TabKeep, lab_ui_geometry::rect(panel.x + 16.0, panel.y + 118.0, 112.0, 30.0), "Keep editing", !app.saving_tab);
        lab_ui_view::at_button(app.editor.view, "tab-discard", 940003, app_editor_single::Action.TabDiscard, lab_ui_geometry::rect(panel.x + 144.0, panel.y + 118.0, 112.0, 30.0), "Discard", !app.saving_tab);
        lab_ui_view::at_button(app.editor.view, "tab-save", 940004, app_editor_single::Action.TabSave, lab_ui_geometry::rect(panel.x + panel.w - 128.0, panel.y + 118.0, 112.0, 30.0), "Save & close", !app.saving_tab);
    };
}
