// Shared by the CLI and graphics sample. Only completed snapshots reach the view.
namespace app_arena_client;
import std;
import os;
import lab.net.line_client;
struct Entity { slot: i64, generation: u64, x: i64, y: i64, hp: i64, ttl: i64, team: i64, moving: i64, vx: i64, vy: i64 }
struct Snapshot { ticks: i64 = 0, score: i64 = 0, misses: i64 = 0, shots: i64 = 0, entities: Entity[..16] = [] }
struct Client { network: lab_net_line_client::Client = lab_net_line_client::Client {}, shown: Snapshot = Snapshot {}, pending: Snapshot = Snapshot {},
    phase: i32 = 0, expected: i64 = 0, deadline: i64 = 0, refresh: i64 = 0, snapshots: i64 = 0, aim: i64 = 0,
    fire: bool = false, reset: bool = false, demo: bool = false, last_fire: i64 = -4, failed: bool = false }
fn connect(port: i64, demo: bool = false) -> Client {
    let network = lab_net_line_client::connect(port);
    Client { network: network, deadline: clock_ns() + 3000000000, demo: demo, failed: network.code != 0 }
}
fn uint(text: const u8[:]) -> u64, bool {
    var value: u64 = 0; if text.len == 0 || text.len > 20 { return 0, false; }
    for byte in text {
        if byte < '0' || byte > '9' { return 0, false; }
        let digit = (byte - '0') as u64;
        if value > (0xFFFFFFFFFFFFFFFF - digit) / 10 { return 0, false; } value = value * 10 + digit;
    }
    return value, true;
}
fn consume(c: Client&, line: const u8[:]) -> bool {
    if c.phase == 0 { if !starts_with(line, "HELLO ") { return false; } c.phase = 1; return true; }
    if c.phase == 2 {
        if line != "RESET" && !starts_with(line, "FIRED ") && !starts_with(line, "ERR ") { return false; }
        c.phase = 1; c.refresh = 0; return true;
    }
    if c.phase == 3 {
        let parts = split(line, ' '); if parts.len != 6 || parts[0] != "FRAME" { return false; }
        var values: i64[5] = [0; 5];
        for i in 5 { let value, ok = parse_int(parts[i + 1]); if !ok || value < 0 { return false; } values[i] = value; }
        if values[4] > 16 { return false; }
        c.pending = Snapshot { ticks: values[0], score: values[1], misses: values[2], shots: values[3] };
        c.expected = values[4]; c.phase = 4; return true;
    }
    if c.phase == 4 {
        if line == "END" {
            if c.pending.entities.len != c.expected { return false; }
            c.shown = c.pending; c.snapshots++; c.phase = 1; c.refresh = clock_ns() + 40000000;
            if c.demo && c.shown.ticks >= c.last_fire + 4 {
                for e in c.shown.entities { if e.team == 2 { c.aim = e.y; c.fire = true; break; } }
            }
            return true;
        }
        if !starts_with(line, "ENTITY ") || c.pending.entities.len >= c.expected { return false; }
        let parts = split(line[7..], ','); if parts.len != 10 { return false; }
        var values: i64[10] = [0; 10];
        let generation, valid = uint(parts[1]); if !valid || generation == 0 { return false; }
        for i in 10 { if i == 1 { continue; } let value, ok = parse_int(parts[i]); if !ok { return false; } values[i] = value; }
        if values[0] < 0 || values[0] >= 16 || values[2] < -32 || values[2] > 32 || values[3] < -32 || values[3] > 32 ||
            values[4] < 1 || values[4] > 99 || values[5] < 1 || values[5] > 128 || values[6] < 1 || values[6] > 2 ||
            values[7] < 0 || values[7] > 1 || values[8] < -8 || values[8] > 8 || values[9] < -8 || values[9] > 8 { return false; }
        for e in c.pending.entities { if e.slot == values[0] { return false; } }
        c.pending.entities.push(Entity { values[0], generation, values[2], values[3], values[4], values[5], values[6], values[7], values[8], values[9] }); return true;
    }
    false
}
fn poll(c: Client&) {
    if c.failed { return; }
    lab_net_line_client::poll(c.network);
    loop { let line, complete = lab_net_line_client::line(c.network); if !complete { break; } if !consume(c, line) { c.failed = true; break; } }
    let now = clock_ns();
    if c.network.code != 0 || (c.phase != 1 && now >= c.deadline) { c.failed = true; return; }
    if c.phase != 1 { return; }
    if c.reset {
        assert(lab_net_line_client::send(c.network, "RESET")); c.reset = false; c.fire = false; c.last_fire = -4; c.phase = 2;
    } else if c.fire {
        let command = str("FIRE ", c.aim); assert(lab_net_line_client::send(c.network, command)); c.fire = false; c.last_fire = c.shown.ticks; c.phase = 2;
    } else if now >= c.refresh { assert(lab_net_line_client::send(c.network, "SNAPSHOT")); c.phase = 3; }
    c.deadline = now + 3000000000;
}
fn destroy(c: Client&) { lab_net_line_client::destroy(c.network); }
