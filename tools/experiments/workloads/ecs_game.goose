import std;
import arena.world;
import lab.ecs.pool;
fn retirement_boundary() {
    var w = app_arena_world::create(3); w.pool.entities[0].generation = 0xFFFFFFFFFFFFFFFE;
    let last, code = app_arena_world::spawn(w, 0, 0, 1, 0, true, 1, 5, 1);
    assert(code == 0 && last.slot == 0 && last.generation == 0xFFFFFFFFFFFFFFFF);
    assert(app_arena_world::despawn(w, last) == 0);
    let first, a = app_arena_world::spawn(w, 1, 2, 0, 0, false, 2, 10, 2);
    let second, b = app_arena_world::spawn(w, 2, 3, 1, 0, true, 3, 20, 2);
    assert(a == 0 && b == 0 && first.slot == 1 && second.slot == 2);
    let image = to_bytes([w]);
    let full, limit = app_arena_world::spawn(w, 0, 0, 0, 0, false, 1, 5, 1);
    let bad, invalid = app_arena_world::spawn(w, -9223372036854775807 - 1, 0, 0, 0, false, 1, 5, 1);
    let velocity = app_arena_world::set_velocity(w, first, true, -9223372036854775807 - 1, 0);
    let stale = app_arena_world::despawn(w, last);
    assert(full.slot == -1 && bad.slot == -1 && to_bytes([w]) == image);
    assert(limit == app_arena_world::LIMIT && invalid == app_arena_world::INVALID && velocity == app_arena_world::INVALID && stale == app_arena_world::STALE);
    app_arena_world::check(w);
    print("retired,", w.pool.entities[0].generation, ",", limit, ",", invalid, ",", velocity, ",", stale, ",", w.spawns, ",", w.destroyed);
    print("boundary,", app_arena_world::describe(w, first)); print("boundary,", app_arena_world::describe(w, second));
    assert(app_arena_world::despawn(w, first) == 0 && app_arena_world::despawn(w, second) == 0); app_arena_world::check(w);
}
fn main() {
    retirement_boundary();
    for capacity in [3, 16, 64] {
        for initial in [238147, 4294967294] {
            var w = app_arena_world::create(capacity); var seed: u64 = initial as u64;
            // Guaranteed actual game event: moving bullet hits a target and both retire.
            let target, tc = app_arena_world::spawn(w, 2, 0, 0, 0, false, 1, 20, 2);
            let bullet, bc = app_arena_world::spawn(w, 0, 0, 1, 0, true, 1, 4, 1); assert(tc == 0 && bc == 0);
            app_arena_world::tick(w); assert(w.score == 1 && w.collisions == 1 && !app_arena_world::valid(w, target) && !app_arena_world::valid(w, bullet));
            // Fill every slot, verify whole-world refusal, reuse an interior slot.
            for i in capacity { let id, code = app_arena_world::spawn(w, i % 8, 3, 0, 0, false, 2, 128, 2); assert(code == 0); }
            let image = to_bytes([w]); let full, fc = app_arena_world::spawn(w, 0, 0, 0, 0, false, 1, 5, 1);
            assert(fc == app_arena_world::LIMIT && full.slot == -1 && to_bytes([w]) == image);
            let old = lab_ecs_pool::Id { 1, w.pool.entities[1].generation }; assert(app_arena_world::despawn(w, old) == 0);
            let fresh, rc = app_arena_world::spawn(w, 7, 7, 1, 0, true, 3, 128, 2); assert(rc == 0 && fresh.slot == 1);
            let reused = to_bytes([w]); assert(app_arena_world::set_velocity(w, old, true, 2, 0) == app_arena_world::STALE && to_bytes([w]) == reused);
            for step in 400 {
                seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
                let slot = ((seed >> 8) % (capacity as u64)) as i64; let choice = ((seed >> 24) % 10) as i64;
                let id = lab_ecs_pool::Id { slot, w.pool.entities[slot].generation };
                var code: i32 = 0; var created = lab_ecs_pool::Id {};
                if choice < 5 {
                    let next, result = app_arena_world::spawn(w, ((seed >> 16) % 9) as i64 - 4, ((seed >> 12) % 9) as i64 - 4,
                        (seed % 5) as i64 - 2, ((seed >> 4) % 5) as i64 - 2, (seed & 1) != 0, (seed % 3) as i64 + 1, (seed % 15) as i64 + 1, (seed % 2) as i64 + 1);
                    created = next; code = result;
                } else if choice < 7 { code = app_arena_world::despawn(w, id); }
                else { code = app_arena_world::set_velocity(w, id, choice != 7, (seed % 5) as i64 - 2, ((seed >> 4) % 5) as i64 - 2); }
                app_arena_world::tick(w); app_arena_world::check(w);
                print("frame,", capacity, ",", initial, ",", step, ",", code, ",", created.slot, ",", created.generation, ",", w.position.rows.slots.len,
                    ",", w.ticks, ",", w.spawns, ",", w.destroyed, ",", w.moves, ",", w.collisions, ",", w.score);
                for slot in capacity { if w.pool.entities[slot].alive { print("entity,", app_arena_world::describe(w, lab_ecs_pool::Id { slot, w.pool.entities[slot].generation })); } }
            }
            for slot in capacity { if w.pool.entities[slot].alive { assert(app_arena_world::despawn(w, lab_ecs_pool::Id { slot, w.pool.entities[slot].generation }) == 0); } }
            app_arena_world::check(w); assert(w.position.rows.slots.len == 0 && w.velocity.rows.slots.len == 0 && w.health.rows.slots.len == 0);
            print("empty,", capacity, ",", initial, ",", w.spawns, ",", w.destroyed);
        }
    }
    print("ECS game experiment passed");
}
