// Pure application simulation, shared by offline practice and network matches.
namespace app_arena_game;
import std;
import lab.ecs.pool;
import lab.ecs.sparse;
struct Peer { slot: i64 = -1, generation: u64 = 0 }
struct Input { sequence: i64, dx: i64, dy: i64 }
struct Body { x: i64, y: i64, kind: i32 }
struct Player { peer: Peer, score: i64 = 0, acknowledged: i64 = 0, received: i64 = 0, inputs: Input[..8] = [] }
struct Game { pool: lab_ecs_pool::Pool = lab_ecs_pool::Pool { capacity: 16 }, bodies: lab_ecs_sparse::Store<Body> = lab_ecs_sparse::Store<Body> {},
    players: lab_ecs_sparse::Store<Player> = lab_ecs_sparse::Store<Player> {}, versus: bool = false,
    ticks: i64 = 0, revision: i64 = 0, round: i64 = 1, winner: Peer = Peer {}, remaining: i64 = 0, collected: i64 = 0 }
fn body(g: Game&, id: lab_ecs_pool::Id) -> Body& {
    let found = lab_ecs_sparse::lookup(g.bodies, g.pool, id); assert(found); found
}
fn spawn(g: Game&, x: i64, y: i64, kind: i32) -> lab_ecs_pool::Id {
    let id, code = lab_ecs_pool::acquire(g.pool); assert(code == 0);
    assert(lab_ecs_sparse::put(g.bodies, g.pool, id, Body { x, y, kind }) == 0); id
}
fn erase(g: Game&, id: lab_ecs_pool::Id) {
    assert(lab_ecs_sparse::erase(g.bodies, id)); assert(lab_ecs_pool::release(g.pool, id) == 0);
}
fn seed(g: Game&) { for y in [3, 7, 11, 15, 19, 23] { let id = spawn(g, 20, y, 2); } }
fn create(versus: bool = false) -> Game { var g = Game { versus: versus }; seed(g); g }
fn player(g: const Game&, peer: Peer) -> lab_ecs_pool::Id {
    for slot, row in g.players.rows.slots {
        let p .= g.players.values[row]; if p.peer.slot == peer.slot && p.peer.generation == peer.generation { return lab_ecs_pool::id(g.pool, slot); }
    } lab_ecs_pool::Id {}
}
fn join(g: Game&, peer: Peer) -> bool {
    if peer.slot < 0 || peer.slot >= 8 || peer.generation == 0 || player(g, peer).slot >= 0 { return false; }
    var old = Peer {};
    for p in g.players.values { if p.peer.slot == peer.slot { if p.peer.generation >= peer.generation { return false; } old = p.peer; break; } }
    if old.slot >= 0 { leave(g, old); }
    let id = spawn(g, if peer.slot % 2 == 0 { 4 } else { 36 }, 4 + (peer.slot / 2) * 5, 1);
    assert(lab_ecs_sparse::put(g.players, g.pool, id, Player { peer: peer }) == 0); g.revision++; true
}
fn leave(g: Game&, peer: Peer) {
    let id = player(g, peer); if id.slot < 0 { return; }
    assert(lab_ecs_sparse::erase(g.players, id)); erase(g, id); g.revision++;
}
// One numbered movement step per tick, at most eight queued. Old inputs are
// harmless duplicates; gaps, invalid axes and excess demand refuse unchanged.
fn input(g: Game&, peer: Peer, command: Input) -> i32 {
    let id = player(g, peer); if id.slot < 0 { return 1; }
    if command.sequence < 1 || command.sequence > 1000000000 || command.dx < -1 || command.dx > 1 || command.dy < -1 || command.dy > 1 { return 1; }
    let p = lab_ecs_sparse::lookup(g.players, g.pool, id); assert(p);
    if command.sequence <= p.received { return 0; }
    if command.sequence != p.received + 1 || p.inputs.len == 8 { return 1; }
    p.inputs.push(command); p.received = command.sequence; 0
}
fn reset_round(g: Game&) {
    // Identities, ticks and input acknowledgements survive round changes.
    g.round++; g.winner = Peer {}; g.remaining = 0;
    for slot, row in g.players.rows.slots {
        let p .= g.players.values[row]; p.score = 0;
        let b .= body(g, lab_ecs_pool::id(g.pool, slot)); b.x = if p.peer.slot % 2 == 0 { 4 } else { 36 }; b.y = 4 + (p.peer.slot / 2) * 5;
    }
    var gems: lab_ecs_pool::Id[..6] = [];
    for slot in g.pool.capacity { if g.pool.entities[slot].alive && g.bodies.values[g.bodies.rows.sparse[slot]].kind == 2 { gems.push(lab_ecs_pool::id(g.pool, slot)); } }
    for id in gems { erase(g, id); } seed(g);
}
fn tick(g: Game&) {
    g.ticks++; g.revision++; let waiting = g.versus && g.players.values.len < 2; let paused = g.remaining > 0 || waiting;
    for slot, row in g.players.rows.slots {
        let p .= g.players.values[row];
        if p.inputs.len > 0 {
            let command = p.inputs[0]; for i in p.inputs.len - 1 { p.inputs[i] = p.inputs[i + 1]; } p.inputs.resize(p.inputs.len - 1);
            p.acknowledged = command.sequence;
            if !paused { let b .= body(g, lab_ecs_pool::id(g.pool, slot)); b.x = clamp(b.x + command.dx, 0, 40); b.y = clamp(b.y + command.dy, 0, 24); }
        }
    }
    if g.remaining > 0 { g.remaining--; if g.remaining == 0 { reset_round(g); } return; }
    if waiting { return; }
    // Contested pickups rotate peer priority each tick. A gem is collected once;
    // respawn is a structural change after all reads of that body.
    var gems: lab_ecs_pool::Id[..6] = [];
    for slot in g.pool.capacity { if g.pool.entities[slot].alive && g.bodies.values[g.bodies.rows.sparse[slot]].kind == 2 { gems.push(lab_ecs_pool::id(g.pool, slot)); } }
    for gem in gems {
        var winner = Peer {}; let at = body(g, gem); let gx = at.x; let gy = at.y;
        for offset in 8 {
            let peer_slot = (g.ticks + offset) % 8;
            for slot, row in g.players.rows.slots {
                let p .= g.players.values[row]; if p.peer.slot != peer_slot { continue; }
                let b = body(g, lab_ecs_pool::id(g.pool, slot));
                if abs(b.x - gx) <= 1 && abs(b.y - gy) <= 1 { winner = p.peer; break; }
            }
            if winner.slot >= 0 { break; }
        }
        if winner.slot >= 0 {
            let pid = player(g, winner); let p = lab_ecs_sparse::lookup(g.players, g.pool, pid); assert(p); p.score++; g.collected++;
            let won = p.score >= 8; erase(g, gem);
            let id = spawn(g, 8 + ((g.collected * 11) % 25), 3 + ((g.collected * 7) % 19), 2);
            if won { g.winner = winner; g.remaining = 60; break; }
        }
    }
}
