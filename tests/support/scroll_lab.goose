import std;
import os;
import gfx;
import lab.ui.render.font;
import support.scroll.demo;
fn main() {
    let argv = args(); var headless = false; var frames: i64 = -1; var scale: f32 = 1.0;
    var width: i64 = 1000; var height: i64 = 820; var screenshot: u8[..2048] = "scroll-lab.png";
    var i = 1;
    while i < argv.len {
        if argv[i] == "--headless" { headless = true; }
        else if argv[i] == "--frames" && i + 1 < argv.len { i++; let n, ok = parse_int(argv[i]); if ok && n > 0 { frames = n; } }
        else if argv[i] == "--width" && i + 1 < argv.len { i++; let n, ok = parse_int(argv[i]); if ok && n >= 480 && n <= 8192 { width = n; } }
        else if argv[i] == "--height" && i + 1 < argv.len { i++; let n, ok = parse_int(argv[i]); if ok && n >= 480 && n <= 8192 { height = n; } }
        else if argv[i] == "--scale" && i + 1 < argv.len { i++; let n, ok = parse_flt(argv[i]); if ok && n >= 0.5 && n <= 4.0 { scale = n as f32; } }
        else if argv[i] == "--screenshot" && i + 1 < argv.len { i++; screenshot.resize(0); screenshot.append(argv[i][..min(argv[i].len, 2048)]); }
        i++;
    }
    gfx::text_transactions(true);
    assert(if headless { gfx::open_headless(width, height) } else { gfx::open("Goose / Scroll Lab", width, height, gfx::WINDOW_RESIZABLE) });
    var app = app_scroll_demo::create(lab_ui_render_font::default_font(), scale); var drawn: i64 = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") && app.view.drag.id == 0 { break; }
        app_scroll_demo::frame(app); drawn++; if drawn == frames { break; } sleep_ms(8);
    }
    print("frames=", drawn, " scroll_lab=true screenshot=", gfx::screenshot(screenshot));
    app_scroll_demo::destroy(app); gfx::close();
}
