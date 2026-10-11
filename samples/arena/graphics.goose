import std;
import os;
import gfx;
import vec;
import arena.client;
import lab.net.tcp;
import lab.ui.render.scene;
import lab.ui.render.font;
import lab.ui.geometry;
fn color(peer: i64) -> float4 {
    let colors = [float4 { 0.2, 0.85, 1.0, 1.0 }, float4 { 1.0, 0.42, 0.32, 1.0 }, float4 { 0.52, 1.0, 0.55, 1.0 }, float4 { 0.74, 0.55, 1.0, 1.0 },
        float4 { 1.0, 0.7, 0.38, 1.0 }, float4 { 1.0, 0.5, 0.8, 1.0 }, float4 { 0.48, 0.68, 1.0, 1.0 }, float4 { 0.55, 1.0, 0.85, 1.0 }];
    colors[peer]
}
fn main() {
    let argv = args(); var port: i64 = 0; var demo = false; var headless = false; var frames: i64 = 0;
    var screenshot: u8[..2048] = []; var i: i64 = 1;
    while i < argv.len {
        if argv[i] == "--solo" { port = 0; }
        else if argv[i] == "--demo" { demo = true; }
        else if argv[i] == "--headless" { headless = true; }
        else if argv[i] == "--frames" && i + 1 < argv.len { i++; let n, valid = parse_int(argv[i]); assert(valid && n > 0); frames = n; }
        else if argv[i] == "--screenshot" && i + 1 < argv.len { i++; assert(argv[i].len <= 2048); screenshot.append(argv[i]); }
        else { let n, valid = parse_int(argv[i]); if !valid || n < 1 || n > 65535 { print("Usage: arena_game [port|--solo] [--demo] [--headless] [--frames N] [--screenshot path]"); return; } port = n; } i++;
    }
    let title = if port == 0 { "Goose / Star Race / Offline" } else { "Goose / Star Race / Versus" };
    assert(if headless { gfx::open_headless(960, 720) } else { gfx::open(title, 960, 720) });
    var canvas = lab_ui_render_scene::create(lab_ui_render_font::default_font());
    var client = if port == 0 { app_arena_client::solo(demo) } else { app_arena_client::connect(port, demo) };
    var drawn: i64 = 0; var last_frame = clock_ns(); var view_x: f32 = 4.0; var view_y: f32 = 4.0; var positioned = false; var seen_players: i64 = 0;
    while gfx::frame() {
        if gfx::key_pressed("Escape") { break; }
        client.dx = (if gfx::key_down("Right") || gfx::key_down("D") { 1 } else { 0 }) - (if gfx::key_down("Left") || gfx::key_down("A") { 1 } else { 0 });
        client.dy = (if gfx::key_down("Down") || gfx::key_down("S") { 1 } else { 0 }) - (if gfx::key_down("Up") || gfx::key_down("W") { 1 } else { 0 });
        app_arena_client::poll(client);
        seen_players = max(seen_players, client.shown.players.len);
        let now = clock_ns(); let dt = min(0.1, ((now - last_frame) as f32) / 1000000000.0); last_frame = now;
        let own = app_arena_client::mine(client);
        if own >= 0 {
            if !positioned || client.shown.round != client.previous.round { view_x = client.predicted_x; view_y = client.predicted_y; positioned = true; }
            view_x += (client.predicted_x - view_x) * min(1.0, dt * 30.0);
            view_y += (client.predicted_y - view_y) * min(1.0, dt * 30.0);
        }
        let size = gfx::screen_size(); lab_ui_render_scene::begin(canvas, size.x, size.y);
        let light = float4 { 0.88, 0.92, 1.0, 1.0 }; let quiet = float4 { 0.55, 0.64, 0.78, 1.0 };
        lab_ui_render_scene::text(canvas, 0, 48.0, 24.0, if client.offline { "STAR RACE / Offline practice" } else { "STAR RACE / Multiplayer versus" }, light);
        let subtitle = str("Collect 8 stars to win.  Round ", client.shown.round, if client.offline { " / Practice at your own pace" } else { " / Separate players, shared field" });
        lab_ui_render_scene::text(canvas, 0, 48.0, 54.0, subtitle, quiet);
        for p, row in client.shown.players {
            let label = str("P", p.peer.slot + 1, "  ", p.score, "/8", if row == own { " YOU" } else { "" });
            lab_ui_render_scene::text(canvas, 0, 48.0 + row * 108.0, 94.0, label, color(p.peer.slot));
        }
        lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(48.0, 142.0, 864.0, 520.0), float4 { 0.06, 0.085, 0.14, 1.0 }, 10.0);
        for column in 9 { lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(80.0 + column * 100.0, 160.0, 1.0, 480.0), float4 { 0.11, 0.15, 0.22, 1.0 }); }
        for row in 7 { lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(80.0, 160.0 + row * 80.0, 800.0, 1.0), float4 { 0.11, 0.15, 0.22, 1.0 }); }
        for gem in client.shown.gems {
            let x = 80.0 + gem.x * 20.0; let y = 160.0 + gem.y * 20.0;
            lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(x - 10.0, y - 4.0, 20.0, 8.0), float4 { 1.0, 0.8, 0.22, 1.0 }, 3.0);
            lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(x - 4.0, y - 10.0, 8.0, 20.0), float4 { 1.0, 0.8, 0.22, 1.0 }, 3.0);
        }
        let alpha = clamp(((now - client.received_at) as f32) / 100000000.0, 0.0, 1.0);
        for p, row in client.shown.players {
            var x = p.x as f32; var y = p.y as f32;
            if row == own { x = view_x; y = view_y; }
            else if client.previous.round == client.shown.round {
                for old in client.previous.players {
                        if old.id.slot == p.id.slot && old.id.generation == p.id.generation { x = old.x + (p.x - old.x) * alpha; y = old.y + (p.y - old.y) * alpha; }
                }
            }
            x = 80.0 + x * 20.0; y = 160.0 + y * 20.0;
            if row == own { lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(x - 13.0, y - 13.0, 26.0, 26.0), light, 8.0); }
            lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(x - 10.0, y - 10.0, 20.0, 20.0), color(p.peer.slot), 6.0);
            let label = str("P", p.peer.slot + 1); lab_ui_render_scene::text(canvas, 0, x - 10.0, y - 34.0, label, light);
        }
        if client.shown.remaining > 0 {
            let result: u8[>..] = if client.offline { "Round cleared!" } else { str("P", client.shown.winner.slot + 1, " wins!") };
            let banner = str(result, "  New round in ", (client.shown.remaining + 19) / 20);
            lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(270.0, 360.0, 420.0, 48.0), float4 { 0.03, 0.045, 0.07, 0.95 }, 8.0);
            lab_ui_render_scene::text(canvas, 0, 290.0, 370.0, banner, light);
        } else if !client.offline && client.shown.players.len < 2 {
            lab_ui_render_scene::text(canvas, 0, 270.0, 368.0, "Waiting for a second player...", light);
        }
        let message = if client.failed { "Disconnected / invalid state. Escape to close." } else { "WASD / Arrow keys: move    Walk into stars    Escape: close" };
        lab_ui_render_scene::text(canvas, 0, 48.0, 680.0, message, light);
        lab_ui_render_scene::render(canvas, float4 { 0.025, 0.035, 0.06, 1.0 }); drawn++;
        if frames > 0 && drawn >= frames { break; } sleep_ms(8);
    }
    if screenshot.len > 0 { assert(gfx::screenshot(screenshot)); }
    let success = !client.failed && client.snapshots > 0;
    if headless && demo && frames >= 300 {
        let pixels = gfx::read_pixels(gfx::screen()); assert(pixels.len == 960 * 720 * 4 && client.shown.collected > 0);
        var stars: i64 = 0; var players: i64 = 0;
        let own_color = color(client.peer.slot); let red = (own_color.x * 255.0) as i64; let green = (own_color.y * 255.0) as i64; let blue = (own_color.z * 255.0) as i64;
        for p in 960 * 720 {
            if pixels[p * 4] > 230 && pixels[p * 4 + 1] > 170 && pixels[p * 4 + 2] < 100 { stars++; }
            if abs(pixels[p * 4] - red) < 15 && abs(pixels[p * 4 + 1] - green) < 15 && abs(pixels[p * 4 + 2] - blue) < 15 { players++; }
        }
        assert(stars > 400 && players > 100);
        if !client.offline { assert(seen_players >= 2); }
    }
    print("GRAPHICS offline=", client.offline, " peer=", client.peer.slot, " frames=", drawn, " snapshots=", client.snapshots,
        " collected=", client.shown.collected, " seen_players=", seen_players, " corrections=", client.corrections, " failed=", client.failed);
    app_arena_client::destroy(client); assert(lab_net_tcp::live() == 0); lab_ui_render_scene::destroy(canvas); assert(gfx::misuse_count() == 0); gfx::close(); assert(success);
}
