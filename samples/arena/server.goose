import std;
import os;
import arena.game;
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
    var server = lab_net_line_server::create(lab_net_line_server::Options { port: port, connections: 8, response_bytes: 2048 });
    if server.code != 0 { print("Cannot listen on loopback port ", port, ": code ", server.code); return; }
    var game = app_arena_game::create(); let started = clock_ns(); var next_tick = started + 50000000;
    print("LISTEN ", server.port); flush_stdout();
    while lab_net_line_server::running(server) {
        let now = clock_ns();
        if duration > 0 && now - started >= duration * 1000000000 { lab_net_line_server::stop(server, now); }
        if !manual && server.listener != 0 {
            var catchup: i64 = 0; while now >= next_tick && catchup < 4 { app_arena_game::tick(game); next_tick += 50000000; catchup++; }
            if now >= next_tick { next_tick = now + 50000000; }
        }
        lab_net_line_server::poll(server, now) { id, line, kind =>
            if kind == lab_net_line_server::CONNECTED { lab_net_line_server::Reply { bytes: str("HELLO ", id.slot, " ", id.generation, "\n") } }
            else { app_arena_game::route(game, line, manual) }
        };
        sleep_ms(1);
    }
    app_arena_game::clear(game); lab_net_line_server::destroy(server);
    print("ARENA stopped score=", game.world.score, " accepted=", server.counters.accepted, " closed=", server.counters.closed,
        " timed_out=", server.counters.timed_out, " native=", lab_net_tcp::live());
}
