namespace app_git_viewer;
import std;
import os;
import vec;
import gfx;
import lab.ui.input.shortcuts;
import lab.io.cancel;
import lab.git.repository;
import lab.git.client;
import lab.git.history;
import lab.fs.search;
import lab.fs.search_client;
import lab.fs.glob;
import lab.text.literal_search;
import lab.text.diff;
import lab.ui.render.font;
import lab.ui.render.scene;
import lab.ui.layout.engine;
import lab.ui.geometry;
import lab.ui.view;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.text.strings;
import lab.ui.controls.components;
import lab.collections.state_bank;
import lab.collections.tree;
import lab.ui.views.tree;
import lab.git.tree;
import lab.ui.views.text;
import lab.ui.command;
import lab.ui.overlays.palette;
import lab.fs.watch;
import lab.io.debounce;
import workbench.navigation;
import lab.ui.overlays.modal;
let STRIDE: f32 = 24.0;
enum Action { None, Refresh, ChangeRepo, OpenRepo, CancelRepo, Working, Staged, Search, SelectFile, Previous, Next, Left, Right, Copy, TextInput, FindText, TextQuery, TextPrevious, TextNext, TextClose, Commands, CommandQuery, CommandChoose, CommandDismiss, AutoRefresh, History, SelectCommit, Older, Newer, Patch, Content, ProjectSearch, RunSearch, CancelSearch, IncludeQuery, IgnoreCase, SelectHit, Editor, Changes, EditFile, Help, HelpClose, SelectTab, CloseTab, NextTab, PreviousTab }
struct App {
    tabs: app_workbench_navigation::Tabs = app_workbench_navigation::Tabs {}, editor_dirty: bool = false, help: lab_ui_overlays_modal::State = lab_ui_overlays_modal::State {},
    mono_font: i64 = 3, attached: bool = false, request_editor: bool = false, request_search: bool = false, request_file: bool = false,
    canvas: lab_ui_render_scene::Canvas, view: lab_ui_view::View<Action> = lab_ui_view::View<Action> {},
    client: lab_git_client::State = lab_git_client::State {}, files: lab_git_repository::Files = lab_git_repository::Files {},
    tree: lab_collections_tree::Tree = lab_collections_tree::Tree {}, tree_state: lab_collections_tree::State = lab_collections_tree::State {},
    repo: u8[..512] = [], selected: u8[..512] = [], shown: u8[..512] = [],
    live: bool = true, watch: lab_fs_watch::Handle = lab_fs_watch::Handle {}, metadata_watch: lab_fs_watch::Handle = lab_fs_watch::Handle {}, common_watch: lab_fs_watch::Handle = lab_fs_watch::Handle {},
    watched_repo: u8[..512] = [], watch_paths: lab_git_repository::WatchPaths = lab_git_repository::WatchPaths {}, watch_code: i32 = lab_fs_watch::OK,
    changes: lab_io_debounce::State = lab_io_debounce::State {}, auto_refreshes: i64 = 0,
    project_search: bool = false, search: lab_fs_search_client::State = lab_fs_search_client::State {},
    hits: lab_fs_search::Hit[..2048] = [], hit_index: i64 = -1, search_query: u8[..512] = [], search_ignore_case: bool = false,
    ignore_case: bool = false, search_progress: lab_fs_search::Progress = lab_fs_search::Progress {}, search_result: i32 = -1,
    first_issue: lab_fs_search::Issue = default<lab_fs_search::Issue>(), shown_worktree: bool = false,
    history: bool = false, page: lab_git_history::Page = lab_git_history::Page {}, commit_index: i64 = -1,
    commit: lab_git_history::Commit = lab_git_history::Commit {}, shown_commit: u8[..64] = [],
    content: bool = false, shown_content: bool = false, loading_commit: bool = false,
    queued: lab_git_client::Job = lab_git_client::Job {},
    staged: bool = false, line: i64 = -1, scale: f32 = 1.0,
    palette: lab_ui_overlays_palette::State = lab_ui_overlays_palette::State {},
    text: lab_ui_views_text::State = lab_ui_views_text::State {}, document: lab_ui_views_text::Document = lab_ui_views_text::Document {},
    editing_repo: bool = false, switching_repo: bool = false,
    pending: bool = false,
    closing: bool = false, notice: u8[..512] = [], diff: lab_git_repository::Diff = lab_git_repository::Diff {},
}
fn repo_field(app: App&) -> lab_ui_controls_field::State& { lab_ui_view::field_state(app.view, 1) }
fn search_query(app: App&) -> lab_ui_controls_field::State& { lab_ui_view::field_state(app.view, 40) }
fn include_query(app: App&) -> lab_ui_controls_field::State& { lab_ui_view::field_state(app.view, 41) }
fn query(app: App&) -> lab_ui_controls_field::State& { lab_ui_view::field_state(app.view, 4) }
fn text_config(font: i64 = 3) -> lab_ui_views_text::Config<Action> { lab_ui_views_text::Config<Action> { id: 7, scroll_id: 2, bar_id: 17, action: Action.TextInput, font: font, stride: if font == 1 { 20.0 } else { STRIDE }, gutter: 104.0 } }
fn palette_config() -> lab_ui_overlays_palette::Config<Action> { lab_ui_overlays_palette::Config<Action> { base: 100000, scroll_id: 10, query: Action.CommandQuery, choose: Action.CommandChoose, dismiss: Action.CommandDismiss, meta_font: 2 } }
fn find_config() -> lab_ui_views_text::FindConfig<Action> { lab_ui_views_text::FindConfig<Action> { field_id: 20, previous_id: 21, next_id: 22, close_id: 23, query: Action.TextQuery, previous: Action.TextPrevious, next: Action.TextNext, close: Action.TextClose } }
fn reset_text(app: App&) {
    app.document = lab_ui_views_text::build(app.diff.patch.source, app.canvas.fonts[app.mono_font].font);
    lab_ui_views_text::reset(app.text, app.diff.patch.source);
    if app.line >= 0 { app.text.cursor = app.diff.patch.rows[app.line].start; app.text.anchor = app.text.cursor; }
}
fn create(repo: const u8[:], font: const u8[:], mono: const u8[:], scale: f32 = 1.0) -> App {
    var app = App { canvas: default<lab_ui_render_scene::Canvas>() }; app.scale = scale; app.repo = repo; app.canvas = lab_ui_render_scene::create(font, scale);
    assert(lab_ui_render_scene::add_font(app.canvas, font, 18.0) == 1); assert(lab_ui_render_scene::add_font(app.canvas, font, 13.0) == 2);
    assert(lab_ui_render_scene::add_font(app.canvas, mono, 14.0) == 3);
    app.view.defer_overlays = true;
    app.view.layout = lab_ui_layout_engine::create(app.canvas.fonts[0].font); assert(app.view.layout.id != 0);
    lab_ui_controls_field::set(repo_field(app), repo); query(app); search_query(app); lab_ui_controls_field::set(include_query(app), "**"); app.search = lab_fs_search_client::create(); app
}
// Only the font table is borrowed. The host owns all painting and GPU resources.
fn attach(repo: const u8[:], canvas: const lab_ui_render_scene::Canvas&) -> App {
    var app = App { mono_font: 1, attached: true, canvas: default<lab_ui_render_scene::Canvas>(), repo: repo, scale: canvas.scale };
    app.canvas.fonts = canvas.fonts;
    app.view.defer_overlays = true; app.view.layout = lab_ui_layout_engine::create(canvas.fonts[0].font);
    assert(app.view.layout.id != 0); lab_ui_controls_field::set(repo_field(app), repo); query(app); app
}
fn destroy(app: App&) { lab_fs_search_client::close(app.search); stop_watching(app); gfx::text_input(false); lab_ui_layout_engine::destroy(app.view.layout); if !app.attached { lab_ui_render_scene::destroy(app.canvas); } }
fn stop_watching(app: App&) {
    lab_fs_watch::close(app.watch); lab_fs_watch::close(app.metadata_watch); lab_fs_watch::close(app.common_watch); lab_io_debounce::clear(app.changes);
}
fn start_watching(app: App&) {
    stop_watching(app); app.watched_repo = app.repo;
    if !app.live || app.closing { return; }
    if app.watch_paths.code != lab_git_repository::OK { app.watch_code = lab_fs_watch::IO; return; }
    app.watch = lab_fs_watch::open(app.repo, true); app.watch_code = app.watch.code;
    if app.watch.code == lab_fs_watch::OK && !starts_with(app.watch_paths.git_dir, str(app.repo, "/")) {
        app.metadata_watch = lab_fs_watch::open(app.watch_paths.git_dir, true); app.watch_code = app.metadata_watch.code;
    }
    if app.watch_code == lab_fs_watch::OK && app.watch_paths.common_dir != app.watch_paths.git_dir && !starts_with(app.watch_paths.common_dir, str(app.repo, "/")) {
        app.common_watch = lab_fs_watch::open(app.watch_paths.common_dir, true); app.watch_code = app.common_watch.code;
    }
    if app.watch_code != lab_fs_watch::OK { stop_watching(app); }
    else { lab_io_debounce::push(app.changes, clock_ns()); } // Reconcile the snapshot read before the watch was opened.
}
fn metadata_change(path: const u8[:]) -> bool {
    path == "index" || path == "HEAD" || path == "packed-refs" || path == "config" || path == "config.worktree" || path == "info/exclude" || starts_with(path, "refs/")
}
fn watch_changes(app: App&, handle: lab_fs_watch::Handle, metadata: bool) {
    if handle.id == 0 { return; } let batch = lab_fs_watch::poll(handle);
    if batch.code != lab_fs_watch::OK { app.watch_code = batch.code; }
    var relevant = batch.rescan;
    for event in batch.events {
        if metadata { relevant = metadata_change(event.path) || relevant; }
        else if starts_with(event.path, ".git/") { relevant = metadata_change(event.path[5..]) || relevant; }
        else if event.path == ".git" { relevant = true; }
        else { relevant = !app.history || relevant; }
    }
    if relevant { lab_io_debounce::push(app.changes, clock_ns()); }
}
fn observe(app: App&) {
    if !app.live || app.closing || app.project_search { return; }
    watch_changes(app, app.watch, false); watch_changes(app, app.metadata_watch, true); watch_changes(app, app.common_watch, true);
    if app.watch_code != lab_fs_watch::OK { stop_watching(app); return; }
    if !app.client.busy && !app.pending && lab_io_debounce::ready(app.changes, clock_ns()) {
        lab_io_debounce::clear(app.changes); refresh(app, -1, false, true); if app.client.busy { app.auto_refreshes++; }
    }
}
fn visible(app: const App&) -> i64[>..] {
    let field = lab_collections_state_bank::lookup(app.view.fields, 4); let search: const u8[:] = if field { trim(field.text) } else { "" };
    var ids: i64[>..] = []; for i in app.files.items.len { if lab_text_strings::contains_folded(app.files.items[i].path, search) { ids.push(i); } } ids
}
fn tree_rows(app: const App&) -> lab_collections_tree::Rows {
    let field = lab_collections_state_bank::lookup(app.view.fields, 4); let search: const u8[:] = if field { trim(field.text) } else { "" };
    if search.len == 0 { return lab_collections_tree::project(app.tree, app.tree_state); }
    var matches: bool[..2048] = []; matches.resize(app.tree.nodes.len, false);
    for i in app.tree.nodes.len {
        let node = app.tree.nodes[i];
        if !node.branch && node.data >= 0 { matches[i] = lab_text_strings::contains_folded(app.files.items[node.data].path, search); }
    }
    lab_collections_tree::project(app.tree, app.tree_state, matches)
}
fn normalize_tree(app: App&) { let rows = tree_rows(app); lab_collections_tree::normalize(app.tree, app.tree_state, rows); }
fn first_file(app: const App&) -> i64 {
    let rows = tree_rows(app);
    for row in rows.items { let node = app.tree.nodes[row.node]; if !node.branch { return node.data; } }
    let ids = visible(app); if ids.len > 0 { ids[0] } else { -1 }
}
// Coalesce all request kinds through one worker; the latest intent owns adoption.
fn submit(app: App&, job: const lab_git_client::Job&) {
    app.notice = [];
    if app.client.busy {
        app.queued = job; app.pending = true;
        lab_io_cancel::request(app.client.token);
    } else if !lab_git_client::begin(app.client, job) { app.notice = "Unable to start Git request"; app.loading_commit = false; }
}
fn read_diff(app: App&) {
    app.notice = [];
    if app.selected.len == 0 {
        app.diff = lab_git_repository::Diff {}; app.shown = []; app.shown_commit = []; app.shown_content = false; app.line = -1; reset_text(app);
        lab_ui_view::scroll_state(app.view, 2).offset = 0.0; return;
    }
    let file = lab_git_repository::index(app.files, app.selected);
    if app.history && file >= 0 && app.files.items[file].status == 'D' { app.content = false; }
    let job = lab_git_client::Job { staged: app.staged, untracked: file >= 0 && app.files.items[file].status == '?',
        history: app.history, content: app.history && app.content, commit: app.commit, repo: app.repo, path: app.selected };
    submit(app, job);
}
fn select_commit(app: App&, index: i64) {
    if index < 0 || index >= app.page.items.len { return; }
    app.commit_index = index; app.loading_commit = true;
    let job = lab_git_client::Job { history: true, commit_files: true, commit: app.page.items[index], repo: app.repo };
    submit(app, job);
}
fn history_page(app: App&, offset: i64) {
    let job = lab_git_client::Job { refresh: true, history: true, history_listing: true, anchor: app.page.anchor, offset: offset, repo: app.repo };
    submit(app, job);
}
fn choose_visible(app: App&, load: bool = true) {
    let ids = visible(app); var keep = false;
    for id in ids { if app.files.items[id].path == app.selected { keep = true; } }
    if keep { app.tree_state.current = app.selected; normalize_tree(app); return; }
    let first = first_file(app); app.selected = if first >= 0 { app.files.items[first].path[..] } else { "" }; if load { read_diff(app); }
    app.tree_state.current = app.selected; normalize_tree(app);
}
fn run_search(app: App&) {
    let text: u8[..512] = search_query(app).text[..]; let include: u8[..256] = include_query(app).text[..];
    let literal = lab_text_literal_search::compile(text, app.ignore_case); let glob = lab_fs_glob::compile(include);
    if !literal.valid || !glob.valid || !lab_text_strings::single_line(text) { app.notice = "Enter search text and a valid include glob"; return; }
    let job = lab_fs_search_client::Job { root: app.repo, query: text, options: lab_fs_search::Options { include: include, ignore_case: app.ignore_case } };
    if !lab_fs_search_client::start(app.search, job) { app.notice = "Unable to start file search"; return; }
    app.search_query = text; app.search_ignore_case = app.ignore_case; app.hits.resize(0); app.hit_index = -1; app.selected = [];
    app.search_progress = lab_fs_search::Progress {}; app.search_result = -1; app.notice = []; app.first_issue = default<lab_fs_search::Issue>();
    lab_ui_view::scroll_state(app.view, 4).offset = 0.0;
}
fn select_hit(app: App&, index: i64) {
    if index < 0 || index >= app.hits.len { return; }
    app.hit_index = index; app.selected = app.hits[index].path;
    let job = lab_git_client::Job { staged: app.staged, content: true, repo: app.repo, path: app.selected,
        search_file: true, query: app.search_query, hit: app.hits[index], ignore_case: app.search_ignore_case };
    submit(app, job);
}
fn poll_search(app: App&) {
    if app.search.worker < 0 { return; }
    loop {
        let update, available = qpoll<lab_fs_search_client::Update>(); if !available { break; }
        if !lab_fs_search_client::accept(app.search, update) || app.closing || !app.project_search || update.root != app.repo || update.query != app.search_query { continue; }
        for hit in update.batch.hits { assert(app.hits.len < 2048); app.hits.push(hit); }
        for issue in update.batch.issues { if app.first_issue.path.len == 0 { app.first_issue = issue; } }
        app.search_progress = update.batch.progress;
        if update.batch.done { app.search_result = update.batch.result; }
        if app.hit_index < 0 && app.hits.len > 0 { select_hit(app, 0); }
        else if update.batch.done && app.hits.len == 0 { app.shown = []; app.diff = lab_git_repository::Diff {}; app.line = -1; reset_text(app); }
    }
    if app.search.code != 0 && !app.search.busy { app.search_result = app.search.code; app.notice = "Unable to start file search"; }
}
fn refresh(app: App&, mode: i32 = -1, change_repo: bool = false, preserve_history: bool = false) {
    if app.project_search && mode < 0 && !change_repo { run_search(app); return; }
    lab_fs_search_client::cancel(app.search);
    if app.client.busy && (app.client.refresh || (app.pending && app.queued.refresh)) { return; }
    let history = mode == 2 || (mode < 0 && app.history);
    let staged = if mode < 0 { app.staged } else { mode == 1 };
    let repo: u8[..512] = if change_repo { repo_field(app).text[..] } else { app.repo[..] };
    app.switching_repo = change_repo; app.loading_commit = false;
    let job = lab_git_client::Job { refresh: true, staged: staged, history: history, history_listing: history,
        anchor: if preserve_history && !change_repo { app.page.anchor[..] } else { "" },
        offset: if preserve_history && !change_repo { app.page.offset } else { 0 }, repo: repo };
    submit(app, job);
}
fn poll(app: App&) {
    poll_search(app);
    loop {
        let result, available = qpoll<lab_git_client::Completed>(); if !available { break; }
        if !lab_git_client::finish(app.client, result) || app.closing { continue; }
        if app.pending {
            app.pending = false;
            let job = app.queued; submit(app, job); continue;
        }
        if result.history_listing {
            let switching_repo = app.switching_repo; app.switching_repo = false; app.loading_commit = false;
            if result.error.len > 0 { app.notice = result.error; continue; }
            if result.page.code != 0 { app.notice = result.page.error; continue; }
            if !app.history || app.repo != result.repo {
                app.files = lab_git_repository::Files {}; app.tree = lab_collections_tree::Tree {}; app.tree_state = lab_collections_tree::State {};
                app.selected = []; app.shown = []; app.shown_commit = []; app.commit = lab_git_history::Commit {};
                app.diff = lab_git_repository::Diff {}; app.line = -1; reset_text(app);
            }
            app.project_search = false; app.history = true; app.repo = result.repo; app.page = result.page;
            if app.watched_repo != app.repo || app.watch_paths != result.watch_paths {
                app.watch_paths = result.watch_paths; start_watching(app);
            }
            if switching_repo { app.editing_repo = false; app.view.input.focused = 14; }
            if !app.editing_repo { lab_ui_controls_field::set(repo_field(app), app.repo); }
            app.commit_index = -1; lab_ui_view::scroll_state(app.view, 3).offset = 0.0;
            for i in app.page.items.len { if app.page.items[i].id == app.commit.id { app.commit_index = i; } }
            if app.commit_index < 0 && app.page.items.len > 0 { app.commit_index = 0; }
            if app.commit_index >= 0 { select_commit(app, app.commit_index); }
            else { app.files = lab_git_repository::Files {}; app.tree = lab_collections_tree::Tree {}; app.selected = []; app.commit = lab_git_history::Commit {}; read_diff(app); }
            continue;
        }
        if result.commit_files {
            if !app.history || app.project_search { continue; }
            app.loading_commit = false;
            if result.files.code != 0 { app.notice = result.files.error; continue; }
            let tree = lab_git_tree::build(result.files);
            if tree.code != 0 { app.notice = lab_collections_tree::message(tree.code); continue; }
            app.commit = result.commit; app.files = result.files; app.tree = tree;
            lab_collections_tree::prune(app.tree, app.tree_state); choose_visible(app, false); normalize_tree(app);
            read_diff(app);
            continue;
        }
        if result.refresh {
            let switching_repo = app.switching_repo; app.switching_repo = false;
            if result.error.len > 0 { app.notice = result.error; continue; }
            if result.files.code != lab_git_repository::OK { app.notice = result.files.error; continue; }
            let tree = lab_git_tree::build(result.files);
            if tree.code != lab_collections_tree::OK { app.notice = lab_collections_tree::message(tree.code); continue; }
            if app.repo != result.repo { app.tree_state = lab_collections_tree::State {}; }
            if app.history || app.staged != result.staged || app.repo != result.repo {
                app.diff = lab_git_repository::Diff {}; app.shown = []; app.line = -1; reset_text(app);
                lab_ui_view::scroll_state(app.view, 2).offset = 0.0;
            }
            let changed_repository = app.project_search || app.history || app.repo != result.repo || app.staged != result.staged;
            app.project_search = false; app.history = false; app.loading_commit = false; app.shown_commit = []; app.shown_content = false; app.shown_worktree = false;
            app.staged = result.staged; app.files = result.files; app.tree = tree; app.repo = result.repo;
            if app.watched_repo != app.repo || app.watch_paths != result.watch_paths {
                app.watch_paths = result.watch_paths; start_watching(app);
            }
            if switching_repo { app.editing_repo = false; app.view.input.focused = 14; }
            if !app.editing_repo { lab_ui_controls_field::set(repo_field(app), app.repo); }
            lab_collections_tree::prune(app.tree, app.tree_state);
            if changed_repository { lab_ui_view::scroll_state(app.view, 1).offset = 0.0; }
            let ids = visible(app); var keep = false;
            for id in ids { if app.files.items[id].path == app.selected { keep = true; } }
            if !keep { let first = first_file(app); app.selected = if first >= 0 { app.files.items[first].path[..] } else { "" }; app.tree_state.current = app.selected; }
            if changed_repository { app.tree_state.current = app.selected; }
            normalize_tree(app);
            read_diff(app);
        } else if result.repo == app.repo && result.path == app.selected && result.staged == app.staged && ((app.project_search && result.search_file && result.query == app.search_query) || (!app.project_search && !result.search_file && result.history == app.history && (!app.history || (result.commit.id == app.commit.id && result.content == app.content)))) {
            let keep = app.shown == result.path && app.diff.code == result.diff.code && app.shown_content == result.content && app.shown_commit == (if result.history { result.commit.id[..] } else { "" });
            let identical = keep && app.diff.patch.source == result.diff.patch.source;
            app.diff = copy(result.diff); app.shown = result.path; app.shown_worktree = result.search_file; app.shown_content = result.content; app.shown_commit = if result.history { result.commit.id[..] } else { "" };
            if !identical {
                if keep {
                    app.document = lab_ui_views_text::build(app.diff.patch.source, app.canvas.fonts[app.mono_font].font);
                    lab_ui_views_text::rebase(app.text, app.diff.patch.source); app.line = lab_ui_views_text::row_at(app.document, app.text.cursor);
                } else {
                    lab_ui_view::scroll_state(app.view, 2).offset = 0.0;
                    app.line = if app.diff.patch.hunks.len > 0 { app.diff.patch.hunks[0] } else if app.diff.patch.rows.len > 0 { 0 } else { -1 }; reset_text(app);
                }
            }
            if result.search_file && result.diff.code == lab_git_repository::OK {
                app.text.anchor = result.hit.start; app.text.cursor = result.hit.end; app.line = lab_ui_views_text::row_at(app.document, result.hit.start);
                lab_ui_views_text::reveal(app.view, app.canvas, app.text, app.document, app.diff.patch.source, lab_ui_view::bounds(app.view, "code"), text_config(app.mono_font));
            }
            if result.diff.code != lab_git_repository::OK { app.notice = result.diff.error; }
        }
    }
}
fn join(app: App&, worker: i64, finish_pending: bool = false) {
    if finish_pending { while app.client.busy || app.search.busy { poll(app); sleep_ms(1); } }
    app.closing = true; lab_fs_search_client::close(app.search); stop_watching(app); lab_io_cancel::request(app.client.token);
    qput(lab_git_client::Job { stop: true }); thread_wait(worker); poll(app);
}
fn jump(app: App&, direction: i64) {
    let row = lab_text_diff::next_hunk(app.diff.patch, app.line, direction); if row < 0 { return; }
    app.line = row; app.text.cursor = app.diff.patch.rows[row].start; app.text.anchor = app.text.cursor; app.text.preferred = -1.0;
    lab_ui_views_text::reveal(app.view, app.canvas, app.text, app.document, app.diff.patch.source, lab_ui_view::bounds(app.view, "code"), text_config(app.mono_font));
    app.view.input.focused = 7;
}
fn repository_name(path: const u8[:]) -> u8[>..] {
    var end = path.len;
    while end > 1 && (path[end - 1] == '/' || path[end - 1] == '\\') { end--; }
    var first: i64 = 0;
    for i in end { if path[i] == '/' || path[i] == '\\' { first = i + 1; } }
    if first == end { first = 0; }
    if end == 0 { return str("Repository"); }
    lab_git_repository::display(path[first..end])
}
fn commands(app: App&) -> lab_ui_command::Catalog<Action> {
    var c = lab_ui_command::Catalog<Action> {}; let refreshing = (app.pending && app.queued.refresh) || (app.client.busy && app.client.refresh);
    assert(lab_ui_command::add(c, 1, "Refresh repository", Action.Refresh, "Read changed files and the current patch", "git reload", "F5", 0, !refreshing, "Repository refresh in progress"));
    assert(lab_ui_command::add(c, 2, "Show working tree", Action.Working, "Changes against the index", "git unstaged mode", "1", lab_ui_input_shortcuts::primary(), !refreshing && (app.staged || app.history || app.project_search), if refreshing { "Repository refresh in progress" } else { "Already showing the working tree" }));
    assert(lab_ui_command::add(c, 3, "Show staged changes", Action.Staged, "Index against HEAD", "git index mode", "2", lab_ui_input_shortcuts::primary(), !refreshing && (!app.staged || app.history || app.project_search), if refreshing { "Repository refresh in progress" } else { "Already showing staged changes" }));
    if !app.attached { assert(lab_ui_command::add(c, 4, "Change repository", Action.ChangeRepo, "Enter a different repository directory", "git open folder path", "O", lab_ui_input_shortcuts::primary(), !refreshing && !app.editing_repo, if refreshing { "Repository refresh in progress" } else { "Repository editor is already open" })); }
    assert(lab_ui_command::add(c, 5, "Find in patch", Action.FindText, "Search the displayed patch", "text search", "F", lab_ui_input_shortcuts::primary(), app.diff.patch.source.len > 0, "No patch text to search"));
    assert(lab_ui_command::add(c, 6, "Next hunk", Action.Next, "Jump to the next changed section", "diff navigation", "F7", 0, lab_text_diff::next_hunk(app.diff.patch, app.line, 1) >= 0, "No next hunk"));
    assert(lab_ui_command::add(c, 7, "Previous hunk", Action.Previous, "Jump to the previous changed section", "diff navigation", "F7", gfx::MOD_SHIFT, lab_text_diff::next_hunk(app.diff.patch, app.line, -1) >= 0, "No previous hunk"));
    assert(lab_ui_command::add(c, 8, "Copy patch", Action.Copy, "Copy original patch bytes", "clipboard diff", "C", lab_ui_input_shortcuts::primary() | gfx::MOD_SHIFT, app.diff.patch.source.len > 0, "No patch text to copy"));
    assert(lab_ui_command::add(c, 9, "Next search match", Action.TextNext, "Move through patch search results", "find text", "F3", 0, app.text.matches.len > 0, "Search the patch first"));
    assert(lab_ui_command::add(c, 10, "Previous search match", Action.TextPrevious, "Move through patch search results", "find text", "F3", gfx::MOD_SHIFT, app.text.matches.len > 0, "Search the patch first"));
    assert(lab_ui_command::add(c, 11, if app.live && app.watch_code == lab_fs_watch::OK { "Pause automatic refresh" } else { "Enable automatic refresh" }, Action.AutoRefresh, "Watch worktree, index and refs for changes", "live files watch", "", 0, !app.project_search, "Automatic refresh resumes in Git views"));
    assert(lab_ui_command::add(c, 12, "Show commit history", Action.History, "Browse first-parent commits, files and contents", "git log history", "3", lab_ui_input_shortcuts::primary(), !refreshing && !app.history, "Already showing history or refreshing"));
    assert(lab_ui_command::add(c, 13, "Find in files", Action.ProjectSearch, "Search current project files and open matching lines", "project search files", "F", lab_ui_input_shortcuts::primary() | gfx::MOD_SHIFT, !refreshing)); c
}
fn build(app: App&, width: f32, height: f32) {
    if app.attached { build_attached(app, width, height); return; }
    let theme = lab_ui_controls_components::Theme {}; let ids = visible(app); let wide = width >= 900.0;
    let rows = tree_rows(app);
    let refreshing = (app.pending && app.queued.refresh) || (app.client.busy && app.client.refresh);
    let patch .= app.diff.patch;
    let status: u8[>..] = if app.text.copy_failed { "Unable to copy selection · Try again" } else if app.notice.len > 0 { app.notice[..] } else if refreshing { "Reading repository…" } else if app.loading_commit { "Reading commit files…" } else if app.client.busy { "Reading file… You can choose another file." }
        else if app.project_search { str(app.hits.len, " matches · ", app.search_progress.searched, " files searched · ", if app.search.busy { "Searching…" } else if app.search_result >= 0 { lab_fs_search::message(app.search_result) } else { "Enter text and press Search" }) }
        else { str(app.files.items.len, " changed files · ", if app.history { "Commit against first parent" } else if app.staged { "Index against HEAD" } else { "Working tree against index" }) };
    let revision: u8[>..] = if app.shown_commit.len > 0 { str(app.shown_commit[..8], " · ") } else { "" };
    let path: u8[>..] = if app.shown.len > 0 { str(revision, lab_git_repository::display(app.shown, 480)) } else if app.selected.len > 0 { "Loading selected file…" } else { if app.project_search { "Select a search result" } else { "No changed file selected" } };
    let details: u8[>..] = if app.diff.code != lab_git_repository::OK { app.diff.error[..] } else if patch.binary { if app.shown_content { "Binary file · Use git_history blob for exact bytes" } else { "Binary file · Git reports a binary change" } } else if app.shown_content { str(app.diff.bytes, " bytes · ", patch.rows.len, " lines · ", if app.shown_worktree { "Current working file" } else { "File at commit" }) } else { str("+", patch.added, "  −", patch.removed, "   ·   ", patch.hunks.len, " hunks") };
    let summary: u8[>..] = if app.diff.untracked && app.diff.bytes >= 0 { str("Untracked · ", app.diff.bytes, " bytes · ", details) }
        else if app.diff.untracked { str("Untracked · ", details) } else { details[..] };
    lab_ui_view::begin(app.view, width, height);
    let catalog = commands(app); lab_ui_overlays_palette::bindings(app.view, catalog);
    lab_ui_view::shortcut(app.view, "K", lab_ui_input_shortcuts::primary(), Action.Commands);
    if app.text.find_open { lab_ui_view::shortcut(app.view, "Escape", 0, Action.TextClose); }
    lab_ui_view::box(app.view, "root", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), padding: lab_ui_layout_engine::padding(16), gap: 8 }) {
        if app.attached { app_workbench_navigation::header(app.view, repository_name(app.repo), true, Action.Editor, Action.Changes, Action.EditFile, app.selected.len > 0 && !app.loading_commit); }
        else { lab_ui_view::box(app.view, "repository", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
            lab_ui_view::label(app.view, "repository-name", repository_name(app.repo), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, 1);
            lab_ui_view::button(app.view, "change-repo", 14, Action.ChangeRepo, "Change…", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(92.0), height: lab_ui_layout_engine::grow() }, false, !refreshing && !app.editing_repo);
            lab_ui_view::button(app.view, "commands", 30, Action.Commands, "Commands", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(100.0), height: lab_ui_layout_engine::grow() });
            lab_ui_view::button(app.view, "auto-refresh", 31, Action.AutoRefresh, "Auto", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(60.0), height: lab_ui_layout_engine::grow() }, app.live && app.watch_code == lab_fs_watch::OK && !app.project_search, !app.project_search);
            lab_ui_view::button(app.view, "refresh", 2, Action.Refresh, "Refresh", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(84.0), height: lab_ui_layout_engine::grow() }, false, !refreshing);
        };
        }
        if app.editing_repo {
            lab_ui_view::box(app.view, "repository-editor", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
                lab_ui_view::field(app.view, "repo", 1, Action.OpenRepo, "Repository directory…", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, !refreshing, 512);
                lab_ui_view::button(app.view, "open-repo", 15, Action.OpenRepo, "Open", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(68.0), height: lab_ui_layout_engine::grow() }, true, !refreshing);
                lab_ui_view::button(app.view, "cancel-repo", 16, Action.CancelRepo, "Cancel", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(76.0), height: lab_ui_layout_engine::grow() }, false, !refreshing);
            };
        }
        lab_ui_view::box(app.view, "tools", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
            lab_ui_view::button(app.view, "working", 3, Action.Working, "Working tree", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(124.0), height: lab_ui_layout_engine::grow() }, !app.staged && !app.history && !app.project_search, !refreshing);
            lab_ui_view::button(app.view, "staged", 5, Action.Staged, "Staged", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(80.0), height: lab_ui_layout_engine::grow() }, app.staged && !app.history && !app.project_search, !refreshing);
            lab_ui_view::button(app.view, "history", 32, Action.History, "History", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(80.0), height: lab_ui_layout_engine::grow() }, app.history, !refreshing);
            if !app.attached { lab_ui_view::button(app.view, "project-search", 38, Action.ProjectSearch, "Find in files", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(108.0), height: lab_ui_layout_engine::grow() }, app.project_search, !refreshing); }
            if app.attached { lab_ui_view::button(app.view, "refresh", 2, Action.Refresh, "Refresh", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(84.0), height: lab_ui_layout_engine::grow() }, false, !refreshing); }
            if !app.project_search { lab_ui_view::field(app.view, "search", 4, Action.Search, "Filter files…", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, !refreshing); }
        };
        if app.project_search {
            lab_ui_view::box(app.view, "search-tools", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
                lab_ui_view::field(app.view, "project-query", 40, Action.RunSearch, "Search current files…", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, true, 512);
                lab_ui_view::button(app.view, "run-search", 42, Action.RunSearch, "Search", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(76.0), height: lab_ui_layout_engine::grow() });
                lab_ui_view::button(app.view, "cancel-search", 43, Action.CancelSearch, "Stop", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(64.0), height: lab_ui_layout_engine::grow() }, false, app.search.busy);
            };
            lab_ui_view::box(app.view, "search-options", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(28.0), gap: 8 }) {
                lab_ui_view::label(app.view, "include-label", "Include", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(56.0), height: lab_ui_layout_engine::grow() }, 2, theme.muted);
                lab_ui_view::field(app.view, "include-query", 41, Action.IncludeQuery, "**/*.goose", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, true, 256);
                lab_ui_view::button(app.view, "ignore-case", 45, Action.IgnoreCase, "Ignore ASCII case", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(156.0), height: lab_ui_layout_engine::grow() }, app.ignore_case);
            };
        };
        lab_ui_view::label(app.view, "status", status, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(20.0) }, 2, theme.muted);
        if app.history {
            lab_ui_view::box(app.view, "history-panel", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(if wide { 180.0 } else { 148.0 }), gap: 4 }) {
                lab_ui_view::box(app.view, "history-tools", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(26.0), gap: 6 }) {
                    let caption: u8[>..] = if app.page.anchor.len == 0 { "No commits yet" } else { str("First-parent · ", app.page.offset + 1, "–", app.page.offset + app.page.items.len, " · HEAD ", app.page.anchor[..8]) };
                    lab_ui_view::label(app.view, "history-caption", caption, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, 2, theme.muted);
                    lab_ui_view::button(app.view, "newer", 34, Action.Newer, "Newer", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(70.0), height: lab_ui_layout_engine::grow() }, false, !refreshing && app.page.offset > 0);
                    lab_ui_view::button(app.view, "older", 35, Action.Older, "Older", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(70.0), height: lab_ui_layout_engine::grow() }, false, !refreshing && app.page.more);
                };
                lab_ui_view::leaf(app.view, "commits", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
            };
        }
        lab_ui_view::box(app.view, "workspace", lab_ui_layout_engine::Config { direction: if wide { lab_ui_layout_engine::ROW } else { lab_ui_layout_engine::COLUMN }, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), gap: 14 }) {
            lab_ui_view::leaf(app.view, "files", lab_ui_layout_engine::Config { width: if wide { lab_ui_layout_engine::fixed(if app.project_search { 360.0 } else { 280.0 }) } else { lab_ui_layout_engine::grow() }, height: if wide { lab_ui_layout_engine::grow() } else { lab_ui_layout_engine::fixed(172.0) } });
            lab_ui_view::box(app.view, "diff-card", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), padding: lab_ui_layout_engine::padding(12), gap: 8 }) {
                lab_ui_view::decoration(app.view, "diff-card");
                lab_ui_view::label(app.view, "path", path, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) });
                lab_ui_view::label(app.view, "summary", summary, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(20.0) }, 2, theme.muted);
                if app.history {
                    lab_ui_view::box(app.view, "file-mode", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(26.0), gap: 6 }) {
                        lab_ui_view::button(app.view, "patch-mode", 36, Action.Patch, "Diff", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(60.0), height: lab_ui_layout_engine::grow() }, !app.content, !app.loading_commit);
                        let chosen = lab_git_repository::index(app.files, app.selected);
                        lab_ui_view::button(app.view, "content-mode", 37, Action.Content, "File at commit", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(130.0), height: lab_ui_layout_engine::grow() }, app.content, !app.loading_commit && chosen >= 0 && app.files.items[chosen].status != 'D');
                    };
                }
                lab_ui_view::box(app.view, "navigation", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(34.0), gap: 6 }) {
                    lab_ui_view::button(app.view, "previous", 8, Action.Previous, "Prev hunk", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(90.0), height: lab_ui_layout_engine::grow() }, false, lab_text_diff::next_hunk(patch, app.line, -1) >= 0);
                    lab_ui_view::button(app.view, "next", 9, Action.Next, "Next hunk", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(90.0), height: lab_ui_layout_engine::grow() }, false, lab_text_diff::next_hunk(patch, app.line, 1) >= 0);
                    lab_ui_view::button(app.view, "left", 10, Action.Left, "←", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(36.0), height: lab_ui_layout_engine::grow() }, false, app.text.horizontal.offset > 0.0);
                    lab_ui_view::button(app.view, "right", 11, Action.Right, "→", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(36.0), height: lab_ui_layout_engine::grow() }, false, patch.rows.len > 0);
                    lab_ui_view::button(app.view, "copy", 12, Action.Copy, if app.shown_content { "Copy file" } else { "Copy patch" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(114.0), height: lab_ui_layout_engine::grow() }, false, patch.source.len > 0);
                    lab_ui_view::button(app.view, "find", 18, Action.FindText, "Find", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(62.0), height: lab_ui_layout_engine::grow() }, false, patch.source.len > 0);
                };
                lab_ui_views_text::find_bar(app.view, app.text, "text-find", find_config());
                lab_ui_view::label(app.view, "columns", if app.shown_content { "        LINE    FILE CONTENT" } else { "OLD     NEW     PATCH" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(16.0) }, 2, theme.muted);
                lab_ui_view::leaf(app.view, "code", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
            };
        };
        let skipped_detail: u8[>..] = if app.first_issue.path.len > 0 { str(" · ", lab_git_repository::display(app.first_issue.path, 180), ": ", lab_fs_search::reason(app.first_issue.reason)) } else { " · Default dependency/build exclusions · No .gitignore filtering" };
        let footer: u8[>..] = if app.project_search {
            str("Current files · ", app.search_progress.skipped, " skipped", skipped_detail)
        } else { str(ids.len, " matching files · ", if !app.live { "Auto paused" } else if app.watch_code != lab_fs_watch::OK { "Auto unavailable · Refresh manually" } else { "Auto refresh on" }, if app.history { " · First-parent history" } else { " · ? untracked · U unmerged" }) };
        lab_ui_view::label(app.view, "footer", footer, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(20.0) }, 2, theme.muted);
    };
    lab_ui_view::solve(app.view);
    describe_lists(app, refreshing, ids, rows);
    lab_ui_views_text::at_view(app.view, lab_ui_view::bounds(app.view, "code"), text_config(app.mono_font), app.text, app.document);
    lab_ui_overlays_palette::show(app.view, app.palette, palette_config(), catalog);
}
fn paint_code(app: App&) { paint_on(app, app.canvas); }
fn paint_on(app: App&, canvas: lab_ui_render_scene::Canvas&) {
    let theme = lab_ui_controls_components::Theme {};
    fn row_color(index: i64, r: lab_ui_geometry::Rect) -> float4 {
        let row = app.diff.patch.rows[index];
        lab_ui_render_scene::fill(canvas, r,
            if app.line == index { float4 { 0.19, 0.17, 0.34, 1.0 } } else if row.kind == lab_text_diff::ADD { float4 { 0.05, 0.18, 0.13, 1.0 } }
            else if row.kind == lab_text_diff::REMOVE { float4 { 0.22, 0.09, 0.12, 1.0 } } else { theme.surface });
        let old_text: u8[>..] = if row.old >= 0 { str(row.old) } else { "" };
        let new_text: u8[>..] = if row.new >= 0 { str(row.new) } else { "" };
        lab_ui_render_scene::label(canvas, app.mono_font, lab_ui_geometry::rect(r.x + 4.0, r.y, 46.0, r.h), old_text, theme.muted, true);
        lab_ui_render_scene::label(canvas, app.mono_font, lab_ui_geometry::rect(r.x + 52.0, r.y, 46.0, r.h), new_text, theme.muted, true);
        if row.kind == lab_text_diff::ADD { float4 { 0.56, 0.91, 0.70, 1.0 } }
        else if row.kind == lab_text_diff::REMOVE { float4 { 1.0, 0.62, 0.64, 1.0 } }
        else if row.kind == lab_text_diff::HUNK { float4 { 0.70, 0.66, 1.0, 1.0 } } else { theme.text }
    }
    lab_ui_views_text::paint(canvas, app.text, app.document, app.diff.patch.source, lab_ui_view::bounds(app.view, "code"), text_config(app.mono_font), lab_ui_view::scroll_state(app.view, 2).offset, app.view.input.focused == 7, row_color);
}
fn text_command(a: Action) -> lab_ui_views_text::Command, bool {
    match a {
        TextInput => { return lab_ui_views_text::Command.Input, true; }, FindText => { return lab_ui_views_text::Command.Find, true; },
        TextQuery => { return lab_ui_views_text::Command.Query, true; }, TextPrevious => { return lab_ui_views_text::Command.Previous, true; },
        TextNext => { return lab_ui_views_text::Command.Next, true; }, TextClose => { return lab_ui_views_text::Command.Close, true; },
        _ => { return lab_ui_views_text::Command.Input, false; }
    }
}
fn action(app: App&, event: lab_ui_view::Event<Action>) -> bool {
    if app.help.opened {
        if event.action == Action.HelpClose && (event.kind == lab_ui_view::ACTIVATE || lab_ui_overlays_modal::backdrop(event)) { lab_ui_overlays_modal::close(app.view, app.help); } return true;
    }
    if event.action == Action.Help && event.kind == lab_ui_view::ACTIVATE { lab_ui_overlays_modal::open(app.view, app.help, 930002); return true; }
    if event.action == Action.Commands && event.kind == lab_ui_view::ACTIVATE { lab_ui_overlays_palette::open(app.view, app.palette, palette_config()); return true; }
    if event.action == Action.CommandQuery || event.action == Action.CommandChoose || event.action == Action.CommandDismiss {
        let catalog = commands(app); let result = lab_ui_overlays_palette::reduce(app.view, app.palette, palette_config(), catalog, event);
        if result.invoked { apply_action(app, lab_ui_view::Event<Action> { kind: lab_ui_view::ACTIVATE, action: result.action, source: 0 }); }
        return result.changed;
    }
    apply_action(app, event)
}
fn apply_action(app: App&, event: lab_ui_view::Event<Action>) -> bool {
    let command, text_action = text_command(event.action);
    if text_action {
        let changed = lab_ui_views_text::handle(app.view, app.canvas, app.text, app.document, app.diff.patch.source, lab_ui_view::bounds(app.view, "code"), text_config(app.mono_font), find_config(), command, event);
        app.line = lab_ui_views_text::row_at(app.document, app.text.cursor); return changed;
    }
    if event.action == Action.Search && event.kind == lab_ui_view::CHANGE { if !app.loading_commit { choose_visible(app); } lab_ui_view::scroll_state(app.view, 1).offset = 0.0; return true; }
    if event.action == Action.SelectHit && (event.kind == lab_ui_view::SELECT || event.kind == lab_ui_view::ACTIVATE) {
        if event.index >= 0 && event.index < app.hits.len {
            if event.index != app.hit_index || app.shown != app.hits[event.index].path { select_hit(app, event.index); }
            if event.reveal { let r = lab_ui_view::bounds(app.view, "files"); lab_ui_layout_scroll::reveal(lab_ui_view::scroll_state(app.view, 4), event.index * 48.0, (event.index + 1) * 48.0, r.h - 16.0, app.hits.len * 48.0); }
        } return true;
    }
    if event.action == Action.SelectCommit && (event.kind == lab_ui_view::SELECT || event.kind == lab_ui_view::ACTIVATE) {
        if event.index >= 0 && event.index < app.page.items.len {
            if event.index != app.commit_index || app.commit.id != app.page.items[event.index].id { select_commit(app, event.index); }
            if event.reveal { lab_ui_layout_scroll::reveal(lab_ui_view::scroll_state(app.view, 3), event.index * 48.0, (event.index + 1) * 48.0, lab_ui_view::bounds(app.view, "commits").h, app.page.items.len * 48.0); }
        } return true;
    }
    if event.action == Action.SelectFile {
        let rows = tree_rows(app); let result = lab_ui_views_tree::reduce(app.tree, app.tree_state, rows, event);
        if result.leaf >= 0 && result.leaf < app.files.items.len {
            let path = app.files.items[result.leaf].path;
            if path != app.selected { app.selected = path; read_diff(app); }
        }
        if event.reveal {
            let after = tree_rows(app); let files = lab_ui_view::bounds(app.view, "files");
            lab_ui_views_tree::reveal(app.view, app.tree, app.tree_state, after, lab_ui_geometry::rect(files.x + 8.0, files.y + 8.0, files.w - 16.0, files.h - 16.0), 1);
        } return result.changed || result.leaf >= 0;
    }
    if event.kind != lab_ui_view::ACTIVATE && event.kind != lab_ui_view::SUBMIT { return false; }
    match event.action {
        Refresh => { refresh(app); },
        AutoRefresh => { app.live = !app.live || app.watch_code != lab_fs_watch::OK; start_watching(app); },
        ChangeRepo => { lab_ui_controls_field::set(repo_field(app), app.repo); app.editing_repo = true; app.view.input.focused = 1; },
        OpenRepo => { refresh(app, -1, true); },
        CancelRepo => { lab_ui_controls_field::set(repo_field(app), app.repo); app.editing_repo = false; app.view.input.focused = 14; },
        Working => { if app.staged || app.history || app.project_search { refresh(app, 0); } },
        Staged => { if !app.staged || app.history || app.project_search { refresh(app, 1); } },
        History => { if !app.history || app.project_search { refresh(app, 2); } },
        Editor => { app.request_editor = true; }, Changes => {}, EditFile => { app.request_file = true; },
        ProjectSearch => {
            if app.attached { app.request_search = true; return true; }
            lab_fs_search_client::cancel(app.search); lab_io_cancel::request(app.client.token); app.pending = false;
            app.project_search = true; app.history = false; app.loading_commit = false; lab_io_debounce::clear(app.changes);
            app.notice = []; app.view.input.focused = 40;
        },
        RunSearch => { run_search(app); }, CancelSearch => { lab_fs_search_client::cancel(app.search); },
        IgnoreCase => { app.ignore_case = !app.ignore_case; }, IncludeQuery => {}, SelectHit => {},
        Older => { if app.page.more { history_page(app, app.page.offset + 32); } },
        Newer => { if app.page.offset > 0 { history_page(app, max(0, app.page.offset - 32)); } },
        Patch => { if app.content { app.content = false; read_diff(app); } },
        Content => { if !app.content { app.content = true; read_diff(app); } },
        SelectCommit => {},
        Previous => { jump(app, -1); }, Next => { jump(app, 1); },
        Left => { app.text.horizontal.offset = max(0.0, app.text.horizontal.offset - 160.0); }, Right => { app.text.horizontal.offset += 160.0; },
        Copy => { app.text.copy_failed = false; app.notice = if gfx::set_clipboard(app.diff.patch.source) { if app.shown_content { "File copied · Original bytes preserved" } else { "Patch copied · Original bytes preserved" } } else { "Unable to copy the patch · Try again" }; },
        Commands => {}, CommandQuery => {}, CommandChoose => {}, CommandDismiss => {},
        Help => {}, HelpClose => {}, SelectTab => {}, CloseTab => {}, NextTab => {}, PreviousTab => {}, None => {}, Search => {}, SelectFile => {}, TextInput => {}, FindText => {}, TextQuery => {}, TextPrevious => {}, TextNext => {}, TextClose => {},
    } true
}
fn frame(app: App&) {
    poll(app); observe(app); let size = gfx::screen_size(); let w: f32 = size.x / app.scale; let h: f32 = size.y / app.scale;
    lab_ui_render_scene::begin(app.canvas, w, h);
    fn describe() { build(app, w, h); }
    fn reduce(event: lab_ui_view::Event<Action>) -> bool { action(app, event) }
    lab_ui_view::frame(app.view, app.canvas, gfx::events(), gfx::mouse_pos(), gfx::focused(), app.scale, describe, reduce);
    paint_code(app); lab_ui_view::paint_overlays(app.view, app.canvas); lab_ui_render_scene::render(app.canvas, lab_ui_controls_components::Theme {}.background);
}

fn describe_lists(app: App&, refreshing: bool, ids: const i64[:], rows: const lab_collections_tree::Rows&) {
    let theme = lab_ui_controls_components::Theme {};
    let files = lab_ui_view::bounds(app.view, "files"); if !app.attached { lab_ui_view::at_decoration(app.view, "files-card", files); }
    let area = lab_ui_geometry::rect(files.x + 8.0, files.y + 8.0, files.w - 16.0, files.h - 16.0);
    if app.project_search {
        if app.hits.len == 0 { lab_ui_view::at_label(app.view, "empty-results", lab_ui_geometry::rect(area.x + 8.0, area.y + 10.0, area.w - 16.0, 26.0), if app.search.busy { "Searching…" } else if app.search_result >= 0 { "No matches returned" } else { "Enter text to search current files" }, 2, theme.muted); }
        lab_ui_view::at_list(app.view, area, lab_ui_view::ListConfig<Action> { id: 44, scroll_id: 4, count: app.hits.len, stride: 48.0, selected: app.hit_index, action: Action.SelectHit, framed: false }) {
            let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(app.view, 4), area.h, 48.0, app.hits.len);
            for i in range.first..range.end {
                let hit = app.hits[i]; let r = lab_ui_geometry::rect(area.x + 4.0, area.y + i * 48.0, max(0.0, area.w - 20.0), 48.0);
                lab_ui_view::at_list_item(app.view, str("hit-", i), 70000 + i as u64, i, r);
                lab_ui_view::at_label(app.view, str("hit-path-", i), lab_ui_geometry::rect(r.x + 8.0, r.y, r.w - 16.0, 26.0), str(lab_git_repository::display(hit.path, 400), ":", hit.line, ":", hit.column));
                lab_ui_view::at_label(app.view, str("hit-preview-", i), lab_ui_geometry::rect(r.x + 8.0, r.y + 26.0, r.w - 16.0, 20.0), hit.preview, 2, theme.muted);
            }
        };
    } else {
    if ids.len == 0 { lab_ui_view::at_label(app.view, "empty-files", lab_ui_geometry::rect(area.x + 8.0, area.y + 10.0, area.w - 16.0, 26.0), "No matching changes", 2, theme.muted); }
    lab_ui_views_tree::at_tree(app.view, area, lab_ui_views_tree::Config<Action> { id: 6, scroll_id: 1, row_base: 50000, action: Action.SelectFile, blocked: refreshing || app.loading_commit, stride: if app.attached { 22.0 } else { 28.0 }, trailing: 24.0 }, app.tree, app.tree_state, rows) { node, index, r =>
        let item = app.tree.nodes[node];
        if !item.branch && item.data >= 0 {
            let file = app.files.items[item.data]; let letter: u8[1] = [file.status];
            let sw = lab_ui_render_font::width(app.canvas.fonts[0].font, letter);
            lab_ui_view::at_label(app.view, str("file-status-", index), lab_ui_geometry::rect(r.x + r.w - 12.0 - sw, r.y, sw, r.h), letter, 0, theme.muted);
        }
    };
    }
    if app.history {
        let area = lab_ui_view::bounds(app.view, "commits");
        lab_ui_view::at_list(app.view, area, lab_ui_view::ListConfig<Action> { id: 33, scroll_id: 3, count: app.page.items.len, stride: 48.0, selected: app.commit_index, action: Action.SelectCommit, blocked: refreshing, framed: false }) {
            let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(app.view, 3), area.h, 48.0, app.page.items.len);
            for i in range.first..range.end {
                let item = app.page.items[i]; let r = lab_ui_geometry::rect(area.x + 4.0, area.y + i * 48.0, max(0.0, area.w - 20.0), 48.0);
                lab_ui_view::at_list_item(app.view, str("commit-", i), 60000 + i as u64, i, r);
                let subject: u8[>..] = if item.subject.len > 0 { lab_git_repository::display(item.subject) } else { "(No subject)" };
                lab_ui_view::at_label(app.view, str("commit-subject-", i), lab_ui_geometry::rect(r.x + 12.0, r.y, r.w - 24.0, 26.0), subject);
                lab_ui_view::at_label(app.view, str("commit-meta-", i), lab_ui_geometry::rect(r.x + 12.0, r.y + 26.0, r.w - 24.0, 20.0), str(item.id[..8], " · ", lab_text_strings::display_bytes(item.author, 120), " · ", item.date, if item.parents > 1 { " · merge" } else { "" }), 2, theme.muted);
            }
        };
    }
}

fn build_attached(app: App&, width: f32, height: f32) {
    let theme = lab_ui_controls_components::Theme {}; let ids = visible(app); let rows = tree_rows(app); let patch .= app.diff.patch;
    let refreshing = (app.pending && app.queued.refresh) || (app.client.busy && app.client.refresh);
    lab_ui_view::begin(app.view, width, height); let catalog = commands(app); lab_ui_overlays_palette::bindings(app.view, catalog);
    let primary = lab_ui_input_shortcuts::primary();
    lab_ui_view::shortcut(app.view, "K", primary, Action.Commands); lab_ui_view::shortcut(app.view, "F1", 0, Action.Help);
    lab_ui_view::shortcut(app.view, "E", primary | gfx::MOD_SHIFT, Action.Editor);
    lab_ui_view::shortcut(app.view, "G", primary | gfx::MOD_SHIFT, Action.Changes);
    lab_ui_view::shortcut(app.view, "Tab", gfx::MOD_CTRL, Action.NextTab); lab_ui_view::shortcut(app.view, "Tab", gfx::MOD_CTRL | gfx::MOD_SHIFT, Action.PreviousTab);
    lab_ui_view::shortcut(app.view, "W", primary, Action.CloseTab);
    if app.text.find_open { lab_ui_view::shortcut(app.view, "Escape", 0, Action.TextClose); }
    let status = str(ids.len, " files   ", if app.history { "History · First parent" } else if app.staged { "Staged · Index against HEAD" } else { "Working tree · Against index" }, "   ", if refreshing { "Refreshing changes…" } else if app.loading_commit { "Reading commit files…" } else if app.client.busy || app.pending { "Reading file…" } else if app.notice.len > 0 { app.notice[..] } else if app.diff.code != 0 { app.diff.error[..] } else { "" });
    app_workbench_navigation::shell(app.view, width, repository_name(app.repo), true, false, Action.Editor, Action.Changes, Action.ProjectSearch, Action.Help, "git-sidebar", status, app.history) {
        lab_ui_view::box(app.view, "navigation", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(28.0), gap: 2 }) {
            lab_ui_view::label(app.view, "summary", str("+", patch.added, "  −", patch.removed), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, 0, theme.muted);
            lab_ui_view::button(app.view, "workbench-open-file", 900003, Action.EditFile, "Edit file", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(64.0), height: lab_ui_layout_engine::grow() }, false, app.selected.len > 0 && !app.loading_commit, true);
            if app.history {
                lab_ui_view::button(app.view, "patch-mode", 36, Action.Patch, "Diff", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(42.0), height: lab_ui_layout_engine::grow() }, !app.content, !app.loading_commit, true);
                let chosen = lab_git_repository::index(app.files, app.selected);
                lab_ui_view::button(app.view, "content-mode", 37, Action.Content, "At commit", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(66.0), height: lab_ui_layout_engine::grow() }, app.content, !app.loading_commit && chosen >= 0 && app.files.items[chosen].status != 'D', true);
            }
            lab_ui_view::button(app.view, "previous", 8, Action.Previous, "Prev", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(40.0), height: lab_ui_layout_engine::grow() }, false, lab_text_diff::next_hunk(patch, app.line, -1) >= 0, true);
            lab_ui_view::button(app.view, "next", 9, Action.Next, "Next", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(40.0), height: lab_ui_layout_engine::grow() }, false, lab_text_diff::next_hunk(patch, app.line, 1) >= 0, true);
            lab_ui_view::button(app.view, "find", 18, Action.FindText, "Find", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(40.0), height: lab_ui_layout_engine::grow() }, false, patch.source.len > 0, true);
        };
        lab_ui_views_text::find_bar(app.view, app.text, "text-find", find_config());
        lab_ui_view::leaf(app.view, "code", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
    };
    lab_ui_view::solve(app.view);
    let panel = lab_ui_view::bounds(app.view, "git-tools"); let x = panel.x + 8.0; let w = panel.w - 16.0;
    lab_ui_view::at_label(app.view, "sidebar-title", lab_ui_geometry::rect(x + 4.0, panel.y, w - 66.0, 28.0), if panel.w >= 240.0 { "SOURCE CONTROL" } else { "GIT" }, 0, theme.muted);
    lab_ui_view::at_button(app.view, "refresh", 2, Action.Refresh, lab_ui_geometry::rect(x + w - 60.0, panel.y, 60.0, 28.0), "Refresh", !refreshing, false, false, true);
    for i in 3 {
        let action = if i == 0 { Action.Working } else if i == 1 { Action.Staged } else { Action.History };
        lab_ui_view::record(app.view, lab_ui_view::Node<Action> { name: if i == 0 { "working" } else if i == 1 { "staged" } else { "history" }, text: if i == 0 { "Changes" } else if i == 1 { "Staged" } else { "History" }, id: if i == 0 { 3 } else if i == 1 { 5 } else { 32 }, kind: lab_ui_view::BUTTON, action: action, rect: lab_ui_geometry::rect(x + i * w / 3.0, panel.y + 28.0, w / 3.0, 28.0), placed: true, primary: if i == 0 { !app.staged && !app.history } else if i == 1 { app.staged && !app.history } else { app.history }, enabled: !refreshing, flat: true });
    }
    lab_ui_view::at_field(app.view, "search", 4, Action.Search, lab_ui_geometry::rect(x, panel.y + 62.0, w, 26.0), "Filter files…", !refreshing);
    if app.history {
        let area = lab_ui_view::bounds(app.view, "history-tools");
        lab_ui_view::at_label(app.view, "history-caption", lab_ui_geometry::rect(area.x + 12.0, area.y, area.w - 100.0, 26.0), "COMMITS", 0, theme.muted);
        lab_ui_view::at_button(app.view, "newer", 34, Action.Newer, lab_ui_geometry::rect(area.x + area.w - 100.0, area.y, 48.0, 26.0), "Newer", !refreshing && app.page.offset > 0, false, false, true);
        lab_ui_view::at_button(app.view, "older", 35, Action.Older, lab_ui_geometry::rect(area.x + area.w - 52.0, area.y, 48.0, 26.0), "Older", !refreshing && app.page.more, false, false, true);
    }
    describe_lists(app, refreshing, ids, rows);
    let revision: u8[>..] = if app.shown_commit.len > 0 { str(" @", app.shown_commit[..8]) } else { "" };
    let name: u8[>..] = str(if app.shown.len > 0 { app.shown[..] } else { "Diff" }, revision, if app.shown_content { " · File" } else { " · Diff" });
    app_workbench_navigation::tabs(app.view, app.tabs, Action.SelectTab, Action.CloseTab, app.editor_dirty, true, name, Action.Changes, Action.PreviousTab, Action.NextTab);
    lab_ui_views_text::at_view(app.view, lab_ui_view::bounds(app.view, "code"), text_config(app.mono_font), app.text, app.document);
    lab_ui_overlays_palette::show(app.view, app.palette, palette_config(), catalog); app_workbench_navigation::help(app.view, app.help, Action.HelpClose);
}
