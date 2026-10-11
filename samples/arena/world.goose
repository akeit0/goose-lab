// Bounded projectile arena: independent identity, dense SoA components, deferred deaths.
namespace app_arena_world;
import lab.ecs.pool;
import lab.ecs.sparse;
import std;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2; let STALE: i32 = 3;
struct Position { rows: lab_ecs_sparse::Index = lab_ecs_sparse::Index {}, x: i64[..64] = [], y: i64[..64] = [] }
struct Velocity { rows: lab_ecs_sparse::Index = lab_ecs_sparse::Index {}, x: i64[..64] = [], y: i64[..64] = [] }
struct Health { rows: lab_ecs_sparse::Index = lab_ecs_sparse::Index {}, hp: i64[..64] = [], ttl: i64[..64] = [], team: i64[..64] = [] }
struct World {
    pool: lab_ecs_pool::Pool = lab_ecs_pool::Pool {},
    position: Position = Position {}, velocity: Velocity = Velocity {}, health: Health = Health {},
    ticks: i64 = 0, spawns: i64 = 0, destroyed: i64 = 0, moves: i64 = 0, collisions: i64 = 0, score: i64 = 0,
}
fn create(capacity: i64 = 64) -> World { assert(capacity >= 1 && capacity <= 64); World { pool: lab_ecs_pool::create(capacity) } }
fn valid(w: const World&, id: lab_ecs_pool::Id) -> bool { lab_ecs_pool::valid(w.pool, id) }
fn set_velocity(w: World&, id: lab_ecs_pool::Id, enabled: bool, x: i64, y: i64) -> i32 {
    if !valid(w, id) { return STALE; }
    if x < -8 || x > 8 || y < -8 || y > 8 { return INVALID; }
    let v .= w.velocity; let row = v.rows.sparse[id.slot];
    if enabled {
        if row >= 0 { v.x[row] = x; v.y[row] = y; }
        else { assert(lab_ecs_sparse::insert(v.rows, id.slot) == v.x.len); v.x.push(x); v.y.push(y); }
    } else if row >= 0 {
        let removed, last = lab_ecs_sparse::remove(v.rows, id.slot); assert(removed == row);
        v.x[row] = v.x[last]; v.y[row] = v.y[last]; v.x.resize(last); v.y.resize(last);
    }
    OK
}
fn spawn(w: World&, x: i64, y: i64, vx: i64, vy: i64, moving: bool, hp: i64, ttl: i64, team: i64) -> lab_ecs_pool::Id, i32 {
    if x < -32 || x > 32 || y < -32 || y > 32 || vx < -8 || vx > 8 || vy < -8 || vy > 8 || hp < 1 || hp > 99 || ttl < 1 || ttl > 128 || team < 1 || team > 2 {
        return lab_ecs_pool::Id {}, INVALID;
    }
    let id, code = lab_ecs_pool::acquire(w.pool); if code != OK { return id, code; }
    let slot = id.slot;
    let p .= w.position; assert(lab_ecs_sparse::insert(p.rows, slot) == p.x.len); p.x.push(x); p.y.push(y);
    let h .= w.health; assert(lab_ecs_sparse::insert(h.rows, slot) == h.hp.len); h.hp.push(hp); h.ttl.push(ttl); h.team.push(team);
    assert(set_velocity(w, id, moving, vx, vy) == OK); w.spawns++; return id, OK;
}
fn despawn(w: World&, id: lab_ecs_pool::Id) -> i32 {
    if !valid(w, id) { return STALE; }
    assert(set_velocity(w, id, false, 0, 0) == OK);
    let p .= w.position; let row, last = lab_ecs_sparse::remove(p.rows, id.slot); assert(row >= 0);
    p.x[row] = p.x[last]; p.y[row] = p.y[last]; p.x.resize(last); p.y.resize(last);
    let h .= w.health; let hr, hl = lab_ecs_sparse::remove(h.rows, id.slot); assert(hr >= 0);
    h.hp[hr] = h.hp[hl]; h.ttl[hr] = h.ttl[hl]; h.team[hr] = h.team[hl];
    h.hp.resize(hl); h.ttl.resize(hl); h.team.resize(hl);
    assert(lab_ecs_pool::release(w.pool, id) == OK); w.destroyed++; OK
}
fn tick(w: World&) {
    var dead: bool[64] = [false; 64];
    // Intersection query: iterate dense Velocity, locate Position through its sparse map.
    for slot, row in w.velocity.rows.slots {
        let p = w.position.rows.sparse[slot]; assert(p >= 0);
        w.position.x[p] += w.velocity.x[row]; w.position.y[p] += w.velocity.y[row]; w.moves++;
    }
    for slot, row in w.health.rows.slots {
        w.health.ttl[row]--; let p = w.position.rows.sparse[slot];
        dead[slot] = w.health.ttl[row] == 0 || abs(w.position.x[p]) > 32 || abs(w.position.y[p]) > 32;
    }
    // Resolve collisions in logical slot order, independent of swap-removal order.
    for bullet in w.pool.capacity {
        if !w.pool.entities[bullet].alive || dead[bullet] { continue; }
        let bh = w.health.rows.sparse[bullet]; if w.health.team[bh] != 1 { continue; }
        let bp = w.position.rows.sparse[bullet];
        for target in w.pool.capacity {
            if !w.pool.entities[target].alive || dead[target] { continue; }
            let th = w.health.rows.sparse[target]; if w.health.team[th] != 2 { continue; }
            let tp = w.position.rows.sparse[target];
            if abs(w.position.x[bp] - w.position.x[tp]) <= 1 && abs(w.position.y[bp] - w.position.y[tp]) <= 1 {
                w.health.hp[th]--; dead[bullet] = true; w.collisions++;
                if w.health.hp[th] == 0 { dead[target] = true; w.score++; } break;
            }
        }
    }
    // Structural changes occur only after all component queries finish.
    for slot in w.pool.capacity { if dead[slot] { assert(despawn(w, lab_ecs_pool::Id { slot, w.pool.entities[slot].generation }) == OK); } }
    w.ticks++;
}
fn check(w: const World&) {
    let p .= w.position; let v .= w.velocity; let h .= w.health;
    lab_ecs_sparse::check(p.rows); lab_ecs_sparse::check(v.rows); lab_ecs_sparse::check(h.rows);
    assert(w.pool.live == p.rows.slots.len);
    assert(p.rows.slots.len == p.x.len && p.x.len == p.y.len && h.rows.slots.len == h.hp.len && h.hp.len == h.ttl.len && h.ttl.len == h.team.len);
    assert(v.rows.slots.len == v.x.len && v.x.len == v.y.len && h.rows.slots.len == p.rows.slots.len);
    for slot in 64 {
        assert((p.rows.sparse[slot] >= 0) == w.pool.entities[slot].alive && (h.rows.sparse[slot] >= 0) == w.pool.entities[slot].alive);
        if w.pool.entities[slot].alive {
            assert(p.rows.slots[p.rows.sparse[slot]] == slot && h.rows.slots[h.rows.sparse[slot]] == slot && h.hp[h.rows.sparse[slot]] > 0);
        } else { assert(v.rows.sparse[slot] == -1); }
        if v.rows.sparse[slot] >= 0 { assert(v.rows.slots[v.rows.sparse[slot]] == slot); }
    }
    for slot, row in p.rows.slots { assert(p.rows.sparse[slot] == row); }
    for slot, row in h.rows.slots { assert(h.rows.sparse[slot] == row); }
    for slot, row in v.rows.slots { assert(v.rows.sparse[slot] == row); }
}
fn describe(w: const World&, id: lab_ecs_pool::Id) -> u8[>..] {
    if !valid(w, id) { return str("STALE"); }
    let p = w.position.rows.sparse[id.slot]; let h = w.health.rows.sparse[id.slot]; let v = w.velocity.rows.sparse[id.slot];
    str(id.slot, ",", id.generation, ",", w.position.x[p], ",", w.position.y[p], ",", w.health.hp[h], ",", w.health.ttl[h], ",", w.health.team[h],
        ",", if v >= 0 { 1 } else { 0 }, ",", if v >= 0 { w.velocity.x[v] } else { 0 }, ",", if v >= 0 { w.velocity.y[v] } else { 0 })
}
