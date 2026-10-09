namespace app_api_browser;
import std;
import vec;
import gfx;
import lab.ui.input.shortcuts;
import lab.net.http;
import api_browser.feed;
import api_browser.client;
import api_browser.snapshot;
import lab.json.file;
import lab.json.codec;
import lab.text.strings;
import lab.ui.render.font;
import lab.ui.render.scene;
import lab.ui.layout.engine;
import lab.ui.geometry;
import lab.ui.view;
import lab.ui.layout.scroll;
import lab.ui.controls.field;
import lab.ui.controls.components;
import lab.collections.state_bank;
import lab.ui.views.text;
import lab.ui.command;
import lab.ui.overlays.palette;
import lab.fs.watch;
import lab.io.debounce;
import lab.fs.files;
import lab.ui.overlays.modal;
enum Action { None, Fetch, Cancel, Example, Search, Select, Toggle, Export, Save, Reload, Record, Response, CopyResponse, TextInput, FindText, TextQuery, TextPrevious, TextNext, TextClose, Commands, CommandQuery, CommandChoose, CommandDismiss, DiskReview, DiskLoad, DiskLocal, DiskDismiss }
struct App {
    canvas: lab_ui_render_scene::Canvas, view: lab_ui_view::View<Action> = lab_ui_view::View<Action> {}, detail_layout: lab_ui_layout_engine::Context,
    feed: app_api_feed::Feed = app_api_feed::Feed {}, client: app_api_client::State = app_api_client::State {},
    selected: i64 = -1, changed: bool = false, copied: bool = false, copy_failed: bool = false, scale: f32 = 1.0,
    source: u8[..512] = "Offline example",
    path: u8[..2048] = [], dirty: bool = false, blocked: bool = false, restored: bool = false,
    disk_notice: u8[..256] = [], external: bool = false,
    monitor: lab_fs_watch::Handle = lab_fs_watch::Handle {}, monitored_path: u8[..2048] = [], monitor_stopped: bool = false,
    baseline: lab_fs_files::Revision = lab_fs_files::Revision { code: lab_fs_files::MISSING }, observed: lab_fs_files::Revision = lab_fs_files::Revision { code: lab_fs_files::MISSING },
    changes: lab_io_debounce::State = lab_io_debounce::State {}, disk_dialog: lab_ui_overlays_modal::State = lab_ui_overlays_modal::State {}, disk_valid: bool = false, disk_local_ok: bool = false,
    show_response: bool = false, response_label: u8[..256] = [], response_copied: bool = false,
    palette: lab_ui_overlays_palette::State = lab_ui_overlays_palette::State {},
    text: lab_ui_views_text::State = lab_ui_views_text::State {}, document: lab_ui_views_text::Document = lab_ui_views_text::Document {},
    response: u8[>..<] = [],
}
fn url(app: App&) -> lab_ui_controls_field::State& { lab_ui_view::field_state(app.view, 1) }
fn query(app: App&) -> lab_ui_controls_field::State& { lab_ui_view::field_state(app.view, 4) }
fn text_config() -> lab_ui_views_text::Config<Action> { lab_ui_views_text::Config<Action> { id: 15, scroll_id: 3, bar_id: 16, action: Action.TextInput, font: 3 } }
fn palette_config() -> lab_ui_overlays_palette::Config<Action> { lab_ui_overlays_palette::Config<Action> { base: 100000, scroll_id: 10, query: Action.CommandQuery, choose: Action.CommandChoose, dismiss: Action.CommandDismiss, meta_font: 2 } }
fn find_config() -> lab_ui_views_text::FindConfig<Action> { lab_ui_views_text::FindConfig<Action> { field_id: 20, previous_id: 21, next_id: 22, close_id: 23, query: Action.TextQuery, previous: Action.TextPrevious, next: Action.TextNext, close: Action.TextClose } }
fn response(app: App&, bytes: const u8[:], label: const u8[:]) {
    assert(bytes.len <= 2097152); app.response = bytes; app.response_label = label; app.response_copied = false;
    app.document = lab_ui_views_text::build(app.response, app.canvas.fonts[3].font);
    lab_ui_views_text::reset(app.text, app.response); lab_ui_view::scroll_state(app.view, 3).offset = 0.0;
}
fn encoded_response(app: App&, label: const u8[:]) {
    let encoded, ok = app_api_feed::encode(app.feed); response(app, if ok { encoded[..] } else { "" }, label);
}
fn create(font: const u8[:], scale: f32 = 1.0, path: const u8[:] = "") -> App {
    var app = App { canvas: default<lab_ui_render_scene::Canvas>(), detail_layout: lab_ui_layout_engine::Context { id: 0 } }; app.scale = scale; app.selected = 1;
    app.feed = app_api_feed::example(); app.canvas = lab_ui_render_scene::create(font, scale);
    assert(app.canvas.fonts.len == 1); assert(lab_ui_render_scene::add_font(app.canvas, font, 27.0) == 1); assert(lab_ui_render_scene::add_font(app.canvas, font, 13.0) == 2);
    assert(lab_ui_render_scene::add_font(app.canvas, lab_ui_render_font::default_mono(), 14.0) == 3);
    app.view.defer_overlays = true;
    app.view.layout = lab_ui_layout_engine::create(app.canvas.fonts[0].font); assert(app.view.layout.id != 0);
    app.detail_layout = lab_ui_layout_engine::create(app.canvas.fonts[0].font); assert(app.detail_layout.id != 0);
    lab_ui_controls_field::set(url(app), "https://jsonplaceholder.typicode.com/todos?_limit=12"); query(app);
    encoded_response(app, "Example JSON · Generated from the offline records");
    assert(path.len <= 2048); app.path = path; configure_monitor(app); if path.len > 0 { reload(app); } app
}
fn destroy(app: App&) { lab_fs_watch::close(app.monitor); gfx::text_input(false); lab_ui_layout_engine::destroy(app.detail_layout); lab_ui_layout_engine::destroy(app.view.layout); lab_ui_render_scene::destroy(app.canvas); }
fn visible(app: const App&) -> i64[>..] {
    var ids: i64[>..] = []; let field = lab_collections_state_bank::lookup(app.view.fields, 4);
    let search: const u8[:] = if field { field.text[..] } else { "" };
    for item in app.feed.items { if lab_text_strings::contains_folded(item.title, trim(search)) { ids.push(item.id); } } ids
}
fn adopt(app: App&, feed: const app_api_feed::Feed&) {
    app.feed = feed; app.changed = false; app.copied = false; app.copy_failed = false;
    app.dirty = feed.code == app_api_feed::OK; app.disk_notice = [];
    let ids = visible(app); var found = false; for id in ids { if id == app.selected { found = true; } }
    if !found { app.selected = if ids.len > 0 { ids[0] } else { -1 }; }
    lab_ui_view::scroll_state(app.view, 1).offset = 0.0;
    lab_ui_view::scroll_state(app.view, 2).offset = 0.0;
}
fn configure_monitor(app: App&) {
    lab_fs_watch::close(app.monitor); app.monitored_path = app.path; app.external = false; lab_io_debounce::clear(app.changes);
    if app.path.len == 0 { app.baseline = lab_fs_files::Revision { code: lab_fs_files::MISSING }; return; }
    app.baseline = lab_fs_files::revision(app.path); app.observed = app.baseline;
    let parent, name = lab_fs_watch::parent(app.path); app.monitor = lab_fs_watch::open(parent);
}
fn acknowledge(app: App&, revision: lab_fs_files::Revision) {
    app.baseline = revision; app.observed = revision; app.external = false; lab_io_debounce::clear(app.changes);
    lab_ui_overlays_modal::close(app.view, app.disk_dialog);
}
fn check_disk(app: App&) {
    let revision = lab_fs_files::revision(app.path); let was_external = app.external;
    app.external = revision != app.baseline;
    if !app.external && was_external { app.disk_notice = "Saved file matches the known version again"; lab_ui_overlays_modal::close(app.view, app.disk_dialog); }
    else if app.external && app.disk_dialog.opened && revision != app.observed {
        let loaded = app_api_snapshot::load(app.path); app.disk_valid = loaded.code == lab_json_file::OK;
        app.disk_local_ok = app.disk_valid || loaded.code == lab_json_file::MISSING;
        app.disk_notice = if app.disk_local_ok { "File changed again · Choose which version to keep" }
            else { str(app_api_snapshot::message(loaded.code), " · Current records kept") };
    }
}
fn observe(app: App&) {
    if app.monitor_stopped { return; }
    if app.monitored_path != app.path { configure_monitor(app); }
    if app.monitor.id != 0 {
        let batch = lab_fs_watch::poll(app.monitor); var changed = batch.rescan;
        let parent, name = lab_fs_watch::parent(app.path);
        for event in batch.events { if lab_text_strings::equal_folded(event.path, name) { changed = true; } }
        if changed { lab_io_debounce::push(app.changes, clock_ns()); }
        if batch.code != lab_fs_watch::OK { lab_fs_watch::close(app.monitor); app.monitor.code = batch.code; }
    }
    if app.path.len > 0 && lab_io_debounce::ready(app.changes, clock_ns()) { lab_io_debounce::clear(app.changes); check_disk(app); }
}
fn apply_snapshot(app: App&, loaded: const app_api_snapshot::Loaded&) {
    let snapshot = loaded.snapshot;
    lab_ui_controls_field::set(url(app), snapshot.url); lab_ui_controls_field::set(query(app), snapshot.query);
    app.selected = snapshot.selected; adopt(app, snapshot.feed);
    app.changed = snapshot.changed; app.source = snapshot.source; app.dirty = false;
    app.blocked = false; app.restored = true; app.client.status = 0;
    app.client.cancelled = false; app.client.start_failed = false;
    encoded_response(app, "Snapshot JSON · Generated from the saved records");
    acknowledge(app, loaded.revision); app.disk_notice = "Snapshot restored";
}
fn review_disk(app: App&) {
    if app.client.busy || !app.external { return; }
    let loaded = app_api_snapshot::load(app.path); app.disk_valid = loaded.code == lab_json_file::OK;
    app.disk_local_ok = app.disk_valid || loaded.code == lab_json_file::MISSING;
    app.observed = if app.disk_valid { loaded.revision } else { lab_fs_files::revision(app.path) };
    app.disk_notice = if app.disk_local_ok { "" } else { str(app_api_snapshot::message(loaded.code), " · Current records kept") };
    lab_ui_overlays_modal::open(app.view, app.disk_dialog, 200005);
}
fn disk_dialog(app: App&) {
    if !app.disk_dialog.opened { return; }
    let screen = app.view.screen; let width = min(600.0, max(0.0, screen.w - 32.0));
    let r = lab_ui_geometry::rect((screen.w - width) * 0.5, max(16.0, (screen.h - 250.0) * 0.5), width, 250.0); let theme = lab_ui_controls_components::Theme {};
    lab_ui_overlays_modal::at_panel(app.view, 200000, 200005, r, Action.DiskDismiss) {
        lab_ui_view::shortcut(app.view, "Escape", 0, Action.DiskDismiss);
        lab_ui_view::at_label(app.view, "disk-title", lab_ui_geometry::rect(r.x + 16.0, r.y + 16.0, r.w - 32.0, 28.0), "Snapshot changed externally");
        lab_ui_view::at_label(app.view, "disk-reload-help", lab_ui_geometry::rect(r.x + 16.0, r.y + 62.0, r.w - 32.0, 24.0), "Load file replaces current records and unsaved edits.", 2, theme.muted);
        lab_ui_view::at_label(app.view, "disk-local-help", lab_ui_geometry::rect(r.x + 16.0, r.y + 90.0, r.w - 32.0, 24.0), "Use local keeps your records; next Save replaces the file.", 2, theme.muted);
        lab_ui_view::at_label(app.view, "disk-error", lab_ui_geometry::rect(r.x + 16.0, r.y + 128.0, r.w - 32.0, 32.0), if app.disk_notice.len > 0 { app.disk_notice[..] } else if !app.disk_valid { "Saved file was deleted. Use local to recreate it on Save." } else { "Choose which version to keep, or decide later." }, 2, theme.muted);
        lab_ui_view::at_button(app.view, "disk-load", 200003, Action.DiskLoad, lab_ui_geometry::rect(r.x + 16.0, r.y + 194.0, 110.0, 36.0), "Load file", app.disk_valid && !app.client.busy);
        lab_ui_view::at_button(app.view, "disk-local", 200004, Action.DiskLocal, lab_ui_geometry::rect(r.x + 134.0, r.y + 194.0, 110.0, 36.0), "Use local", app.disk_local_ok && !app.client.busy);
        lab_ui_view::at_button(app.view, "disk-dismiss", 200005, Action.DiskDismiss, lab_ui_geometry::rect(r.x + r.w - 106.0, r.y + 194.0, 90.0, 36.0), "Later");
    };
}
// Reload only after record edits have been saved. A rejected file never changes
// the current model and blocks Save until a valid/missing file is reloaded.
fn reload(app: App&) -> bool {
    if app.client.busy || (app.dirty && !app.blocked) || app.path.len == 0 { return false; }
    let loaded = app_api_snapshot::load(app.path);
    if app.dirty {
        app.blocked = loaded.code != lab_json_file::OK && loaded.code != lab_json_file::MISSING;
        acknowledge(app, if loaded.code == lab_json_file::OK { loaded.revision } else { lab_fs_files::revision(app.path) });
        app.disk_notice = if app.blocked { str(app_api_snapshot::message(loaded.code), " · File left untouched") }
            else { "File checked · Current records kept · Save before reloading" }; return false;
    }
    if loaded.code == lab_json_file::OK { apply_snapshot(app, loaded); return true; }
    app.blocked = loaded.code != lab_json_file::MISSING;
    acknowledge(app, lab_fs_files::revision(app.path));
    app.disk_notice = str(app_api_snapshot::message(loaded.code), if app.blocked { " · File left untouched" } else { " · Save to keep this collection" }); false
}
fn save(app: App&) -> bool {
    if app.client.busy || app.blocked || app.external || app.path.len == 0 || app.feed.code != app_api_feed::OK { return false; }
    check_disk(app); if app.external { return false; }
    let snapshot = app_api_snapshot::Snapshot { feed: app.feed, url: url(app).text, query: query(app).text,
        source: app.source, selected: app.selected, changed: app.changed };
    let saved = app_api_snapshot::write(app.path, snapshot); let code = saved.code;
    if code == lab_json_file::OK { acknowledge(app, saved.revision); app.dirty = false; app.disk_notice = "Snapshot saved · Ready for next launch"; return true; }
    app.disk_notice = str(app_api_snapshot::message(code), " · Records kept · Try Save again"); false
}
fn poll(app: App&) {
    loop {
        let result, available = qpoll<app_api_client::Completed>(); if !available { break; }
        if app_api_client::accept(app.client, result) && !app.client.cancelled {
            adopt(app, result.feed); app.source = result.url;
            let label: u8[>..] = if result.code == lab_net_http::OK { str("HTTP ", result.status, " · ", result.body.len, " bytes · Original response") }
                else { str("Partial response · ", result.body.len, " bytes · Transport failed") };
            response(app, result.body, label);
        }
    }
}
// Join before destroying the view or HTTP runtime. Explicit finite captures may
// finish a request; user shutdown requests cancellation and retains the model.
fn join(app: App&, worker: i64, finish_pending: bool = false) {
    app.monitor_stopped = true; lab_fs_watch::close(app.monitor);
    if !finish_pending { app_api_client::cancel(app.client); }
    qput(app_api_client::Job { stop: true }); thread_wait(worker); poll(app);
}
fn status(app: const App&) -> u8[>..] {
    if app.client.cancelling { return str("Cancelling…   Keeping the current records."); }
    if app.client.busy { return str("Loading…   You can keep browsing the current records."); }
    if app.client.start_failed { return str("Unable to create a request. Try Fetch again."); }
    if app.client.cancelled { return str("Cancelled   ·   Current records kept   ·   Fetch to try again"); }
    if app.copy_failed { return str("Unable to copy JSON to the clipboard. Try Copy JSON again."); }
    if app.feed.code != app_api_feed::OK { return str(app.feed.error); }
    if app.client.status > 0 { return str("HTTP ", app.client.status, "   ·   ", app.feed.items.len, " records   ·   ", app.client.elapsed_ms, " ms", if app.changed { "   ·   Local changes" } else { "" }); }
    str(if app.restored { "Local snapshot" } else { "Offline example" }, "   ·   ", app.feed.items.len, " records", if app.changed { "   ·   Local changes" } else { "" })
}
fn commands(app: App&) -> lab_ui_command::Catalog<Action> {
    var c = lab_ui_command::Catalog<Action> {}; let busy = app.client.busy;
    assert(lab_ui_command::add(c, 1, "Fetch URL", Action.Fetch, "Fetch records and inspect the original response", "http request network", "Return", lab_ui_input_shortcuts::primary(), !busy && trim(url(app).text).len > 0, if busy { "A request is already running" } else { "Enter a URL first" }));
    assert(lab_ui_command::add(c, 2, "Cancel request", Action.Cancel, "Keep the current records and stop the worker", "http network", "", 0, busy && !app.client.cancelling, if app.client.cancelling { "Cancellation in progress" } else { "No request is running" }));
    assert(lab_ui_command::add(c, 3, "Load offline example", Action.Example, "Replace the collection with example records", "demo reset", "", 0, !busy, "A request is running"));
    assert(lab_ui_command::add(c, 4, "Save snapshot", Action.Save, "Save records, URL, filter and selection", "file disk persist", "S", lab_ui_input_shortcuts::primary(), !busy && !app.blocked && !app.external && app.path.len > 0 && app.feed.code == app_api_feed::OK,
        if busy { "A request is running" } else if app.path.len == 0 { "No snapshot path configured" } else if app.external { "Review the external snapshot change first" } else if app.blocked { "Check the snapshot file before saving" } else { "No valid collection to save" }));
    assert(lab_ui_command::add(c, 5, if app.dirty && app.blocked { "Check snapshot file" } else { "Reload snapshot" }, Action.Reload, "Read the saved collection or check a repaired file", "file disk restore", "R", lab_ui_input_shortcuts::primary(),
        !busy && app.path.len > 0 && (!app.dirty || app.blocked), if busy { "A request is running" } else if app.path.len == 0 { "No snapshot path configured" } else { "Save unsaved records before reloading" }));
    assert(lab_ui_command::add(c, 6, "Show record", Action.Record, "Return to record details", "tab view collection", "1", lab_ui_input_shortcuts::primary(), app.show_response, "Already showing record details"));
    assert(lab_ui_command::add(c, 7, "Show response", Action.Response, "Inspect the original HTTP body", "tab view raw json", "2", lab_ui_input_shortcuts::primary(), !app.show_response, "Already showing the response"));
    assert(lab_ui_command::add(c, 8, "Find in response", Action.FindText, "Search the response text", "text search", "F", lab_ui_input_shortcuts::primary(), app.show_response && app.document.code == lab_ui_views_text::OK, "Open the Response tab first"));
    assert(lab_ui_command::add(c, 9, "Copy JSON", Action.Export, "Encode the current records to the clipboard", "export collection", "C", lab_ui_input_shortcuts::primary() | gfx::MOD_SHIFT, !busy && app.feed.code == app_api_feed::OK, if busy { "A request is running" } else { "No valid collection to copy" }));
    assert(lab_ui_command::add(c, 10, "Copy response", Action.CopyResponse, "Copy the original response bytes", "clipboard http raw", "", 0, app.show_response && app.document.code == lab_ui_views_text::OK, "Open the Response tab first"));
    assert(lab_ui_command::add(c, 11, "Toggle completion", Action.Toggle, "Change the selected record's completion state", "complete active task", "", 0, !busy && app_api_feed::index(app.feed, app.selected) >= 0, if busy { "A request is running" } else { "Select a record first" }));
    assert(lab_ui_command::add(c, 12, "Next search match", Action.TextNext, "Move through response search results", "find text", "F3", 0, app.show_response && app.text.matches.len > 0, "Search the response first"));
    assert(lab_ui_command::add(c, 13, "Previous search match", Action.TextPrevious, "Move through response search results", "find text", "F3", gfx::MOD_SHIFT, app.show_response && app.text.matches.len > 0, "Search the response first"));
    assert(lab_ui_command::add(c, 14, "Review external snapshot", Action.DiskReview, "Choose between the saved file and current records", "conflict disk local reload", "", 0, app.external && !busy, if busy { "A request is running" } else { "No external change to review" })); c
}
fn build(app: App&, width: f32, height: f32) {
    let theme = lab_ui_controls_components::Theme {}; let ids = visible(app); let wide = width >= 900.0;
    var selected_index: i64 = -1; for i in ids.len { if ids[i] == app.selected { selected_index = i; } }
    let selected = app_api_feed::index(app.feed, app.selected);
    lab_ui_view::begin(app.view, width, height);
    let catalog = commands(app); lab_ui_overlays_palette::bindings(app.view, catalog);
    lab_ui_view::shortcut(app.view, "K", lab_ui_input_shortcuts::primary(), Action.Commands);
    if app.show_response && app.text.find_open { lab_ui_view::shortcut(app.view, "Escape", 0, Action.TextClose); }
    lab_ui_view::box(app.view, "root", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), padding: lab_ui_layout_engine::padding(22), gap: 12 }) {
        lab_ui_view::label(app.view, "kicker", "GOOSE   /   API BROWSER", lab_ui_layout_engine::Config { height: lab_ui_layout_engine::fixed(18.0), width: lab_ui_layout_engine::grow() }, 2, theme.muted);
        lab_ui_view::label(app.view, "heading", "From a response to a collection.", lab_ui_layout_engine::Config { height: lab_ui_layout_engine::fixed(38.0), width: lab_ui_layout_engine::grow() }, 1);
        lab_ui_view::box(app.view, "request", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, height: lab_ui_layout_engine::fixed(44.0), width: lab_ui_layout_engine::grow(), gap: 8 }) {
            lab_ui_view::field(app.view, "url", 1, Action.Fetch, "Paste a JSON endpoint…", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, true, 512);
            if app.client.busy {
                // Separate identity prevents a pending Cancel release activating Fetch.
                lab_ui_view::button(app.view, "cancel", 8, Action.Cancel, if app.client.cancelling { "Stopping…" } else { "Cancel" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(100.0), height: lab_ui_layout_engine::grow() }, true, !app.client.cancelling);
            } else {
                lab_ui_view::button(app.view, "fetch", 2, Action.Fetch, "Fetch", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(100.0), height: lab_ui_layout_engine::grow() }, true, url(app).text.len > 0);
            }
            lab_ui_view::button(app.view, "example", 3, Action.Example, "Example", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(100.0), height: lab_ui_layout_engine::grow() }, false, !app.client.busy);
        };
        lab_ui_view::label(app.view, "status", status(app), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) }, 2,
            if app.feed.code == app_api_feed::OK || app.client.busy { theme.muted } else { float4 { 1.0, 0.43, 0.43, 1.0 } });
        lab_ui_view::box(app.view, "tools", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, height: lab_ui_layout_engine::fixed(40.0), width: lab_ui_layout_engine::grow(), gap: 10 }) {
            lab_ui_view::field(app.view, "search", 4, Action.Search, "Search records…", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
            lab_ui_view::button(app.view, "export", 5, Action.Export, if app.copied { "JSON copied" } else { "Copy JSON" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(144.0), height: lab_ui_layout_engine::grow() }, false, app.feed.code == app_api_feed::OK && !app.client.busy);
            if app.path.len > 0 {
                lab_ui_view::button(app.view, "save", 9, Action.Save, "Save", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(80.0), height: lab_ui_layout_engine::grow() }, false, !app.client.busy && !app.blocked && !app.external && app.feed.code == app_api_feed::OK);
                lab_ui_view::button(app.view, "reload", 10, Action.Reload, if app.blocked && app.dirty { "Check file" } else { "Reload" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(96.0), height: lab_ui_layout_engine::grow() }, false, !app.client.busy && (!app.dirty || app.blocked));
            }
        };
        if app.external {
            lab_ui_view::box(app.view, "disk-change", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, height: lab_ui_layout_engine::fixed(32.0), width: lab_ui_layout_engine::grow(), gap: 8 }) {
                lab_ui_view::label(app.view, "disk-change-notice", "Saved file changed externally · Current records kept", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, 2, theme.muted);
                lab_ui_view::button(app.view, "disk-review", 32, Action.DiskReview, "Review", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(80.0), height: lab_ui_layout_engine::grow() }, false, !app.client.busy);
            };
        }
        lab_ui_view::box(app.view, "workspace", lab_ui_layout_engine::Config { direction: if wide { lab_ui_layout_engine::ROW } else { lab_ui_layout_engine::COLUMN }, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), gap: 14 }) {
            lab_ui_view::leaf(app.view, "records", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
            lab_ui_view::box(app.view, "details", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), padding: lab_ui_layout_engine::padding(20), gap: 12 }) {
                lab_ui_view::decoration(app.view, "details");
                lab_ui_view::box(app.view, "detail-tabs", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
                    lab_ui_view::button(app.view, "record-tab", 11, Action.Record, "Record", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(84.0), height: lab_ui_layout_engine::grow() }, !app.show_response);
                    lab_ui_view::button(app.view, "response-tab", 12, Action.Response, "Response", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(100.0), height: lab_ui_layout_engine::grow() }, app.show_response);
                    lab_ui_view::button(app.view, "commands", 30, Action.Commands, "Commands", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(100.0), height: lab_ui_layout_engine::grow() });
                };
                if app.show_response {
                    lab_ui_view::label(app.view, "response-label", if app.text.copy_failed { "Unable to copy · Try again" } else { app.response_label[..] }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) }, 2, theme.muted);
                    lab_ui_view::box(app.view, "response-tools", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
                        lab_ui_view::button(app.view, "find", 13, Action.FindText, "Find", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(62.0), height: lab_ui_layout_engine::grow() }, false, app.document.code == lab_ui_views_text::OK);
                        lab_ui_view::button(app.view, "copy-response", 14, Action.CopyResponse, if app.response_copied { "Copied" } else { "Copy response" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(144.0), height: lab_ui_layout_engine::grow() }, false, app.document.code == lab_ui_views_text::OK);
                    };
                    lab_ui_views_text::find_bar(app.view, app.text, "text-find", find_config());
                    lab_ui_view::leaf(app.view, "response-body", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
                } else if selected >= 0 {
                    let item = app.feed.items[selected];
                    lab_ui_view::paragraph(app.view, "detail-title", item.title, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit() }, theme.text);
                    lab_ui_view::label(app.view, "detail-id", str("ID ", item.id, "   ·   ", if item.completed { "Completed" } else { "Active" }), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0) }, 2, theme.muted);
                    lab_ui_view::leaf(app.view, "detail-body", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
                    lab_ui_view::button(app.view, "toggle", 6, Action.Toggle, if item.completed { "Mark active" } else { "Mark complete" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(40.0) }, false, !app.client.busy);
                } else {
                    lab_ui_view::paragraph(app.view, "detail-empty", "Choose a record from the list. Fetch again to recover from an error, or load the offline example.", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit() });
                }
            };
        };
        lab_ui_view::label(app.view, "footer", str(ids.len, " shown   ·   ", if app.disk_notice.len > 0 { app.disk_notice[..] } else if app.path.len > 0 && app.monitor.id == 0 && app.monitor.code != lab_fs_watch::CLOSED { "File watch unavailable · Save checks the file" } else if app.dirty && app.path.len > 0 { "Unsaved records · Save before reloading" } else { "Arrows to select · Changes stay local" }), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(20.0) }, 2, theme.muted);
    };
    lab_ui_view::solve(app.view);
    if app.show_response {
        lab_ui_views_text::at_view(app.view, lab_ui_view::bounds(app.view, "response-body"), text_config(), app.text, app.document);
    } else if selected >= 0 {
        let area = lab_ui_view::bounds(app.view, "detail-body"); let item = app.feed.items[selected];
        let body: const u8[:] = if item.body.len > 0 { item.body[..] } else { "No description was supplied by the API." };
        assert(lab_ui_layout_engine::begin(app.detail_layout, max(1.0, area.w - 16.0), 100000.0));
        lab_ui_layout_engine::box(app.detail_layout, "body", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit() }) { assert(lab_ui_layout_engine::text(app.detail_layout, body, lab_ui_layout_engine::WRAP_JAPANESE)); };
        assert(lab_ui_layout_engine::finish(app.detail_layout));
        let measured, found = lab_ui_layout_engine::bounds(app.detail_layout, "body"); assert(found);
        lab_ui_view::at_scroll_viewport(app.view, area, 2, measured.h) {
            lab_ui_view::at_paragraph(app.view, "body-text", area, app.detail_layout);
        };
    }
    let area = lab_ui_view::bounds(app.view, "records");
    lab_ui_view::at_decoration(app.view, "records-card", area);
    if ids.len == 0 {
        lab_ui_view::at_label(app.view, "empty", lab_ui_geometry::rect(area.x + 20.0, area.y + 24.0, area.w - 40.0, 32.0), if app.feed.code != app_api_feed::OK { "No records loaded" } else { "No matching records" }, 0, theme.muted);
    }
    let list = lab_ui_geometry::rect(area.x + 8.0, area.y + 8.0, max(0.0, area.w - 16.0), max(0.0, area.h - 16.0));
    lab_ui_view::at_list(app.view, list, lab_ui_view::ListConfig<Action> { id: 7, scroll_id: 1, count: ids.len, stride: 68.0, selected: selected_index, action: Action.Select }) {
        let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(app.view, 1), list.h, 68.0, ids.len);
        for i in range.end - range.first {
            let index = range.first + i; let item = app.feed.items[app_api_feed::index(app.feed, ids[index])];
            let row = lab_ui_geometry::rect(list.x + 4.0, list.y + index * 68.0 + 3.0, max(0.0, list.w - 22.0), 62.0);
            lab_ui_view::at_list_item(app.view, str("record-", index), (1000 + index) as u64, index, row);
            lab_ui_view::at_label(app.view, str("record-title-", index), lab_ui_geometry::rect(row.x + 12.0, row.y + 7.0, row.w - 24.0, 24.0), item.title, 0);
            lab_ui_view::at_label(app.view, str("record-state-", index), lab_ui_geometry::rect(row.x + 12.0, row.y + 34.0, row.w - 24.0, 20.0), str("#", item.id, "   ·   ", if item.completed { "Completed" } else { "Active" }), 2, theme.muted);
        }
    };
    lab_ui_overlays_palette::show(app.view, app.palette, palette_config(), catalog); disk_dialog(app);
}
fn action(app: App&, event: lab_ui_view::Event<Action>) -> bool {
    if event.action == Action.DiskDismiss && lab_ui_overlays_modal::backdrop(event) { lab_ui_overlays_modal::close(app.view, app.disk_dialog); return true; }
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
    if text_action && app.show_response {
        return lab_ui_views_text::handle(app.view, app.canvas, app.text, app.document, app.response, lab_ui_view::bounds(app.view, "response-body"), text_config(), find_config(), command, event);
    }
    if event.action == Action.Search && event.kind == lab_ui_view::CHANGE {
        let ids = visible(app); var found = false; for id in ids { if id == app.selected { found = true; } }
        if !found { app.selected = if ids.len > 0 { ids[0] } else { -1 }; }
        lab_ui_view::scroll_state(app.view, 1).offset = 0.0; return true;
    }
    if event.action == Action.Select && (event.kind == lab_ui_view::SELECT || event.kind == lab_ui_view::ACTIVATE) {
        let ids = visible(app); if event.index >= 0 && event.index < ids.len { app.selected = ids[event.index]; lab_ui_view::scroll_state(app.view, 2).offset = 0.0; } return true;
    }
    if event.kind != lab_ui_view::ACTIVATE && event.kind != lab_ui_view::SUBMIT { return false; }
    match event.action {
        DiskReview => { review_disk(app); },
        DiskDismiss => { lab_ui_overlays_modal::close(app.view, app.disk_dialog); },
        DiskLoad => { if app.disk_dialog.opened && app.external && !app.client.busy {
            let loaded = app_api_snapshot::load(app.path);
            if loaded.code == lab_json_file::OK { apply_snapshot(app, loaded); }
            else { app.disk_valid = false; app.disk_local_ok = loaded.code == lab_json_file::MISSING; app.disk_notice = str(app_api_snapshot::message(loaded.code), " · Current records kept"); }
        } },
        DiskLocal => { if app.disk_dialog.opened && app.external && !app.client.busy {
            let loaded = app_api_snapshot::load(app.path); let current = if loaded.code == lab_json_file::OK { loaded.revision } else { lab_fs_files::revision(app.path) };
            if current != app.observed { app.observed = current; app.disk_notice = "File changed again · Review the current version"; app.disk_valid = loaded.code == lab_json_file::OK; app.disk_local_ok = app.disk_valid || loaded.code == lab_json_file::MISSING; }
            else if loaded.code == lab_json_file::OK || loaded.code == lab_json_file::MISSING { acknowledge(app, current); app.blocked = false; app.dirty = true; app.disk_notice = "Local records kept · Save to replace the changed file"; }
            else { app.disk_local_ok = false; app.disk_valid = false; app.disk_notice = str(app_api_snapshot::message(loaded.code), " · Current records kept"); }
        } },
        Fetch => { if app_api_client::start(app.client, trim(url(app).text)) { app.copied = false; app.copy_failed = false; } },
        Cancel => { app_api_client::cancel(app.client); },
        Example => { if !app.client.busy { let feed = app_api_feed::example(); adopt(app, feed); encoded_response(app, "Example JSON · Generated from the offline records"); app.client.status = 0; app.client.cancelled = false; app.client.start_failed = false; app.source = "Offline example"; app.restored = false; } },
        Toggle => { let i = app_api_feed::index(app.feed, app.selected); if i >= 0 && !app.client.busy { app.feed.items[i].completed = !app.feed.items[i].completed; app.changed = true; app.dirty = true; app.disk_notice = []; app.copied = false; app.copy_failed = false; } },
        Export => { if !app.client.busy && app.feed.code == app_api_feed::OK {
            let encoded, ok = app_api_feed::encode(app.feed);
            // Clipboard copies the owned output before the temporary writer expires.
            app.copied = ok && gfx::set_clipboard(encoded); app.copy_failed = !app.copied;
        } },
        Save => { save(app); }, Reload => { reload(app); },
        Record => { app.show_response = false; }, Response => { app.show_response = true; app.view.input.focused = 15; },
        CopyResponse => { app.response_copied = gfx::set_clipboard(app.response); app.text.copy_failed = !app.response_copied; },
        Commands => {}, CommandQuery => {}, CommandChoose => {}, CommandDismiss => {},
        None => {}, Search => {}, Select => {}, TextInput => {}, FindText => {}, TextQuery => {}, TextPrevious => {}, TextNext => {}, TextClose => {},
    } true
}
fn frame(app: App&) {
    poll(app); observe(app); let size = gfx::screen_size(); let w: f32 = size.x / app.scale; let h: f32 = size.y / app.scale;
    lab_ui_render_scene::begin(app.canvas, w, h);
    fn describe() { build(app, w, h); }
    fn reduce(event: lab_ui_view::Event<Action>) -> bool { action(app, event) }
    lab_ui_view::frame(app.view, app.canvas, gfx::events(), gfx::mouse_pos(), gfx::focused(), app.scale, describe, reduce);
    if app.show_response {
        fn row_color(index: i64, bounds: lab_ui_geometry::Rect) -> float4 { lab_ui_controls_components::Theme {}.text }
        lab_ui_views_text::paint(app.canvas, app.text, app.document, app.response, lab_ui_view::bounds(app.view, "response-body"), text_config(), lab_ui_view::scroll_state(app.view, 3).offset, app.view.input.focused == 15, row_color);
    }
    lab_ui_view::paint_overlays(app.view, app.canvas);
    lab_ui_render_scene::render(app.canvas, lab_ui_controls_components::Theme {}.background);
}
fn text_command(a: Action) -> lab_ui_views_text::Command, bool {
    match a {
        TextInput => { return lab_ui_views_text::Command.Input, true; }, FindText => { return lab_ui_views_text::Command.Find, true; },
        TextQuery => { return lab_ui_views_text::Command.Query, true; }, TextPrevious => { return lab_ui_views_text::Command.Previous, true; },
        TextNext => { return lab_ui_views_text::Command.Next, true; }, TextClose => { return lab_ui_views_text::Command.Close, true; },
        _ => { return lab_ui_views_text::Command.Input, false; }
    }
}
