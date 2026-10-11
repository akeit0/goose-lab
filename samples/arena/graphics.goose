import std;
import os;
import gfx;
import vec;
import arena.client;
import lab.ui.render.scene;
import lab.ui.render.font;
import lab.ui.geometry;
fn main() {
    let argv = args(); if argv.len < 2 { print("Usage: arena_game port [--demo] [--headless] [--frames N] [--screenshot path]"); return; }
    let port, ok = parse_int(argv[1]); assert(ok); var demo = false; var headless = false; var frames: i64 = 0;
    var screenshot: u8[..2048] = []; var i: i64 = 2;
    while i < argv.len {
        if argv[i] == "--demo" { demo = true; }
        else if argv[i] == "--headless" { headless = true; }
        else if argv[i] == "--frames" && i + 1 < argv.len { i++; let n, valid = parse_int(argv[i]); assert(valid && n > 0); frames = n; }
        else if argv[i] == "--screenshot" && i + 1 < argv.len { i++; assert(argv[i].len <= 2048); screenshot.append(argv[i]); }
        else { print("Unknown option ", argv[i]); return; } i++;
    }
    assert(if headless { gfx::open_headless(960, 720) } else { gfx::open("Goose / Co-op Arena", 960, 720) });
    var canvas = lab_ui_render_scene::create(lab_ui_render_font::default_font()); var client = app_arena_client::connect(port, demo); var drawn: i64 = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") { break; }
        if gfx::key_pressed("Up") { client.aim = min(16, (client.aim / 8 + 1) * 8); }
        if gfx::key_pressed("Down") { client.aim = max(-16, (client.aim / 8 - 1) * 8); }
        let motion = gfx::mouse_delta();
        if gfx::mouse_in_window() && (motion.y != 0.0 || gfx::mouse_pressed(1)) { let p = gfx::mouse_pos(); client.aim = clamp(((600.0 - p.y) / 8.0 - 32.0) as i64, -20, 20); }
        if gfx::key_pressed("Space") || gfx::mouse_pressed(1) { client.fire = true; }
        if gfx::key_pressed("R") { client.reset = true; }
        app_arena_client::poll(client);
        let size = gfx::screen_size(); lab_ui_render_scene::begin(canvas, size.x, size.y);
        let light = float4 { 0.86, 0.9, 0.98, 1.0 };
        lab_ui_render_scene::text(canvas, 0, 32.0, 28.0, "CO-OP ARENA / Goose ECS + TCP", light);
        let status = str("Score ", client.shown.score, "   Missed ", client.shown.misses, "/5   Shots ", client.shown.shots, "   Tick ", client.shown.ticks);
        lab_ui_render_scene::text(canvas, 0, 32.0, 60.0, status, light);
        lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(32.0, 96.0, 800.0, 536.0), float4 { 0.055, 0.075, 0.12, 1.0 }, 8.0);
        for lane in [-16, -8, 0, 8, 16] {
            let y = 600.0 - ((lane + 32) as f32) * 8.0;
            lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(80.0, y, 640.0, 1.0), float4 { 0.14, 0.18, 0.25, 1.0 });
        }
        for e in client.shown.entities {
            let x = 80.0 + ((e.x + 32) as f32) * 10.0; let y = 600.0 - ((e.y + 32) as f32) * 8.0;
            let color = if e.team == 1 { float4 { 0.2, 0.86, 1.0, 1.0 } } else { float4 { 1.0, 0.48, 0.24, 1.0 } };
            lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(x - 6.0, y - 6.0, 12.0, 12.0), color, 4.0);
        }
        let aim = 600.0 - ((client.aim + 32) as f32) * 8.0;
        lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(680.0, aim - 8.0, 22.0, 16.0), float4 { 0.3, 1.0, 0.65, 1.0 }, 4.0);
        let message = if client.failed { "Disconnected / invalid server response. Escape to close." } else if client.shown.misses >= 5 { "Game over. Press R to restart." } else { "Mouse or Up/Down: aim   Space/click: fire   R: reset   Escape: close" };
        lab_ui_render_scene::text(canvas, 0, 32.0, 664.0, message, light);
        lab_ui_render_scene::render(canvas, float4 { 0.025, 0.035, 0.06, 1.0 }); drawn++;
        if frames > 0 && drawn >= frames { break; } sleep_ms(8);
    }
    if screenshot.len > 0 { assert(gfx::screenshot(screenshot)); }
    let success = !client.failed && client.snapshots > 0;
    if headless && demo && frames >= 200 {
        let pixels = gfx::read_pixels(gfx::screen()); assert(pixels.len == 960 * 720 * 4 && client.shown.score > 0);
        var avatar: i64 = 0;
        for p in 960 * 720 { if pixels[p * 4] < 130 && pixels[p * 4 + 1] > 230 && pixels[p * 4 + 2] < 200 { avatar++; } }
        assert(avatar > 100);
    }
    print("GRAPHICS frames=", drawn, " snapshots=", client.snapshots, " score=", client.shown.score, " failed=", client.failed);
    app_arena_client::destroy(client); lab_ui_render_scene::destroy(canvas); assert(gfx::misuse_count() == 0); gfx::close(); assert(success);
}
