// Small loopback TCP game server. Native code only performs nonblocking socket operations.
import std;
import os;
import regex;
import .world;
extern "exp_server_init" fn transport_init() -> bool;
extern "exp_server_listen" fn listen_raw(port: i64&) -> u64;
extern "exp_server_accept" fn accept_raw(listener: u64, code: i32&) -> u64;
extern "exp_server_receive" fn receive_raw(socket: u64, out: u8&, capacity: i64) -> i64;
extern "exp_server_send" fn send_raw(socket: u64, bytes: const u8&, length: i64) -> i64;
extern "exp_server_close" fn close_raw(socket: u64) -> bool;
extern "exp_server_live" fn live_raw() -> i64;
extern "exp_server_shutdown" fn shutdown_raw() -> bool;
struct Connection {
    socket: u64 = 0, generation: u64 = 0, eof: bool = false, closing: bool = false,
    input: u8[..256] = [], output: u8[..2048] = [], sent: i64 = 0,
}
struct Counters { accepted: i64 = 0, closed: i64 = 0, requests: i64 = 0, paused: i64 = 0, partial: i64 = 0, written: i64 = 0, input_peak: i64 = 0, output_peak: i64 = 0,
    blocked: i64 = 0, compactions: i64 = 0, reclaimed: i64 = 0 }
fn reserve_response(c: Connection&, counters: Counters&) -> bool {
    // Reclaim sent bytes only when the next response needs their capacity.
    // A kernel-blocked write keeps the owned unsent suffix intact across polls.
    if c.output.len > 948 && c.sent > 0 {
        let remaining = c.output.len - c.sent;
        for i in remaining { c.output[i] = c.output[c.sent + i]; }
        c.output.resize(remaining); counters.reclaimed += c.sent; c.sent = 0; counters.compactions++;
    }
    c.output.len <= 948
}
fn route(w: experiment_ecs::World&, re: regex::Regex&, line: const u8[:]) -> u8[>..], bool {
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
        let id, code = experiment_ecs::spawn(w, values[0], values[1], values[2], values[3], true, values[4], values[5], values[6]);
        return if code == 0 { str("ID ", id.slot, " ", id.generation, "\n") } else { str("ERR ", code, "\n") }, false;
    }
    if command == "STEP" && argc == 1 && values[0] >= 1 && values[0] <= 32 {
        for i in values[0] { experiment_ecs::tick(w); } experiment_ecs::check(w);
        return str("TICK ", w.ticks, " ", w.score, " ", w.position.slots.len, "\n"), false;
    }
    if (command == "STATE" || command == "DESPAWN" || command == "VELOCITY") && argc >= 2 && values[0] >= 0 && values[1] > 0 {
        let id = experiment_ecs::Id { values[0], values[1] as u64 };
        if command == "STATE" && argc == 2 { return str("STATE ", experiment_ecs::describe(w, id), "\n"), false; }
        if command == "DESPAWN" && argc == 2 { return str("CODE ", experiment_ecs::despawn(w, id), "\n"), false; }
        if command == "VELOCITY" && argc == 5 && (values[2] == 0 || values[2] == 1) {
            return str("CODE ", experiment_ecs::set_velocity(w, id, values[2] == 1, values[3], values[4]), "\n"), false;
        }
    }
    if command == "STATS" && argc == 0 {
        return str("STATS ", w.ticks, " ", w.spawns, " ", w.destroyed, " ", w.moves, " ", w.collisions, " ", w.score, " ", w.position.slots.len, "\n"), false;
    }
    return str("ERR command\n"), false;
}
fn close_connection(c: Connection&, counters: Counters&) {
    // Discard a bounded amount of unread pipelined input before closing, so a
    // small framing overflow need not reset an already-sent error response.
    var scratch: u8[16] = [0; 16];
    for i in 16 { if receive_raw(c.socket, scratch[0], 16) <= 0 { break; } }
    assert(c.socket != 0 && close_raw(c.socket)); c.socket = 0; c.input.resize(0); c.output.resize(0); c.sent = 0; counters.closed++;
}
fn main() {
    let argv = args(); var quantum: i64 = 32;
    if argv.len == 2 { let value, ok = parse_int(argv[1]); assert(ok && value >= 1 && value <= 2048); quantum = value; } else { assert(argv.len == 1); }
    assert(transport_init()); var port: i64 = 0; var listener = listen_raw(port); assert(listener != 0);
    let command = regex::compile("([A-Z]+)(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?(?: (-?[0-9]{1,19}))?");
    var world = experiment_ecs::create(16); var clients: Connection[3] = [Connection {}; 3]; var counters = Counters {};
    var stopping = false; let deadline = clock_ns() + 60000000000;
    print("LISTEN ", port); flush_stdout();
    loop {
        assert(clock_ns() < deadline);
        if !stopping {
            for slot in 3 {
                let c .= clients[slot]; if c.socket != 0 { continue; }
                var code: i32 = 0; let socket = accept_raw(listener, code); assert(code <= 1);
                if socket == 0 { break; }
                assert(c.generation != 0xFFFFFFFFFFFFFFFF);
                c = Connection { socket: socket, generation: c.generation + 1 }; counters.accepted++;
                c.output.append(str("HELLO ", slot, " ", c.generation, "\n"));
            }
        }
        var active: i64 = 0;
        for slot in 3 {
            let c .= clients[slot]; if c.socket == 0 { continue; } active++;
            if !c.closing {
                // Reserve room for the largest response before consuming a frame.
                if !reserve_response(c, counters) { counters.paused++; }
                else {
                    if !c.eof && c.input.len < 256 {
                        var scratch: u8[16] = [0; 16]; let n = receive_raw(c.socket, scratch[0], min(16, 256 - c.input.len));
                        if n == -2 { close_connection(c, counters); continue; }
                        if n == 0 { c.eof = true; }
                        if n > 0 { c.input.append(scratch[..n]); counters.input_peak = max(counters.input_peak, c.input.len); }
                    }
                    var newline: i64 = -1;
                    for byte, i in c.input { if byte == '\n' { newline = i; break; } }
                    if newline >= 0 {
                        let end = if newline > 0 && c.input[newline - 1] == '\r' { newline - 1 } else { newline };
                        let response, shutdown = route(world, command, c.input[..end]); assert(response.len <= 1100);
                        c.output.append(response); counters.requests++;
                        let closing = c.input[..end] == "CLOSE";
                        let left = c.input.len - newline - 1;
                        for i in left { c.input[i] = c.input[newline + 1 + i]; } c.input.resize(left);
                        if closing { c.closing = true; c.input.resize(0); }
                        if shutdown {
                            stopping = true; assert(close_raw(listener)); listener = 0;
                            for i in 3 { if clients[i].socket != 0 { clients[i].closing = true; clients[i].input.resize(0); } }
                        }
                    } else if c.input.len == 256 || c.eof {
                        if c.input.len > 0 { c.output.append(if c.eof { "ERR truncated\n" } else { "ERR frame-limit\n" }); }
                        c.closing = true; c.input.resize(0);
                    }
                }
            }
            counters.output_peak = max(counters.output_peak, c.output.len); assert(c.output.len <= 2048);
            if c.sent < c.output.len {
                let remaining = c.output.len - c.sent; let n = send_raw(c.socket, c.output[c.sent], min(remaining, quantum));
                if n == -2 { close_connection(c, counters); continue; }
                if n == -1 {
                    if counters.blocked == 0 { print("BLOCKED ", slot, " ", c.generation); flush_stdout(); }
                    counters.blocked++;
                }
                if n > 0 { if n < remaining { counters.partial++; } c.sent += n; counters.written += n; }
            }
            if c.sent == c.output.len { c.output.resize(0); c.sent = 0; if c.closing { close_connection(c, counters); } }
        }
        if stopping && active == 0 { break; } sleep_ms(1);
    }
    assert(listener == 0 && live_raw() == 0 && counters.accepted == counters.closed);
    for slot in world.capacity { if world.entities[slot].alive { assert(experiment_ecs::despawn(world, experiment_ecs::Id { slot, world.entities[slot].generation }) == 0); } }
    experiment_ecs::check(world); assert(world.position.slots.len == 0 && shutdown_raw());
    print("SERVER ", counters.accepted, " ", counters.closed, " ", counters.requests, " ", counters.paused, " ", counters.partial, " ", counters.written,
        " ", counters.input_peak, " ", counters.output_peak, " ", live_raw(), " ", counters.blocked, " ", counters.compactions, " ", counters.reclaimed);
}
