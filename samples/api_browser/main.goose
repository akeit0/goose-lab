import std;
import os;
import gfx;
import lab.net.http;
import lab.ui.render.font;
import lab.ui.controls.field;
import api_browser.client;
import api_browser.browser;
fn main() {
    let argv = args(); var headless = false; var fetch = false; var frames: i64 = -1;
    var width: i64 = 1180; var height: i64 = 820; var scale: f32 = 1.0;
    var url: u8[..512] = []; var screenshot: u8[..2048] = "api-browser.png";
    var data: u8[..2048] = "api-browser.json";
    var i: i64 = 1;
    while i < argv.len {
        if argv[i] == "--headless" { headless = true; } else if argv[i] == "--fetch" { fetch = true; }
        else if i + 1 < argv.len && argv[i] == "--url" { assert(argv[i + 1].len <= 512); url = argv[i + 1]; i++; }
        else if argv[i] == "--no-data" { data = []; }
        else if i + 1 < argv.len && argv[i] == "--data" { assert(argv[i + 1].len <= 2048); data = argv[i + 1]; i++; }
        else if i + 1 < argv.len && argv[i] == "--screenshot" { assert(argv[i + 1].len <= 2048); screenshot = argv[i + 1]; i++; }
        else if i + 1 < argv.len && (argv[i] == "--frames" || argv[i] == "--width" || argv[i] == "--height") {
            let value, ok = parse_int(argv[i + 1]); if ok {
                if argv[i] == "--frames" && value > 0 { frames = value; }
                else if argv[i] == "--width" && value >= 560 && value <= 8192 { width = value; }
                else if argv[i] == "--height" && value >= 640 && value <= 8192 { height = value; }
            }
            i++;
        } else if i + 1 < argv.len && argv[i] == "--scale" { let value, ok = parse_flt(argv[i + 1]); if ok && value >= 0.5 && value <= 4.0 { scale = value as f32; } i++; }
        i++;
    }
    assert(lab_net_http::init() == lab_net_http::OK);
    gfx::text_transactions(true);
    assert(if headless { gfx::open_headless(width, height) } else { gfx::open("Goose / API Browser", width, height, gfx::WINDOW_RESIZABLE) });
    var app = app_api_browser::create(lab_ui_render_font::default_font(), scale, data); if url.len > 0 { lab_ui_controls_field::set(app_api_browser::url(app), url); }
    let worker = thread_spawn(app_api_client::worker);
    if fetch { assert(app_api_client::start(app.client, app_api_browser::url(app).text)); }
    var drawn: i64 = 0; var finite_capture = false;
    while gfx::frame() {
        if gfx::key_pressed("Escape") && !app.palette.modal.opened && !app.disk_dialog.opened && !(app.show_response && app.text.find_open) { break; }
        app_api_browser::frame(app); drawn++; if drawn == frames { finite_capture = true; break; } sleep_ms(8);
    }
    // Finite captures finish their request; user close/Escape cancels before join.
    app_api_browser::join(app, worker, finite_capture);
    // Paint the final accepted response before a finite-run capture.
    if gfx::frame() { app_api_browser::frame(app); }
    print("records=", app.feed.items.len, " error=", app.feed.code, " busy=", app.client.busy, " status=", app.client.status, " screenshot=", gfx::screenshot(screenshot));
    print("restored=", app.restored, " selected=", app.selected, " changed=", app.changed, " blocked=", app.blocked, " dirty=", app.dirty);
    app_api_browser::destroy(app); gfx::close(); lab_net_http::shutdown();
}
