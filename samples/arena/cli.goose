import std;
import os;
import arena.client;
fn main() {
    let argv = args(); if argv.len < 2 { print("Usage: arena_client port [--ticks 80] [--demo]"); return; }
    let port, ok = parse_int(argv[1]); assert(ok); var demo = false; var ticks: i64 = 80;
    var i: i64 = 2;
    while i < argv.len {
        if argv[i] == "--demo" { demo = true; }
        else if argv[i] == "--ticks" && i + 1 < argv.len { i++; let n, valid = parse_int(argv[i]); assert(valid && n > 0 && n <= 10000); ticks = n; }
        else { print("Usage: arena_client port [--ticks 80] [--demo]"); return; }
        i++;
    }
    var client = app_arena_client::connect(port, demo); let deadline = clock_ns() + 30000000000;
    while !client.failed && client.shown.ticks < ticks && clock_ns() < deadline { app_arena_client::poll(client); sleep_ms(2); }
    print("CLIENT ticks=", client.shown.ticks, " score=", client.shown.score, " misses=", client.shown.misses,
        " shots=", client.shown.shots, " snapshots=", client.snapshots, " failed=", client.failed);
    let success = !client.failed && client.shown.ticks >= ticks && client.snapshots > 0;
    app_arena_client::destroy(client); assert(success);
}
