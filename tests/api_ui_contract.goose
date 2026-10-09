import std;
import os;
import gfx;
import lab.net.http;
import lab.io.cancel;
import lab.ui.layout.engine;
import lab.text.utf8;
import lab.text.line_break;
import lab.ui.render.font;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.ui.geometry;
import lab.ui.view;
import lab.json.codec;
import api_browser.feed;
import api_browser.client;
import api_browser.browser;
import api_browser.snapshot;
import lab.json.file;
import lab.ui.views.text;
import lab.fs.watch;
import lab.fs.files;
fn tick(app: app_api_browser::App&) { assert(gfx::frame()); app_api_browser::frame(app); }
fn click(app: app_api_browser::App&, name: const u8[:]) {
    let r = lab_ui_view::bounds(app.view, name); let x = (r.x + r.w / 2.0) * app.scale; let y = (r.y + r.h / 2.0) * app.scale;
    gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, true); gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, false); tick(app);
}
fn key(app: app_api_browser::App&, name: const u8[:]) { assert(gfx::inject_key(name, true)); assert(gfx::inject_key(name, false)); tick(app); }
fn modified_key(app: app_api_browser::App&, modifier: const u8[:], name: const u8[:]) {
    assert(gfx::inject_key(modifier, true)); assert(gfx::inject_key(name, true)); assert(gfx::inject_key(name, false)); assert(gfx::inject_key(modifier, false)); tick(app);
}
fn fetch(app: app_api_browser::App&, base: const u8[:], path: const u8[:]) {
    lab_ui_controls_field::set(app_api_browser::url(app), str(base, path)); tick(app); click(app, "fetch"); assert(app.client.busy);
}
fn wait(app: app_api_browser::App&) {
    let deadline = clock_ns() + 10000000000;
    while app.client.busy { assert(clock_ns() < deadline); sleep_ms(2); tick(app); }
}
fn node(app: const app_api_browser::App&, name: const u8[:]) -> lab_ui_view::Node<app_api_browser::Action> {
    for n in app.view.nodes { if n.name == name { return n; } } assert(false); default<lab_ui_view::Node<app_api_browser::Action>>()
}
fn click_node(app: app_api_browser::App&, name: const u8[:]) {
    let r = node(app, name).rect;
    gfx::inject_mouse((r.x + 8.0) * app.scale, (r.y + r.h / 2.0) * app.scale, gfx::MOUSE_LEFT, true);
    gfx::inject_mouse((r.x + 8.0) * app.scale, (r.y + r.h / 2.0) * app.scale, gfx::MOUSE_LEFT, false); tick(app);
}
fn wait_external(app: app_api_browser::App&, expected: bool) {
    let until = clock_ns() + 3000000000;
    while app.external != expected || app.changes.pending { assert(clock_ns() < until); sleep_ms(2); tick(app); }
}
fn frames_for(app: app_api_browser::App&, duration: i64) {
    let until = clock_ns() + duration; while clock_ns() < until { sleep_ms(2); tick(app); }
}
fn main() {
    let argv = args(); assert(argv.len == 5); var scale: f32 = 1.0;
    if argv.len == 5 { let value, ok = parse_flt(argv[3]); assert(ok); scale = value as f32; }
    assert(lab_net_http::init() == lab_net_http::OK); assert(gfx::open_headless((1180.0 * scale) as i64, (820.0 * scale) as i64));
    var app = app_api_browser::create(lab_ui_render_font::default_font(), scale, argv[4]); let worker = thread_spawn(app_api_client::worker); tick(app);
    assert(app.feed.items.len == 5);
    click(app, "search"); modified_key(app, "Left Ctrl", "K");
    assert(app.palette.modal.opened && app.view.input.focused == 100002);
    assert(gfx::screenshot(str(argv[2], ".commands.png")));
    assert(gfx::inject_text("show response")); tick(app); key(app, "Return");
    assert(app.show_response && app.view.input.focused == 15 && !app.palette.modal.opened);
    modified_key(app, "Left Ctrl", "K"); assert(gfx::inject_text("record")); tick(app);
    key(app, "Down"); key(app, "Up"); key(app, "Return"); assert(!app.show_response && !app.palette.modal.opened);
    // Search text stays in the palette; cancellation restores the original field.
    click(app, "search"); modified_key(app, "Left Ctrl", "K"); assert(gfx::inject_text("no such command")); tick(app);
    key(app, "Return"); assert(app.palette.modal.opened && app_api_browser::query(app).text.len == 0);
    assert(gfx::screenshot(str(argv[2], ".commands-empty.png")));
    key(app, "Escape"); assert(app.view.input.focused == 4 && !app.palette.modal.opened);
    // Multilingual search, caret placement, selection and export use the family.
    click(app, "search"); assert(gfx::inject_text("日本語")); tick(app);
    assert(app_api_browser::visible(app).len == 1 && app.selected == 2);
    let points = lab_ui_controls_field::stops(app.canvas.fonts[0].font, app_api_browser::query(app).text);
    assert(points.len == 4 && points[1].byte == 3 && points[2].byte == 6 && points[3].byte == 9);
    key(app, "Left"); assert(app_api_browser::query(app).cursor == 6);
    key(app, "End");
    var saw_url = false;
    let area = lab_ui_view::bounds(app.view, "detail-body");
    for i in lab_ui_layout_engine::line_count(app.detail_layout) {
        let line = lab_ui_layout_engine::line(app.detail_layout, i); assert(lab_text_utf8::valid(line.text));
        assert(line.bounds.w <= area.w - 16.0 + 0.05);
        if line.text.len > 0 {
            let cp, next, ok = lab_text_utf8::decode(line.text, 0); assert(ok && lab_text_line_break::can_start(cp));
            var at = 0; var last: i64 = 0;
            while at < line.text.len { let cp, next, ok = lab_text_utf8::decode(line.text, at); assert(ok); last = cp; at = next; }
            assert(lab_text_line_break::can_end(last));
        }
        if lab_text_strings::contains_folded(line.text, "https://") { saw_url = true; }
    }
    assert(saw_url);
    click(app, "toggle"); click(app, "export"); assert(app.copied);
    let multilingual = app_api_feed::decode(gfx::clipboard()); assert(multilingual.items[1].title == app.feed.items[1].title && multilingual.items[1].completed);
    assert(gfx::screenshot(str(argv[2], ".multilingual.png")));
    lab_ui_controls_field::set(app_api_browser::query(app), ""); tick(app);
    lab_ui_controls_field::set(app_api_browser::url(app), str(argv[1], "/slow")); tick(app);
    modified_key(app, "Left Ctrl", "K"); assert(gfx::inject_text("fetch")); tick(app); key(app, "Return"); assert(app.client.busy && !app.palette.modal.opened);
    modified_key(app, "Left Ctrl", "K"); assert(gfx::inject_text("fetch")); tick(app); key(app, "Return"); assert(app.client.busy && app.palette.modal.opened);
    assert(gfx::screenshot(str(argv[2], ".commands-busy.png")));
    // Ctrl+R belongs to the background and must not restore a disk snapshot.
    modified_key(app, "Left Ctrl", "R"); assert(app.client.busy && app.palette.modal.opened);
    key(app, "Escape");
    // Input and rendering progress while the worker is waiting for HTTP.
    click(app, "search"); assert(gfx::inject_text("Unicode")); tick(app);
    assert(app.client.busy && app_api_browser::visible(app).len == 1 && app.selected == 2);
    lab_ui_controls_field::set(app_api_browser::query(app), ""); tick(app); wait(app);
    assert(app.client.status == 200 && app.feed.code == app_api_feed::OK && app.feed.items.len == 40);
    assert(app.feed.items[0].id == 9007199254740993 && app.feed.items[0].title == "Inspect café data 🚀");
    // Original HTTP bytes remain available independently of record/local edits.
    click(app, "response-tab"); assert(app.show_response && app.document.code == lab_ui_views_text::OK);
    assert(starts_with(app.response, "{\"items\":") && lab_text_strings::contains_folded(app.response, "café"));
    click(app, "response-body"); modified_key(app, "Left Ctrl", "A"); modified_key(app, "Left Ctrl", "C");
    assert(gfx::clipboard() == app.response);
    modified_key(app, "Left Ctrl", "F"); assert(app.text.find_open && app.view.input.focused == 20);
    assert(gfx::inject_text("café")); tick(app); assert(app.text.matches.len == 1);
    key(app, "Escape"); assert(!app.text.find_open); modified_key(app, "Left Ctrl", "C"); assert(gfx::clipboard() == "café");
    modified_key(app, "Left Ctrl", "F"); modified_key(app, "Left Ctrl", "A");
    assert(gfx::inject_text("record 40")); tick(app);
    assert(app.text.matches.len == 1 && app.text.horizontal.offset > 0.0);
    assert(gfx::screenshot(str(argv[2], ".response.png"))); key(app, "Escape");
    let original_response = copy(app.response); click(app, "record-tab");
    // Keyboard selection crosses virtualized rows and reveals the final row.
    let list = lab_ui_view::bounds(app.view, "records");
    gfx::inject_mouse((list.x + 30.0) * scale, (list.y + 25.0) * scale, gfx::MOUSE_LEFT, true);
    gfx::inject_mouse((list.x + 30.0) * scale, (list.y + 25.0) * scale, gfx::MOUSE_LEFT, false); tick(app);
    key(app, "End"); assert(app.selected == 40 && lab_ui_view::scroll_state(app.view, 1).offset > 0.0);
    click(app, "search"); assert(gfx::inject_text("CAF")); tick(app);
    assert(app_api_browser::visible(app).len == 1 && app.selected == 9007199254740993);
    // A long body scrolls independently, leaving the toggle reachable.
    let body = lab_ui_view::bounds(app.view, "detail-body");
    gfx::inject_mouse((body.x + 20.0) * scale, (body.y + 20.0) * scale, 0, false);
    assert(gfx::inject_wheel(0.0, -3.0)); tick(app); assert(lab_ui_view::scroll_state(app.view, 2).offset > 0.0);
    click(app, "toggle"); assert(app.changed && app.feed.items[0].completed);
    assert(app.response == original_response);
    click(app, "export"); assert(app.copied); let exported = gfx::clipboard(); let roundtrip = app_api_feed::decode(exported);
    assert(roundtrip.code == app_api_feed::OK && roundtrip.items.len == 40 && roundtrip.items[0].completed && roundtrip.items[0].id == 9007199254740993);
    assert(gfx::screenshot(argv[2]));
    // Save via actual UI events; Reload cannot discard an unsaved completion edit.
    assert(app.dirty); let edited = copy(app.feed); click(app, "reload"); assert(app.feed == edited && app.dirty);
    modified_key(app, "Left Ctrl", "K"); assert(gfx::inject_text("save snapshot")); tick(app); key(app, "Return");
    assert(!app.palette.modal.opened && !app.dirty && !app.blocked);
    let disk = lab_json_file::load(argv[4], lab_json_file::MAX_BYTES); assert(disk.code == lab_json_file::OK);
    let snapshot = app_api_snapshot::decode(disk.data); assert(snapshot.code == lab_json_file::OK);
    assert(snapshot.snapshot.feed == app.feed && snapshot.snapshot.query == "CAF" && snapshot.snapshot.changed);
    lab_ui_controls_field::set(app_api_browser::query(app), ""); tick(app); click(app, "reload");
    assert(app.restored && app.changed && app_api_browser::query(app).text == "CAF" && app.selected == 9007199254740993);
    // A write failure preserves both the records and the existing good snapshot.
    app.path = str(argv[4], "/missing/snapshot.json"); click(app, "toggle"); let unsaved = copy(app.feed);
    click(app, "save"); assert(app.dirty && app.feed == unsaved && app.disk_notice.len > 0);
    let retained = lab_json_file::load(argv[4], lab_json_file::MAX_BYTES); assert(retained.data == disk.data);
    app.path = argv[4]; click(app, "toggle"); click(app, "save"); assert(!app.dirty && app.feed.items[0].completed);
    // The bounded native file bridge accepts valid JSON beyond 64 KiB.
    var text: u8[>..] = []; for i in 70000 { text.push('x'); }
    var writer = lab_json_codec::Writer { limit: 80000 }; lab_json_codec::write_string(writer, text);
    let large_json, large_ok = lab_json_codec::finish(writer); assert(large_ok);
    let large_path = str(argv[4], ".large"); assert(lab_json_file::save(large_path, large_json) == lab_json_file::OK);
    let large_file = lab_json_file::load(large_path); assert(large_file.code == lab_json_file::OK && large_file.data == large_json);
    let limited = lab_json_file::load(large_path, 65536); assert(limited.code == lab_json_file::LIMIT && limited.data.len == 0);
    assert(lab_json_file::save(large_path, "[]", 0) == lab_json_file::LIMIT);
    let still_large = lab_json_file::load(large_path); assert(still_large.data == large_json);
    // Invalid JSON cannot replace a good file. Invalid loads cannot replace the model.
    assert(lab_json_file::save(argv[4], "{broken") == lab_json_file::INVALID_JSON);
    let good = lab_json_file::load(argv[4], lab_json_file::MAX_BYTES);
    assert(write_file_atomic(argv[4], "{broken")); let current = copy(app.feed); click(app, "reload");
    assert(app.blocked && app.feed == current); click(app, "save");
    var rejected: u8[>..] = []; assert(read_file(argv[4], rejected) && rejected == "{broken");
    click(app, "toggle"); assert(app.dirty && app.blocked); let blocked_edits = copy(app.feed);
    assert(write_file_atomic(argv[4], good.data)); click(app, "reload");
    assert(!app.blocked && app.dirty && app.feed == blocked_edits); // Check file retains edits.
    click(app, "toggle"); click(app, "save"); assert(!app.dirty && app.feed == current);
    click(app, "reload"); assert(!app.blocked && app.feed == current);
    assert(gfx::screenshot(str(argv[2], ".saved.png")));
    assert(app.monitor.id != 0 && app.monitor.code == lab_fs_watch::OK);
    let original_snapshot = app_api_snapshot::load(argv[4]); assert(original_snapshot.code == 0);
    click(app, "toggle"); let local_records = copy(app.feed); let local_selection = app.selected;
    var external_snapshot = copy(original_snapshot.snapshot); external_snapshot.feed.items[1].title = "Externally edited record 02";
    let external_bytes, external_ok = app_api_snapshot::encode(external_snapshot); assert(external_ok && write_file_atomic(argv[4], external_bytes));
    wait_external(app, true);
    assert(app.dirty && app.feed == local_records && app.selected == local_selection && app_api_browser::query(app).text == "CAF");
    assert(!node(app, "save").enabled && !app_api_browser::save(app));
    assert(lab_json_file::load(argv[4]).data == external_bytes);
    assert(gfx::screenshot(str(argv[2], ".external-change.png")));
    click(app, "disk-review"); assert(app.disk_dialog.opened && app.view.input.focused == 200005);
    assert(gfx::screenshot(str(argv[2], ".external-review.png")));
    // Background shortcuts cannot save over the file from inside the dialog.
    modified_key(app, "Left Ctrl", "S"); assert(app.disk_dialog.opened && lab_json_file::load(argv[4]).data == external_bytes);
    key(app, "Escape"); assert(!app.disk_dialog.opened && app.external && app.feed == local_records && app.view.input.focused == 32);
    click(app, "disk-review"); click_node(app, "disk-load");
    assert(!app.disk_dialog.opened && !app.external && !app.dirty && app.feed == external_snapshot.feed);
    // Invalid external data never becomes either the model or an acknowledged
    // overwrite target. Repair updates the still-open dialog's availability.
    click(app, "toggle"); let retained_edits = copy(app.feed);
    assert(write_file_atomic(argv[4], "{broken")); wait_external(app, true); click(app, "disk-review");
    assert(!node(app, "disk-load").enabled && !node(app, "disk-local").enabled && app.feed == retained_edits);
    external_snapshot.feed.items[1].title = "Repaired external record 02";
    let repaired_bytes, repaired_ok = app_api_snapshot::encode(external_snapshot); assert(repaired_ok && write_file_atomic(argv[4], repaired_bytes));
    frames_for(app, 350000000); assert(node(app, "disk-load").enabled && node(app, "disk-local").enabled && app.feed == retained_edits);
    click_node(app, "disk-local"); assert(app.disk_dialog.opened && app.external); // Changed since opening: review again.
    click_node(app, "disk-local"); assert(!app.disk_dialog.opened && !app.external && app.dirty && app.feed == retained_edits);
    // Save rechecks the disk even before the debounce has reported a change.
    assert(write_file_atomic(argv[4], external_bytes)); assert(!app_api_browser::save(app) && app.external);
    tick(app); click(app, "disk-review"); click_node(app, "disk-local"); assert(!app.external && app.feed == retained_edits);
    click(app, "toggle"); click(app, "save"); assert(!app.dirty && !app.external && app.feed.items[0].completed);
    frames_for(app, 350000000); assert(!app.external && app.baseline == lab_fs_files::revision(argv[4]));
    // Watch the parent, not the file: deletion and recreation remain visible.
    let before_delete = copy(app.feed); assert(delete_file(argv[4])); wait_external(app, true); click(app, "disk-review");
    assert(!node(app, "disk-load").enabled && node(app, "disk-local").enabled);
    click_node(app, "disk-local"); click(app, "save"); assert(!app.external && app.feed == before_delete && file_exists(argv[4]));
    assert(write_file_atomic(argv[4], good.data)); wait_external(app, true); click(app, "disk-review"); click_node(app, "disk-load");
    assert(!app.external && !app.dirty && app.feed == original_snapshot.snapshot.feed);
    let saved = copy(app.feed); let selected = app.selected;
    fetch(app, argv[1], "/stall");
    let ready = lab_net_http::get(str(argv[1], "/waiting")); assert(ready.status == 200);
    assert(gfx::screenshot(str(argv[2], ".loading.png")));
    let before = clock_ns(); modified_key(app, "Left Ctrl", "K"); assert(gfx::inject_text("cancel request")); tick(app); key(app, "Return");
    assert(!app.palette.modal.opened && app.client.cancelling);
    wait(app); assert(clock_ns() - before < 2000000000);
    assert(app.client.cancelled && app.client.code == lab_net_http::CANCELLED && app.client.token.id == 0);
    assert(app.feed == saved && app.selected == selected && app.changed);
    assert(gfx::screenshot(str(argv[2], ".cancelled.png")));
    // A completion queued just before Cancel cannot overwrite the current model.
    var race = app_api_client::State { serial: 99, busy: true, token: lab_io_cancel::create() };
    let queued = app_api_client::Completed { serial: 99, status: 200, elapsed_ms: 0, code: lab_net_http::OK, url: "", feed: app_api_feed::Feed {} };
    var outdated = copy(queued); outdated.serial = 98;
    assert(!app_api_client::accept(race, outdated) && race.busy && lab_io_cancel::valid(race.token));
    assert(app_api_client::cancel(race) && app_api_client::accept(race, queued) && race.cancelled && race.token.id == 0);
    // Completion between a Cancel press and release must not activate Fetch.
    fetch(app, argv[1], "/slow"); let button = lab_ui_view::bounds(app.view, "cancel");
    let x = (button.x + button.w / 2.0) * scale; let y = (button.y + button.h / 2.0) * scale;
    gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, true); tick(app); let serial = app.client.serial;
    wait(app); gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, false); tick(app);
    assert(!app.client.busy && app.client.serial == serial && !app.client.cancelled);
    // A worker completion rebuilds availability while the palette stays open.
    fetch(app, argv[1], "/slow"); modified_key(app, "Left Ctrl", "K"); assert(gfx::inject_text("cancel request")); tick(app);
    let completed_serial = app.client.serial; wait(app);
    assert(app.palette.modal.opened && app.view.input.focused == 100002);
    key(app, "Return"); assert(app.palette.modal.opened && !app.client.busy && app.client.serial == completed_serial);
    key(app, "Escape");
    fetch(app, argv[1], "/bad"); wait(app);
    assert(app.feed.code == app_api_feed::INVALID_JSON && app.feed.items.len == 0 && !app.copied);
    click(app, "response-tab"); click(app, "copy-response"); assert(gfx::clipboard() == "[\n{\"id\":1,}]");
    assert(gfx::screenshot(str(argv[2], ".bad-response.png"))); click(app, "record-tab");
    fetch(app, argv[1], "/schema"); wait(app); assert(app.feed.code == app_api_feed::SCHEMA && app.feed.items.len == 0);
    fetch(app, argv[1], "/fail"); wait(app); assert(app.client.status == 503 && app.feed.items.len == 0);
    assert(app.response == "Unavailable");
    fetch(app, argv[1], "/empty"); wait(app); assert(app.feed.code == app_api_feed::OK && app.feed.items.len == 0);
    fetch(app, argv[1], "/items"); wait(app); assert(app.feed.code == app_api_feed::OK && app.feed.items.len == 40 && app.selected == 9007199254740993);
    let stale = app_api_client::Completed { serial: 0, status: 200, elapsed_ms: 0, code: 0, url: "", feed: app_api_feed::Feed {} };
    assert(!app_api_client::accept(app.client, stale));
    // Exercise the sample's exact close path during a live, stalled request.
    fetch(app, argv[1], "/stall"); let closing = lab_net_http::get(str(argv[1], "/waiting")); assert(closing.status == 200);
    let closing_at = clock_ns(); app_api_browser::join(app, worker);
    assert(clock_ns() - closing_at < 2000000000 && app.client.cancelled && app.client.token.id == 0 && app.feed.items.len == 40 && app.monitor.id == 0);
    // Finite capture draws after join: a deliberately closed watch is not a
    // monitoring failure, and must not introduce a false unavailable notice.
    app.disk_notice = []; tick(app); assert(!lab_text_strings::contains_folded(node(app, "footer").text, "watch unavailable"));
    var tokens: lab_io_cancel::Token[..64] = [];
    for i in 64 { let token = lab_io_cancel::create(); assert(token.id != 0); tokens.push(token); }
    assert(lab_io_cancel::create().id == 0); for &token in tokens { lab_io_cancel::destroy(token); }
    assert(gfx::misuse_count() == 0); app_api_browser::destroy(app); gfx::close(); lab_net_http::shutdown();
    print("API UI: fetch, search, selection, scrolling, toggle, export, cancellation with retained edits and recovery passed");
}
