// Stable bounded entity identity. One owner coordinates component cleanup.
namespace lab_ecs_pool;
import std;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2; let STALE: i32 = 3;
struct Id { slot: i64 = -1, generation: u64 = 0 }
struct Entity { alive: bool = false, generation: u64 = 0 }
struct Pool { code: i32 = OK, capacity: i64 = 64, entities: Entity[64] = [Entity {}; 64], live: i64 = 0 }
fn create(capacity: i64 = 64) -> Pool {
    if capacity < 1 || capacity > 64 { return Pool { code: INVALID }; }
    Pool { capacity: capacity }
}
fn valid(p: const Pool&, id: Id) -> bool {
    p.code == OK && id.slot >= 0 && id.slot < p.capacity && p.entities[id.slot].alive && p.entities[id.slot].generation == id.generation
}
fn acquire(p: Pool&) -> Id, i32 {
    if p.code != OK { return Id {}, INVALID; }
    for slot in p.capacity {
        if !p.entities[slot].alive && p.entities[slot].generation != 0xFFFFFFFFFFFFFFFF {
            p.entities[slot].generation++; p.entities[slot].alive = true; p.live++;
            return Id { slot, p.entities[slot].generation }, OK;
        }
    }
    return Id {}, LIMIT;
}
// Remove all of this entity's components before releasing it. Pools are unrelated
// identity domains; a Store is paired with exactly one Pool by its owner.
fn release(p: Pool&, id: Id) -> i32 {
    if !valid(p, id) { return STALE; }
    p.entities[id.slot].alive = false; p.live--; OK
}
fn id(p: const Pool&, slot: i64) -> Id {
    if slot < 0 || slot >= p.capacity || !p.entities[slot].alive { return Id {}; }
    Id { slot, p.entities[slot].generation }
}
