import std;
import os;
import arena.client;
import lab.net.tcp;
fn main() {
    let argv = args(); var port: i64 = 0; var demo = false; var ticks: i64 = 80; var i: i64 = 1;
    while i < argv.len {
        if argv[i] == "--solo" { port = 0; }
        else if argv[i] == "--demo" { demo = true; }
        else if argv[i] == "--ticks" && i + 1 < argv.len { i++; let n, valid = parse_int(argv[i]); assert(valid && n > 0 && n <= 400); ticks = n; }
        else { let n, valid = parse_int(argv[i]); if !valid || n < 1 || n > 65535 { print("Usage: arena_client [port|--solo] [--ticks 80] [--demo]"); return; } port = n; } i++;
    }
    var client = if port == 0 { app_arena_client::solo(demo) } else { app_arena_client::connect(port, demo) }; let deadline = clock_ns() + 30000000000;
    while !client.failed && client.shown.ticks < ticks && clock_ns() < deadline { app_arena_client::poll(client); sleep_ms(2); }
    let own = app_arena_client::mine(client); let score = if own >= 0 { client.shown.players[own].score } else { 0 };
    print("CLIENT offline=", client.offline, " peer=", client.peer.slot, " ticks=", client.shown.ticks, " score=", score,
        " collected=", client.shown.collected, " snapshots=", client.snapshots, " pending=", client.history.len, " history_peak=", client.history_peak, " failed=", client.failed);
    let success = !client.failed && client.shown.ticks >= ticks && client.snapshots > 0;
    app_arena_client::destroy(client); assert(lab_net_tcp::live() == 0); assert(success);
}
