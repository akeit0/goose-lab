// Fixed owned view values shared by offline capture and network parsing.
namespace app_arena_state;
import std;
import arena.game;
import lab.ecs.pool;
struct Player { id: lab_ecs_pool::Id, peer: app_arena_game::Peer, x: i64, y: i64, score: i64, acknowledged: i64 }
struct Gem { id: lab_ecs_pool::Id, x: i64, y: i64 }
struct Snapshot { versus: bool = false, ticks: i64 = 0, round: i64 = 1, winner: app_arena_game::Peer = app_arena_game::Peer {},
    remaining: i64 = 0, collected: i64 = 0, players: Player[..8] = [], gems: Gem[..6] = [] }
fn capture(g: const app_arena_game::Game&) -> Snapshot {
    var s = Snapshot { versus: g.versus, ticks: g.ticks, round: g.round, winner: g.winner, remaining: g.remaining, collected: g.collected };
    for slot in g.pool.capacity {
        if !g.pool.entities[slot].alive { continue; }
        let id = lab_ecs_pool::id(g.pool, slot); let row = g.bodies.rows.sparse[slot]; let b .= g.bodies.values[row];
        if b.kind == 2 { s.gems.push(Gem { id, b.x, b.y }); }
        else { let p .= g.players.values[g.players.rows.sparse[slot]]; s.players.push(Player { id, p.peer, b.x, b.y, p.score, p.acknowledged }); }
    } s
}
