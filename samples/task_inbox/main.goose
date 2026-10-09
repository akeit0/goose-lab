import std;
import os;
import gfx;
import lab.ui.render.font;
import task_inbox.model;
import task_inbox.inbox;
fn main() {
    let argv = args(); var headless = false; var demo = false; var frames: i64 = -1;
    var width: i64 = 1180; var height: i64 = 820; var scale: f32 = 1.0;
    var data: u8[..2048] = "task-inbox.gxt"; var screenshot: u8[..2048] = "task-inbox.png";
    var font: u8[..2048] = []; font.append(lab_ui_render_font::default_font());
    var i = 1;
    while i < argv.len {
        if argv[i] == "--headless" { headless = true; }
        else if argv[i] == "--demo" { demo = true; }
        else if i + 1 < argv.len && (argv[i] == "--data" || argv[i] == "--screenshot" || argv[i] == "--font") {
            let flag = argv[i]; i++; assert(argv[i].len <= 2048);
            if flag == "--data" { data.resize(0); data.append(argv[i]); }
            else if flag == "--font" { font.resize(0); font.append(argv[i]); }
            else { screenshot.resize(0); screenshot.append(argv[i]); }
        } else if i + 1 < argv.len && argv[i] == "--scale" {
            i++; let n, ok = parse_flt(argv[i]); if ok && n >= 0.5 && n <= 4.0 { scale = n as f32; }
        } else if i + 1 < argv.len && (argv[i] == "--frames" || argv[i] == "--width" || argv[i] == "--height") {
            let flag = argv[i]; i++; let n, ok = parse_int(argv[i]);
            if ok && flag == "--frames" && n > 0 { frames = n; }
            else if ok && flag == "--width" && n >= 480 && n <= 8192 { width = n; }
            else if ok && flag == "--height" && n >= 480 && n <= 8192 { height = n; }
        }
        i++;
    }
    gfx::text_transactions(true);
    assert(if headless { gfx::open_headless(width, height) } else { gfx::open("Goose / Task Inbox", width, height, gfx::WINDOW_RESIZABLE) });
    var app = app_tasks_inbox::create(data, font, scale, demo); var drawn: i64 = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") && app.view.drag.id == 0 { if app.model.editing != 0 { app_tasks_inbox::cancel(app); } else { break; } }
        app_tasks_inbox::frame(app); drawn++; if drawn == frames { break; } sleep_ms(8);
    }
    let saved = gfx::screenshot(screenshot);
    print("frames=", drawn, " tasks=", app.model.journal.store.items.len, " completed=", app_tasks_model::completed(app.model.journal.store), " dirty=", app.model.dirty, " blocked=", app.model.blocked, " screenshot=", saved);
    app_tasks_inbox::destroy(app); gfx::close();
}
