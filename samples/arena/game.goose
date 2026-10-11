// Application policy: target waves, co-op shots and authoritative simulation.
namespace app_arena_game;
import std;
import arena.world;
import lab.ecs.pool;
import lab.net.line_server;
struct Game { world: app_arena_world::World = app_arena_world::World {}, misses: i64 = 0, shots: i64 = 0, wave: i64 = 0 }
fn create() -> Game {
    var g = Game { world: app_arena_world::create(16) };
    for y in [-8, 0, 8] { let id, code = app_arena_world::spawn(g.world, -16, y, 1, 0, true, 1, 64, 2); assert(code == 0); }
    g
}
fn clear(g: Game&) {
    for slot in g.world.pool.capacity {
        let id = lab_ecs_pool::id(g.world.pool, slot); if id.slot >= 0 { assert(app_arena_world::despawn(g.world, id) == 0); }
    }
}
fn reset(g: Game&) {
    // Preserve identity generations across resets so previous entity IDs stay stale.
    clear(g); g.world.ticks = 0; g.world.spawns = 0; g.world.destroyed = 0; g.world.moves = 0; g.world.collisions = 0; g.world.score = 0;
    g.misses = 0; g.shots = 0; g.wave = 0;
    for y in [-8, 0, 8] { let id, code = app_arena_world::spawn(g.world, -16, y, 1, 0, true, 1, 64, 2); assert(code == 0); }
}
fn tick(g: Game&) {
    if g.misses >= 5 { return; }
    let w .= g.world;
    for slot, row in w.health.rows.slots {
        let p = w.position.rows.sparse[slot]; let v = w.velocity.rows.sparse[slot];
        if w.health.team[row] == 2 && (w.health.ttl[row] == 1 || (v >= 0 && w.position.x[p] + w.velocity.x[v] > 32)) { g.misses++; }
    }
    app_arena_world::tick(w);
    if w.ticks % 8 == 0 {
        let lanes = [-16, -8, 0, 8, 16]; let y = lanes[g.wave % 5]; g.wave++;
        let id, code = app_arena_world::spawn(w, -24, y, 1, 0, true, 1, 64, 2); assert(code == 0 || code == 2);
    }
    app_arena_world::check(w);
}
fn snapshot(g: const Game&) -> u8[>..] {
    var out: u8[>..] = []; let w .= g.world;
    format(out, "FRAME ", w.ticks, " ", w.score, " ", g.misses, " ", g.shots, " ", w.pool.live, "\n");
    for slot in w.pool.capacity { if w.pool.entities[slot].alive { format(out, "ENTITY ", app_arena_world::describe(w, lab_ecs_pool::id(w.pool, slot)), "\n"); } }
    out.append("END\n"); assert(out.len <= 2048); out
}
fn route(g: Game&, line: const u8[:], manual: bool = false) -> lab_net_line_server::Reply {
    if line == "PING" { return lab_net_line_server::Reply { bytes: str("PONG\n") }; }
    if line == "SNAPSHOT" { return lab_net_line_server::Reply { bytes: snapshot(g) }; }
    if line == "RESET" { reset(g); return lab_net_line_server::Reply { bytes: str("RESET\n") }; }
    if line == "CLOSE" { return lab_net_line_server::Reply { action: lab_net_line_server::CLOSE, bytes: str("BYE\n") }; }
    if line == "SHUTDOWN" { return lab_net_line_server::Reply { action: lab_net_line_server::STOP, bytes: str("BYE\n") }; }
    let fields = split(line, ' ');
    if fields.len == 2 && fields[0] == "FIRE" {
        let y, ok = parse_int(fields[1]); if !ok || y < -20 || y > 20 || g.misses >= 5 { return lab_net_line_server::Reply { bytes: str("ERR aim\n") }; }
        let id, code = app_arena_world::spawn(g.world, 28, y, -3, 0, true, 1, 40, 1);
        if code != 0 { return lab_net_line_server::Reply { bytes: str("ERR capacity\n") }; }
        g.shots++; return lab_net_line_server::Reply { bytes: str("FIRED ", id.slot, " ", id.generation, "\n") };
    }
    if manual && fields.len == 2 && fields[0] == "STEP" {
        let count, ok = parse_int(fields[1]); if ok && count >= 1 && count <= 32 { for i in count { tick(g); } return lab_net_line_server::Reply { bytes: str("STEPPED\n") }; }
    }
    lab_net_line_server::Reply { bytes: str("ERR command\n") }
}
