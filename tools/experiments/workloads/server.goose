// Exercise reusable line transport with the independently modeled projectile game.
import std;
import os;
import regex;
import arena.world;
import lab.ecs.pool;
import lab.net.line_server;
import lab.net.tcp;
fn route(w: app_arena_world::World&, re: regex::Regex&, line: const u8[:]) -> u8[>..], bool {
    let start, end = regex::find(re, line);
    if start != 0 || end != line.len { return str("ERR syntax\n"), false; }
    var command: u8[..16] = []; var values: i64[7] = [0; 7]; var argc: i64 = 0; var parsed = true;
    regex::each_captures(re, line) { caps =>
        let name = regex::group(caps, 1); if name.len > 16 { parsed = false; } else { command.append(name); }
        for k in 7 {
            if caps.slots[(k + 2) * 2] >= 0 {
                let number, ok = parse_int(regex::group(caps, k + 2)); parsed = parsed && ok; values[argc] = number; argc++;
            }
        }
    };
    if !parsed { return str("ERR syntax\n"), false; }
    if command == "PING" && argc == 0 { return str("PONG\n"), false; }
    if (command == "CLOSE" || command == "SHUTDOWN") && argc == 0 { return str("BYE\n"), command == "SHUTDOWN"; }
    if command == "BURST" && argc == 1 && values[0] >= 1 && values[0] <= 1024 {
        var out: u8[>..] = []; out.append("DATA "); out.resize(out.len + values[0], 'x'); out.push('\n'); return out, false;
    }
    if command == "SPAWN" && argc == 7 {
        let id, code = app_arena_world::spawn(w, values[0], values[1], values[2], values[3], true, values[4], values[5], values[6]);
        return if code == 0 { str("ID ", id.slot, " ", id.generation, "\n") } else { str("ERR ", code, "\n") }, false;
    }
    if command == "STEP" && argc == 1 && values[0] >= 1 && values[0] <= 32 {
        for i in values[0] { app_arena_world::tick(w); } app_arena_world::check(w);
        return str("TICK ", w.ticks, " ", w.score, " ", w.position.rows.slots.len, "\n"), false;
    }
    if (command == "STATE" || command == "DESPAWN" || command == "VELOCITY") && argc >= 2 && values[0] >= 0 && values[1] > 0 {
        let id = lab_ecs_pool::Id { values[0], values[1] as u64 };
        if command == "STATE" && argc == 2 { return str("STATE ", app_arena_world::describe(w, id), "\n"), false; }
        if command == "DESPAWN" && argc == 2 { return str("CODE ", app_arena_world::despawn(w, id), "\n"), false; }
        if command == "VELOCITY" && argc == 5 && (values[2] == 0 || values[2] == 1) {
            return str("CODE ", app_arena_world::set_velocity(w, id, values[2] == 1, values[3], values[4]), "\n"), false;
        }
    }
    if command == "STATS" && argc == 0 {
        return str("STATS ", w.ticks, " ", w.spawns, " ", w.destroyed, " ", w.moves, " ", w.collisions, " ", w.score, " ", w.position.rows.slots.len, "\n"), false;
    }
    return str("ERR command\n"), false;
}
fn main() {
    let argv = args(); var quantum: i64 = 32;
    if argv.len == 2 { let value, ok = parse_int(argv[1]); assert(ok && value >= 1 && value <= 2048); quantum = value; } else { assert(argv.len == 1); }
    var server = lab_net_line_server::create(lab_net_line_server::Options { send_bytes: quantum, send_buffer: 4096, idle_ms: 0 });
    assert(server.code == 0);
    let command = regex::compile("([A-Z]+)(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?");
    var world = app_arena_world::create(16); let deadline = clock_ns() + 60000000000;
    print("LISTEN ", server.port); flush_stdout(); var reported = false;
    while lab_net_line_server::running(server) {
        assert(clock_ns() < deadline);
        lab_net_line_server::poll(server, clock_ns()) { id, line, kind =>
            if kind == lab_net_line_server::CONNECTED { lab_net_line_server::Reply { bytes: str("HELLO ", id.slot, " ", id.generation, "\n") } }
            else {
                let bytes, shutdown = route(world, command, line);
                lab_net_line_server::Reply { action: if shutdown { lab_net_line_server::STOP } else if line == "CLOSE" { lab_net_line_server::CLOSE } else { lab_net_line_server::KEEP }, bytes: copy(bytes) }
            }
        };
        if !reported && server.counters.blocked > 0 {
            print("BLOCKED ", server.counters.blocked_id.slot, " ", server.counters.blocked_id.generation); flush_stdout(); reported = true;
        }
        sleep_ms(1);
    }
    for slot in world.pool.capacity { if world.pool.entities[slot].alive { assert(app_arena_world::despawn(world, lab_ecs_pool::id(world.pool, slot)) == 0); } }
    app_arena_world::check(world); lab_net_line_server::destroy(server);
    let c = server.counters; assert(server.code == 0 && c.accepted == c.closed && lab_net_tcp::live() == 0);
    print("SERVER ", c.accepted, " ", c.closed, " ", c.requests, " ", c.paused, " ", c.partial, " ", c.written,
        " ", c.input_peak, " ", c.output_peak, " ", lab_net_tcp::live(), " ", c.blocked, " ", c.compactions, " ", c.reclaimed);
}
