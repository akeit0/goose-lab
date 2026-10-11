import std;
import os;
import arena.game;
import arena.protocol;
import lab.net.line_server;
import lab.net.tcp;
fn main() {
    let argv = args(); var port: i64 = 7777; var manual = false; var duration: i64 = 0;
    var i: i64 = 1;
    while i < argv.len {
        if argv[i] == "--manual" { manual = true; }
        else if i + 1 < argv.len && (argv[i] == "--port" || argv[i] == "--duration") {
            let flag = argv[i]; i++; let n, ok = parse_int(argv[i]); assert(ok);
            if flag == "--port" { port = n; } else { assert(n >= 1 && n <= 3600); duration = n; }
        } else { print("Usage: arena_server [--port 7777] [--manual] [--duration seconds]"); return; }
        i++;
    }
    var server = lab_net_line_server::create(lab_net_line_server::Options { port: port, connections: 8, response_bytes: 64 });
    if server.code != 0 { print("Cannot listen on loopback port ", port, ": code ", server.code); return; }
    var game = app_arena_game::create(true); let started = clock_ns(); var next_tick = started + 50000000; var next_publish = started;
    var revisions: i64[8] = [-1; 8]; var generations: u64[8] = [0; 8]; var pushed: i64 = 0; var skipped: i64 = 0;
    print("LISTEN ", server.port); flush_stdout();
    while lab_net_line_server::running(server) {
        let now = clock_ns();
        if duration > 0 && now - started >= duration * 1000000000 { lab_net_line_server::stop(server, now); }
        lab_net_line_server::poll(server, now) { id, line, kind =>
            let peer = app_arena_game::Peer { id.slot, id.generation };
            if kind == lab_net_line_server::CONNECTED {
                assert(app_arena_game::join(game, peer));
                lab_net_line_server::Reply { bytes: str("WELCOME 2 ", id.slot, " ", id.generation, "\n") }
            } else { app_arena_protocol::route(game, peer, line, manual) }
        };
        var departed: app_arena_game::Peer[..8] = [];
        for p in game.players.values {
            if !lab_net_line_server::valid(server, lab_net_line_server::Id { p.peer.slot, p.peer.generation }) { departed.push(p.peer); }
        }
        for peer in departed { app_arena_game::leave(game, peer); }
        if server.listener != 0 && !manual {
            var catchup: i64 = 0;
            while now >= next_tick && catchup < 4 { app_arena_game::tick(game); next_tick += 50000000; catchup++; }
            if now >= next_tick { next_tick = now + 50000000; }
        }
        if server.listener != 0 && (manual || now >= next_publish) {
            let bytes = app_arena_protocol::snapshot(game);
            for slot in 8 {
                let id = lab_net_line_server::Id { slot, server.clients[slot].generation };
                if !lab_net_line_server::valid(server, id) { continue; }
                if revisions[slot] == game.revision && generations[slot] == id.generation { continue; }
                // Keep at most one state packet in flight. After it drains, send
                // the latest state, never a FIFO backlog of obsolete snapshots.
                if lab_net_line_server::pending(server, id) != 0 { skipped++; continue; }
                if lab_net_line_server::send(server, id, bytes) {
                    revisions[slot] = game.revision; generations[slot] = id.generation; pushed++;
                }
            }
            next_publish = now + 100000000;
        }
        sleep_ms(1);
    }
    lab_net_line_server::destroy(server);
    print("ARENA stopped collected=", game.collected, " pushed=", pushed, " skipped=", skipped, " accepted=", server.counters.accepted,
        " closed=", server.counters.closed, " timed_out=", server.counters.timed_out, " native=", lab_net_tcp::live());
}
