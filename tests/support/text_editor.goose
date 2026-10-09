import std;
import gfx;
import workbench.editor.single;
import lab.document.model;
import lab.document.file;
fn main() {
    let argv = args(); var path: u8[..512] = []; var headless = false; var frames: i64 = -1; var width: i64 = 1180; var height: i64 = 820; var scale: f32 = 1.0; var screenshot: u8[..2048] = "text-editor.png";
    var i: i64 = 1;
    while i < argv.len {
        if argv[i] == "--headless" { headless = true; }
        else if i + 1 < argv.len && argv[i] == "--file" { i++; assert(argv[i].len <= 512); path = argv[i]; }
        else if i + 1 < argv.len && argv[i] == "--screenshot" { i++; screenshot = argv[i]; }
        else if i + 1 < argv.len && argv[i] == "--scale" { i++; let n, ok = parse_flt(argv[i]); assert(ok && n >= 0.5 && n <= 4.0); scale = n as f32; }
        else if i + 1 < argv.len && (argv[i] == "--frames" || argv[i] == "--width" || argv[i] == "--height") {
            let n, ok = parse_int(argv[i + 1]); assert(ok && n > 0); if argv[i] == "--frames" { frames = n; } else if argv[i] == "--width" { assert(n >= 560 && n <= 2560); width = n; } else { assert(n >= 640 && n <= 1440); height = n; } i++;
        } i++;
    }
    gfx::text_transactions(true);
    assert(if headless { gfx::open_headless(width, height) } else { gfx::open("Goose / Text Editor", width, height, gfx::WINDOW_RESIZABLE) });
    var app = app_editor_single::create(path, scale); var drawn: i64 = 0;
    while gfx::frame() { app_editor_single::frame(app); drawn++; if app.closing.ready || drawn == frames { break; } sleep_ms(8); }
    while lab_document_file::busy(app.file) { app_editor_single::poll(app); sleep_ms(2); }
    if frames > 0 && gfx::frame() { app_editor_single::frame(app); print("bytes=", lab_document_model::size(app.file.document), " dirty=", lab_document_model::dirty(app.file.document), " screenshot=", gfx::screenshot(screenshot)); }
    app_editor_single::destroy(app); gfx::close();
}
