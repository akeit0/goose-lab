// Bounded projectile arena: independent identity, dense SoA components, deferred deaths.
namespace experiment_ecs;
import std;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2; let STALE: i32 = 3;
struct Id { slot: i64 = -1, generation: u64 = 0 }
struct Entity { alive: bool = false, generation: u64 = 0 }
struct Position { slots: i64[..64] = [], x: i64[..64] = [], y: i64[..64] = [], sparse: i64[64] = [-1; 64] }
struct Velocity { slots: i64[..64] = [], x: i64[..64] = [], y: i64[..64] = [], sparse: i64[64] = [-1; 64] }
struct Health { slots: i64[..64] = [], hp: i64[..64] = [], ttl: i64[..64] = [], team: i64[..64] = [], sparse: i64[64] = [-1; 64] }
struct World {
    capacity: i64 = 64, entities: Entity[64] = [Entity {}; 64],
    position: Position = Position {}, velocity: Velocity = Velocity {}, health: Health = Health {},
    ticks: i64 = 0, spawns: i64 = 0, destroyed: i64 = 0, moves: i64 = 0, collisions: i64 = 0, score: i64 = 0,
}
fn create(capacity: i64 = 64) -> World { assert(capacity >= 1 && capacity <= 64); World { capacity: capacity } }
fn valid(w: const World&, id: Id) -> bool {
    id.slot >= 0 && id.slot < w.capacity && w.entities[id.slot].alive && w.entities[id.slot].generation == id.generation
}
fn set_velocity(w: World&, id: Id, enabled: bool, x: i64, y: i64) -> i32 {
    if !valid(w, id) { return STALE; }
    if x < -8 || x > 8 || y < -8 || y > 8 { return INVALID; }
    let v .= w.velocity; let row = v.sparse[id.slot];
    if enabled {
        if row >= 0 { v.x[row] = x; v.y[row] = y; }
        else { v.sparse[id.slot] = v.slots.len; v.slots.push(id.slot); v.x.push(x); v.y.push(y); }
    } else if row >= 0 {
        let last = v.slots.len - 1; let moved = v.slots[last];
        v.slots[row] = moved; v.x[row] = v.x[last]; v.y[row] = v.y[last]; v.sparse[moved] = row;
        v.slots.resize(last); v.x.resize(last); v.y.resize(last); v.sparse[id.slot] = -1;
    }
    OK
}
fn spawn(w: World&, x: i64, y: i64, vx: i64, vy: i64, moving: bool, hp: i64, ttl: i64, team: i64) -> Id, i32 {
    if x < -32 || x > 32 || y < -32 || y > 32 || vx < -8 || vx > 8 || vy < -8 || vy > 8 || hp < 1 || hp > 99 || ttl < 1 || ttl > 128 || team < 1 || team > 2 {
        return Id {}, INVALID;
    }
    var slot: i64 = -1;
    for i in w.capacity { if !w.entities[i].alive && w.entities[i].generation != 0xFFFFFFFFFFFFFFFF { slot = i; break; } }
    if slot < 0 { return Id {}, LIMIT; }
    let id = Id { slot, w.entities[slot].generation + 1 }; w.entities[slot] = Entity { true, id.generation };
    let p .= w.position; p.sparse[slot] = p.slots.len; p.slots.push(slot); p.x.push(x); p.y.push(y);
    let h .= w.health; h.sparse[slot] = h.slots.len; h.slots.push(slot); h.hp.push(hp); h.ttl.push(ttl); h.team.push(team);
    assert(set_velocity(w, id, moving, vx, vy) == OK); w.spawns++; return id, OK;
}
fn despawn(w: World&, id: Id) -> i32 {
    if !valid(w, id) { return STALE; }
    assert(set_velocity(w, id, false, 0, 0) == OK);
    let p .= w.position; let row = p.sparse[id.slot]; let last = p.slots.len - 1; let moved = p.slots[last];
    p.slots[row] = moved; p.x[row] = p.x[last]; p.y[row] = p.y[last]; p.sparse[moved] = row;
    p.slots.resize(last); p.x.resize(last); p.y.resize(last); p.sparse[id.slot] = -1;
    let h .= w.health; let hr = h.sparse[id.slot]; let hl = h.slots.len - 1; let hm = h.slots[hl];
    h.slots[hr] = hm; h.hp[hr] = h.hp[hl]; h.ttl[hr] = h.ttl[hl]; h.team[hr] = h.team[hl]; h.sparse[hm] = hr;
    h.slots.resize(hl); h.hp.resize(hl); h.ttl.resize(hl); h.team.resize(hl); h.sparse[id.slot] = -1;
    w.entities[id.slot].alive = false; w.destroyed++; OK
}
fn tick(w: World&) {
    var dead: bool[64] = [false; 64];
    // Intersection query: iterate dense Velocity, locate Position through its sparse map.
    for slot, row in w.velocity.slots {
        let p = w.position.sparse[slot]; assert(p >= 0);
        w.position.x[p] += w.velocity.x[row]; w.position.y[p] += w.velocity.y[row]; w.moves++;
    }
    for slot, row in w.health.slots {
        w.health.ttl[row]--; let p = w.position.sparse[slot];
        dead[slot] = w.health.ttl[row] == 0 || abs(w.position.x[p]) > 32 || abs(w.position.y[p]) > 32;
    }
    // Resolve collisions in logical slot order, independent of swap-removal order.
    for bullet in w.capacity {
        if !w.entities[bullet].alive || dead[bullet] { continue; }
        let bh = w.health.sparse[bullet]; if w.health.team[bh] != 1 { continue; }
        let bp = w.position.sparse[bullet];
        for target in w.capacity {
            if !w.entities[target].alive || dead[target] { continue; }
            let th = w.health.sparse[target]; if w.health.team[th] != 2 { continue; }
            let tp = w.position.sparse[target];
            if abs(w.position.x[bp] - w.position.x[tp]) <= 1 && abs(w.position.y[bp] - w.position.y[tp]) <= 1 {
                w.health.hp[th]--; dead[bullet] = true; w.collisions++;
                if w.health.hp[th] == 0 { dead[target] = true; w.score++; } break;
            }
        }
    }
    // Structural changes occur only after all component queries finish.
    for slot in w.capacity { if dead[slot] { assert(despawn(w, Id { slot, w.entities[slot].generation }) == OK); } }
    w.ticks++;
}
fn check(w: const World&) {
    let p .= w.position; let v .= w.velocity; let h .= w.health;
    assert(p.slots.len == p.x.len && p.x.len == p.y.len && h.slots.len == h.hp.len && h.hp.len == h.ttl.len && h.ttl.len == h.team.len);
    assert(v.slots.len == v.x.len && v.x.len == v.y.len && h.slots.len == p.slots.len);
    for slot in 64 {
        assert((p.sparse[slot] >= 0) == w.entities[slot].alive && (h.sparse[slot] >= 0) == w.entities[slot].alive);
        if w.entities[slot].alive {
            assert(p.slots[p.sparse[slot]] == slot && h.slots[h.sparse[slot]] == slot && h.hp[h.sparse[slot]] > 0);
        } else { assert(v.sparse[slot] == -1); }
        if v.sparse[slot] >= 0 { assert(v.slots[v.sparse[slot]] == slot); }
    }
    for slot, row in p.slots { assert(p.sparse[slot] == row); }
    for slot, row in h.slots { assert(h.sparse[slot] == row); }
    for slot, row in v.slots { assert(v.sparse[slot] == row); }
}
fn describe(w: const World&, id: Id) -> u8[>..] {
    if !valid(w, id) { return str("STALE"); }
    let p = w.position.sparse[id.slot]; let h = w.health.sparse[id.slot]; let v = w.velocity.sparse[id.slot];
    str(id.slot, ",", id.generation, ",", w.position.x[p], ",", w.position.y[p], ",", w.health.hp[h], ",", w.health.ttl[h], ",", w.health.team[h],
        ",", if v >= 0 { 1 } else { 0 }, ",", if v >= 0 { w.velocity.x[v] } else { 0 }, ",", if v >= 0 { w.velocity.y[v] } else { 0 })
}
