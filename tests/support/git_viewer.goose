import std;
import os;
import gfx;
import lab.ui.render.font;
import lab.git.client;
import workbench.git.viewer;
import lab.ui.controls.field;
import lab.ui.view;
fn main() {
    let argv = args(); var repo: u8[..512] = "."; var headless = false; var staged = false; var history = false;
    var search: u8[..512] = []; var include: u8[..256] = "**"; var ignore_case = false;
    var frames: i64 = -1; var width: i64 = 1180; var height: i64 = 820; var scale: f32 = 1.0;
    var screenshot: u8[..2048] = "git-viewer.png"; var i: i64 = 1;
    while i < argv.len {
        if argv[i] == "--headless" { headless = true; } else if argv[i] == "--staged" { staged = true; } else if argv[i] == "--history" { history = true; }
        else if argv[i] == "--ignore-case" { ignore_case = true; }
        else if i + 1 < argv.len && argv[i] == "--search" { i++; assert(argv[i].len <= 512); search = argv[i]; }
        else if i + 1 < argv.len && argv[i] == "--include" { i++; assert(argv[i].len <= 256); include = argv[i]; }
        else if i + 1 < argv.len && argv[i] == "--repo" { i++; assert(argv[i].len <= 512); repo = argv[i]; }
        else if i + 1 < argv.len && argv[i] == "--screenshot" { i++; assert(argv[i].len <= 2048); screenshot = argv[i]; }
        else if i + 1 < argv.len && (argv[i] == "--frames" || argv[i] == "--width" || argv[i] == "--height") {
            let n, ok = parse_int(argv[i + 1]); if ok {
                if argv[i] == "--frames" && n > 0 { frames = n; }
                else if argv[i] == "--width" && n >= 560 && n <= 2560 { width = n; }
                else if argv[i] == "--height" && n >= 640 && n <= 1440 { height = n; }
            } i++;
        } else if i + 1 < argv.len && argv[i] == "--scale" { i++; let n, ok = parse_flt(argv[i]); if ok && n >= 0.5 && n <= 4.0 { scale = n as f32; } }
        i++;
    }
    gfx::text_transactions(true);
    assert(if headless { gfx::open_headless(width, height) } else { gfx::open("Goose / Git Diff", width, height, gfx::WINDOW_RESIZABLE) });
    var app = app_git_viewer::create(repo, lab_ui_render_font::default_font(), lab_ui_render_font::default_mono(), scale); app.staged = staged;
    let worker = thread_spawn(lab_git_client::worker); app_git_viewer::refresh(app, if history { 2 } else { -1 });
    if search.len > 0 {
        while app.client.busy { app_git_viewer::poll(app); sleep_ms(2); }
        assert(gfx::frame()); app_git_viewer::frame(app);
        app_git_viewer::apply_action(app, lab_ui_view::Event<app_git_viewer::Action> { kind: lab_ui_view::ACTIVATE, action: app_git_viewer::Action.ProjectSearch, source: 0 });
        lab_ui_controls_field::set(app_git_viewer::search_query(app), search); lab_ui_controls_field::set(app_git_viewer::include_query(app), include); app.ignore_case = ignore_case;
        app_git_viewer::run_search(app);
    }
    var drawn: i64 = 0; var finite = false;
    while gfx::frame() {
        if gfx::key_pressed("Escape") && !app.palette.modal.opened && !app.text.find_open { break; } app_git_viewer::frame(app); drawn++;
        if drawn == frames { finite = true; break; } sleep_ms(8);
    }
    app_git_viewer::join(app, worker, finite); if gfx::frame() { app_git_viewer::frame(app); }
    print("files=", app.files.items.len, " matches=", app.hits.len, " rows=", app.diff.patch.rows.len, " staged=", app.staged, " busy=", app.client.busy, " screenshot=", gfx::screenshot(screenshot));
    app_git_viewer::destroy(app); gfx::close();
}
