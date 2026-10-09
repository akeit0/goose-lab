import std;
import gfx;
import workbench.controller;
import workbench.git.viewer;
import workbench.editor.workspace;
import lab.document.model;
import lab.ui.render.scene;
fn main() {
    let argv = args(); var root: u8[..512] = "."; var file: u8[..512] = [];
    var headless = false; var frames: i64 = -1; var width: i64 = 1180; var height: i64 = 820;
    var scale: f32 = 1.0; var screenshot: u8[..2048] = "workbench.png"; var git = false; var mode: i32 = 0;
    var i: i64 = 1;
    while i < argv.len {
        if argv[i] == "--headless" { headless = true; }
        else if argv[i] == "--git" { git = true; }
        else if argv[i] == "--staged" { git = true; mode = 1; }
        else if argv[i] == "--history" { git = true; mode = 2; }
        else if i + 1 < argv.len && (argv[i] == "--root" || argv[i] == "--file" || argv[i] == "--screenshot") {
            let arg = argv[i]; i++;
            if arg == "--root" { assert(argv[i].len <= 512); root = argv[i]; }
            else if arg == "--file" { assert(argv[i].len <= 512); file = argv[i]; }
            else { assert(argv[i].len <= 2048); screenshot = argv[i]; }
        } else if i + 1 < argv.len && argv[i] == "--scale" { i++; let n, ok = parse_flt(argv[i]); assert(ok && n >= 0.5 && n <= 4.0); scale = n as f32; }
        else if i + 1 < argv.len && (argv[i] == "--frames" || argv[i] == "--width" || argv[i] == "--height") {
            let n, ok = parse_int(argv[i + 1]); assert(ok && n > 0);
            if argv[i] == "--frames" { frames = n; } else if argv[i] == "--width" { assert(n >= 560 && n <= 2560); width = n; } else { assert(n >= 640 && n <= 1440); height = n; } i++;
        } else { print("Usage: workbench [--root folder] [--file path] [--git|--staged|--history] [--headless --frames N --screenshot path] [--width N --height N --scale N]"); return; }
        i++;
    }
    gfx::text_transactions(true);
    assert(if headless { gfx::open_headless(width, height) } else { gfx::open("Goose / Workbench", width, height, gfx::WINDOW_RESIZABLE) });
    var workspace = app_editor_workspace::create(root, file, scale, true); var git_view = app_git_viewer::App { canvas: default<lab_ui_render_scene::Canvas>() }; var app = app_workbench::State {};
    app_workbench::init(app, workspace, git_view, mode); app.changes = git;
    var drawn: i64 = 0;
    while gfx::frame() { app_workbench::frame(app, workspace, git_view); drawn++; if workspace.editor.closing.ready || drawn == frames { break; } sleep_ms(8); }
    if frames > 0 {
        let until = clock_ns() + 15000000000;
        while app_workbench::busy(app, workspace, git_view) && clock_ns() < until { app_workbench::poll(app, workspace, git_view); sleep_ms(2); }
        if gfx::frame() { app_workbench::frame(app, workspace, git_view); print("bytes=", lab_document_model::size(workspace.editor.file.document), " files=", git_view.files.items.len, " mode=", if git_view.history { "history" } else if git_view.staged { "staged" } else { "working" }, " busy=", app_workbench::busy(app, workspace, git_view), " screenshot=", gfx::screenshot(screenshot)); }
    }
    app_workbench::destroy(app, workspace, git_view); gfx::close();
}
