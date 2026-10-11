// Offline capture and network publication share one view. Prediction retains
// owned numbered inputs, replays only those not acknowledged by the server.
namespace app_arena_client;
import std;
import os;
import arena.game;
import arena.state;
import lab.net.line_client;
struct Client { network: lab_net_line_client::Client = lab_net_line_client::Client {}, local: app_arena_game::Game = app_arena_game::Game {},
    offline: bool = false, peer: app_arena_game::Peer = app_arena_game::Peer {}, shown: app_arena_state::Snapshot = app_arena_state::Snapshot {},
    previous: app_arena_state::Snapshot = app_arena_state::Snapshot {}, pending: app_arena_state::Snapshot = app_arena_state::Snapshot {},
    history: app_arena_game::Input[..32] = [], sequence: i64 = 0, acknowledged: i64 = 0, predicted_x: i64 = 4, predicted_y: i64 = 4,
    dx: i64 = 0, dy: i64 = 0, phase: i32 = 0, players: i64 = 0, gems: i64 = 0,
    deadline: i64 = 0, next_input: i64 = 0, received_at: i64 = 0, snapshots: i64 = 0, corrections: i64 = 0, history_peak: i64 = 0, demo: bool = false, failed: bool = false }
fn connect(port: i64, demo: bool = false) -> Client {
    let network = lab_net_line_client::connect(port); let now = clock_ns();
    Client { network: network, deadline: now + 3000000000, next_input: now, demo: demo, failed: network.code != 0 }
}
fn solo(demo: bool = false) -> Client {
    var c = Client { local: app_arena_game::create(), offline: true, peer: app_arena_game::Peer { 0, 1 }, phase: 1, next_input: clock_ns(), demo: demo };
    assert(app_arena_game::join(c.local, c.peer)); c.shown = app_arena_state::capture(c.local); c.previous = c.shown; c.snapshots = 1; c
}
fn uint(text: const u8[:]) -> u64, bool {
    var value: u64 = 0; if text.len == 0 || text.len > 20 { return 0, false; }
    for byte in text {
        if byte < '0' || byte > '9' { return 0, false; } let digit = (byte - '0') as u64;
        if value > (0xFFFFFFFFFFFFFFFF - digit) / 10 { return 0, false; } value = value * 10 + digit;
    } return value, true;
}
fn mine(c: const Client&) -> i64 {
    for p, i in c.shown.players { if p.peer.slot == c.peer.slot && p.peer.generation == c.peer.generation { return i; } } -1
}
fn paused(s: const app_arena_state::Snapshot&) -> bool { s.remaining > 0 || (s.versus && s.players.len < 2) }
fn publish(c: Client&) -> bool {
    var own: i64 = -1;
    for p, i in c.pending.players { if p.peer.slot == c.peer.slot && p.peer.generation == c.peer.generation { own = i; } }
    if own < 0 || c.pending.players.len != c.players || c.pending.gems.len != c.gems || c.pending.ticks < c.shown.ticks { return false; }
    let p = c.pending.players[own]; if p.acknowledged < c.acknowledged || p.acknowledged > c.sequence { return false; }
    var retained: app_arena_game::Input[..32] = [];
    for command in c.history { if command.sequence > p.acknowledged { retained.push(command); } }
    var x = p.x; var y = p.y;
    if !paused(c.pending) { for command in retained { x = clamp(x + command.dx, 0, 40); y = clamp(y + command.dy, 0, 24); } }
    if c.snapshots > 0 && (x != c.predicted_x || y != c.predicted_y) { c.corrections++; }
    c.history = retained; c.acknowledged = p.acknowledged; c.predicted_x = x; c.predicted_y = y;
    c.previous = c.shown; c.shown = c.pending; c.snapshots++; c.phase = 1; c.received_at = clock_ns(); c.deadline = c.received_at + 3000000000; true
}
fn unique(c: const Client&, slot: i64) -> bool {
    for p in c.pending.players { if p.id.slot == slot { return false; } }
    for gem in c.pending.gems { if gem.id.slot == slot { return false; } } true
}
fn consume(c: Client&, line: const u8[:]) -> bool {
    let fields = split(line, ' ');
    if c.phase == 0 {
        if fields.len != 4 || fields[0] != "WELCOME" || fields[1] != "2" { return false; }
        let slot, ok = parse_int(fields[2]); let generation, valid = uint(fields[3]);
        if !ok || slot < 0 || slot >= 8 || !valid || generation == 0 { return false; }
        c.peer = app_arena_game::Peer { slot, generation }; c.phase = 1; return true;
    }
    if c.phase == 1 {
        if fields.len != 11 || fields[0] != "FRAME" || fields[1] != "2" || fields[2] != "1" { return false; }
        var values: i64[11] = [0; 11];
        for i in 11 { if i <= 2 || i == 6 { continue; } let n, ok = parse_int(fields[i]); if !ok { return false; } values[i] = n; }
        let generation, valid = uint(fields[6]);
        if !valid || values[3] < 0 || values[4] < 1 || values[5] < -1 || values[5] >= 8 || (values[5] == -1) != (generation == 0) ||
            values[7] < 0 || values[7] > 60 || (values[7] > 0) != (values[5] >= 0) || values[8] < 0 || values[9] < 1 || values[9] > 8 || values[10] != 6 { return false; }
        c.pending = app_arena_state::Snapshot { versus: true, ticks: values[3], round: values[4], winner: app_arena_game::Peer { values[5], generation }, remaining: values[7], collected: values[8] };
        c.players = values[9]; c.gems = values[10]; c.phase = 2; return true;
    }
    if line == "END" { return publish(c); }
    if fields.len != 9 && fields.len != 5 { return false; }
    let slot, slot_ok = parse_int(fields[1]); let generation, gen_ok = uint(fields[2]);
    if !slot_ok || slot < 0 || slot >= 16 || !gen_ok || generation == 0 || !unique(c, slot) { return false; }
    let id = lab_ecs_pool::Id { slot, generation };
    if fields[0] == "PLAYER" && fields.len == 9 && c.pending.players.len < c.players {
        let peer_slot, peer_ok = parse_int(fields[3]); let peer_gen, peer_gen_ok = uint(fields[4]);
        let x, x_ok = parse_int(fields[5]); let y, y_ok = parse_int(fields[6]); let score, score_ok = parse_int(fields[7]); let ack, ack_ok = parse_int(fields[8]);
        if !peer_ok || peer_slot < 0 || peer_slot >= 8 || !peer_gen_ok || peer_gen == 0 || !x_ok || x < 0 || x > 40 || !y_ok || y < 0 || y > 24 ||
            !score_ok || score < 0 || score > 8 || !ack_ok || ack < 0 || ack > 1000000000 { return false; }
        for p in c.pending.players { if p.peer.slot == peer_slot { return false; } }
        c.pending.players.push(app_arena_state::Player { id, app_arena_game::Peer { peer_slot, peer_gen }, x, y, score, ack }); return true;
    }
    if fields[0] == "GEM" && fields.len == 5 && c.pending.gems.len < c.gems {
        let x, x_ok = parse_int(fields[3]); let y, y_ok = parse_int(fields[4]); if !x_ok || x < 0 || x > 40 || !y_ok || y < 0 || y > 24 { return false; }
        c.pending.gems.push(app_arena_state::Gem { id, x, y }); return true;
    } false
}
fn direction(c: Client&) {
    if !c.demo { return; }
    var distance: i64 = 1000; var x = c.predicted_x; var y = c.predicted_y;
    for gem in c.shown.gems {
        let d = abs(gem.x - c.predicted_x) + abs(gem.y - c.predicted_y);
        if d < distance { distance = d; x = gem.x; y = gem.y; }
    }
    c.dx = if x > c.predicted_x { 1 } else if x < c.predicted_x { -1 } else { 0 };
    c.dy = if y > c.predicted_y { 1 } else if y < c.predicted_y { -1 } else { 0 };
}
fn issue(c: Client&) -> bool {
    if c.history.len == 32 || c.sequence >= 1000000000 { c.failed = true; return false; }
    direction(c); let command = app_arena_game::Input { c.sequence + 1, c.dx, c.dy };
    if c.offline {
        assert(app_arena_game::input(c.local, c.peer, command) == 0); app_arena_game::tick(c.local);
        c.sequence++; c.acknowledged = c.sequence; c.previous = c.shown; c.shown = app_arena_state::capture(c.local); c.snapshots++; c.received_at = clock_ns();
        let own = mine(c); assert(own >= 0); c.predicted_x = c.shown.players[own].x; c.predicted_y = c.shown.players[own].y; return true;
    }
    let bytes = str("INPUT ", command.sequence, " ", command.dx, " ", command.dy);
    if !lab_net_line_client::send(c.network, bytes) { return false; }
    c.history.push(command); c.sequence++; c.history_peak = max(c.history_peak, c.history.len);
    if !paused(c.shown) { c.predicted_x = clamp(c.predicted_x + c.dx, 0, 40); c.predicted_y = clamp(c.predicted_y + c.dy, 0, 24); } true
}
fn poll(c: Client&) {
    if c.failed { return; }
    if !c.offline {
        lab_net_line_client::poll(c.network);
        loop { let line, complete = lab_net_line_client::line(c.network); if !complete { break; } if !consume(c, line) { c.failed = true; break; } }
        if c.failed || c.network.code != 0 || clock_ns() >= c.deadline { c.failed = true; return; }
    }
    let now = clock_ns(); if c.snapshots == 0 { return; }
    if now >= c.next_input {
        if issue(c) { c.next_input += 50000000; if now - c.next_input >= 200000000 { c.next_input = now + 50000000; } }
    }
}
fn destroy(c: Client&) { if !c.offline { lab_net_line_client::destroy(c.network); } }
