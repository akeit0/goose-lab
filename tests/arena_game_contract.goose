import std;
import arena.game;
import arena.state;
fn main() {
    var g = app_arena_game::create(true); let a = app_arena_game::Peer { 0, 1 }; let b = app_arena_game::Peer { 1, 1 };
    assert(app_arena_game::join(g, a)); assert(app_arena_game::input(g, a, app_arena_game::Input { 1, 1, 0 }) == 0);
    app_arena_game::tick(g); assert(app_arena_state::capture(g).players[0].x == 4);
    assert(app_arena_game::join(g, b));
    let aid = app_arena_game::player(g, a); let bid = app_arena_game::player(g, b);
    let old_gem = lab_ecs_pool::id(g.pool, 0);
    { let at .= app_arena_game::body(g, aid); at.x = 20; at.y = 3; }
    { let at .= app_arena_game::body(g, bid); at.x = 20; at.y = 3; }
    app_arena_game::tick(g); let s = app_arena_state::capture(g);
    assert(g.collected == 1 && s.players[0].score + s.players[1].score == 1 && !lab_ecs_pool::valid(g.pool, old_gem));
    for sequence in 8 { assert(app_arena_game::input(g, b, app_arena_game::Input { sequence + 1, -1, 0 }) == 0); }
    let image = to_bytes([g]);
    assert(app_arena_game::input(g, b, app_arena_game::Input { 9, -1, 0 }) == 1 && to_bytes([g]) == image);
    assert(app_arena_game::input(g, b, app_arena_game::Input { 1, 1, 1 }) == 0 && to_bytes([g]) == image);
    assert(app_arena_game::input(g, b, app_arena_game::Input { 9, -9223372036854775808, 0 }) == 1 && to_bytes([g]) == image);
    app_arena_game::leave(g, b); assert(app_arena_game::join(g, app_arena_game::Peer { 1, 2 }));
    let reused = to_bytes([g]); assert(!lab_ecs_pool::valid(g.pool, bid));
    assert(app_arena_game::input(g, b, app_arena_game::Input { 1, 1, 0 }) == 1 && to_bytes([g]) == reused);
    app_arena_game::leave(g, b); assert(to_bytes([g]) == reused);
    for slot in 6 { assert(app_arena_game::join(g, app_arena_game::Peer { slot + 2, 1 })); }
    assert(g.pool.live == 14); let full = to_bytes([g]); assert(!app_arena_game::join(g, app_arena_game::Peer { 8, 1 }) && to_bytes([g]) == full);
    lab_ecs_sparse::check(g.bodies.rows); lab_ecs_sparse::check(g.players.rows);
    print("Arena game contract passed: waiting, contested pickup, bounded inputs, player ownership and stale generations");
}
