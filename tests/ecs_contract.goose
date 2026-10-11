import std;
import lab.ecs.pool;
import lab.ecs.sparse;
struct Payload { value: i64, tag: u8[..32] = "owned" }
fn main() {
    var invalid = lab_ecs_pool::create(0); let bad, invalid_code = lab_ecs_pool::acquire(invalid); assert(invalid_code == 1 && bad.slot == -1);
    for capacity in [3, 16, 64] {
        var pool = lab_ecs_pool::create(capacity); var store = lab_ecs_sparse::Store<Payload> {}; var numbers = lab_ecs_sparse::Store<i64> {};
        var alive: bool[64] = [false; 64]; var generations: u64[64] = [0; 64]; var values: i64[64] = [-1; 64]; var seed: u64 = 238147;
        for step in 3000 {
            seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
            let slot = ((seed >> 8) % (capacity as u64)) as i64; let choice = (seed >> 24) % 4;
            if choice == 0 {
                var expected: i64 = -1; for i in capacity { if !alive[i] { expected = i; break; } }
                let id, code = lab_ecs_pool::acquire(pool);
                assert(id.slot == expected && code == (if expected < 0 { 2 } else { 0 }));
                if expected >= 0 {
                    alive[expected] = true; generations[expected]++; values[expected] = -1; assert(id.generation == generations[expected]);
                    assert(!lab_ecs_sparse::lookup(store, pool, id));
                }
            } else {
                let id = lab_ecs_pool::Id { slot, generations[slot] };
                if choice == 1 {
                    let before = to_bytes([store]); let code = lab_ecs_sparse::put(store, pool, id, Payload { value: step });
                    assert(code == (if alive[slot] { 0 } else { 3 }));
                    if alive[slot] { values[slot] = step; assert(lab_ecs_sparse::put(numbers, pool, id, step) == 0); }
                    else { assert(to_bytes([store]) == before); }
                } else if choice == 2 {
                    assert(lab_ecs_pool::release(pool, id) == (if alive[slot] { 0 } else { 3 })); alive[slot] = false; values[slot] = -1;
                    // Retained stale rows must never be visible to a later generation.
                    assert(!lab_ecs_sparse::lookup(store, pool, id));
                } else {
                    let removed = lab_ecs_sparse::erase(store, id); if removed { values[slot] = -1; }
                }
            }
            if step % 17 == 0 { lab_ecs_sparse::prune(store, pool); lab_ecs_sparse::prune(numbers, pool); }
            lab_ecs_sparse::check(store.rows); lab_ecs_sparse::check(numbers.rows);
            var live: i64 = 0;
            for i in capacity {
                let id = lab_ecs_pool::Id { i, generations[i] }; assert(lab_ecs_pool::valid(pool, id) == alive[i]); if alive[i] { live++; }
                let found = lab_ecs_sparse::lookup(store, pool, id);
                if alive[i] && values[i] >= 0 { assert(found && found.value == values[i] && found.tag == "owned"); }
                else { assert(!found); }
            }
            assert(pool.live == live && store.rows.slots.len == store.values.len);
        }
        for slot in capacity { let id = lab_ecs_pool::id(pool, slot); if id.slot >= 0 { assert(lab_ecs_pool::release(pool, id) == 0); } }
        lab_ecs_sparse::prune(store, pool); lab_ecs_sparse::prune(numbers, pool); assert(store.values.len == 0 && numbers.values.len == 0);
    }
    print("Reusable ECS contract passed: 9000 operations");
}
