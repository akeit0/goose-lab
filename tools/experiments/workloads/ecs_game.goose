import std;
import .world;
fn retirement_boundary() {
    var w = experiment_ecs::create(3); w.entities[0].generation = 0xFFFFFFFFFFFFFFFE;
    let last, code = experiment_ecs::spawn(w, 0, 0, 1, 0, true, 1, 5, 1);
    assert(code == 0 && last.slot == 0 && last.generation == 0xFFFFFFFFFFFFFFFF);
    assert(experiment_ecs::despawn(w, last) == 0);
    let first, a = experiment_ecs::spawn(w, 1, 2, 0, 0, false, 2, 10, 2);
    let second, b = experiment_ecs::spawn(w, 2, 3, 1, 0, true, 3, 20, 2);
    assert(a == 0 && b == 0 && first.slot == 1 && second.slot == 2);
    let image = to_bytes([w]);
    let full, limit = experiment_ecs::spawn(w, 0, 0, 0, 0, false, 1, 5, 1);
    let bad, invalid = experiment_ecs::spawn(w, -9223372036854775807 - 1, 0, 0, 0, false, 1, 5, 1);
    let velocity = experiment_ecs::set_velocity(w, first, true, -9223372036854775807 - 1, 0);
    let stale = experiment_ecs::despawn(w, last);
    assert(full.slot == -1 && bad.slot == -1 && to_bytes([w]) == image);
    assert(limit == experiment_ecs::LIMIT && invalid == experiment_ecs::INVALID && velocity == experiment_ecs::INVALID && stale == experiment_ecs::STALE);
    experiment_ecs::check(w);
    print("retired,", w.entities[0].generation, ",", limit, ",", invalid, ",", velocity, ",", stale, ",", w.spawns, ",", w.destroyed);
    print("boundary,", experiment_ecs::describe(w, first)); print("boundary,", experiment_ecs::describe(w, second));
    assert(experiment_ecs::despawn(w, first) == 0 && experiment_ecs::despawn(w, second) == 0); experiment_ecs::check(w);
}
fn main() {
    retirement_boundary();
    for capacity in [3, 16, 64] {
        for initial in [238147, 4294967294] {
            var w = experiment_ecs::create(capacity); var seed: u64 = initial as u64;
            // Guaranteed actual game event: moving bullet hits a target and both retire.
            let target, tc = experiment_ecs::spawn(w, 2, 0, 0, 0, false, 1, 20, 2);
            let bullet, bc = experiment_ecs::spawn(w, 0, 0, 1, 0, true, 1, 4, 1); assert(tc == 0 && bc == 0);
            experiment_ecs::tick(w); assert(w.score == 1 && w.collisions == 1 && !experiment_ecs::valid(w, target) && !experiment_ecs::valid(w, bullet));
            // Fill every slot, verify whole-world refusal, reuse an interior slot.
            for i in capacity { let id, code = experiment_ecs::spawn(w, i % 8, 3, 0, 0, false, 2, 128, 2); assert(code == 0); }
            let image = to_bytes([w]); let full, fc = experiment_ecs::spawn(w, 0, 0, 0, 0, false, 1, 5, 1);
            assert(fc == experiment_ecs::LIMIT && full.slot == -1 && to_bytes([w]) == image);
            let old = experiment_ecs::Id { 1, w.entities[1].generation }; assert(experiment_ecs::despawn(w, old) == 0);
            let fresh, rc = experiment_ecs::spawn(w, 7, 7, 1, 0, true, 3, 128, 2); assert(rc == 0 && fresh.slot == 1);
            let reused = to_bytes([w]); assert(experiment_ecs::set_velocity(w, old, true, 2, 0) == experiment_ecs::STALE && to_bytes([w]) == reused);
            for step in 400 {
                seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
                let slot = ((seed >> 8) % (capacity as u64)) as i64; let choice = ((seed >> 24) % 10) as i64;
                let id = experiment_ecs::Id { slot, w.entities[slot].generation };
                var code: i32 = 0; var created = experiment_ecs::Id {};
                if choice < 5 {
                    let next, result = experiment_ecs::spawn(w, ((seed >> 16) % 9) as i64 - 4, ((seed >> 12) % 9) as i64 - 4,
                        (seed % 5) as i64 - 2, ((seed >> 4) % 5) as i64 - 2, (seed & 1) != 0, (seed % 3) as i64 + 1, (seed % 15) as i64 + 1, (seed % 2) as i64 + 1);
                    created = next; code = result;
                } else if choice < 7 { code = experiment_ecs::despawn(w, id); }
                else { code = experiment_ecs::set_velocity(w, id, choice != 7, (seed % 5) as i64 - 2, ((seed >> 4) % 5) as i64 - 2); }
                experiment_ecs::tick(w); experiment_ecs::check(w);
                print("frame,", capacity, ",", initial, ",", step, ",", code, ",", created.slot, ",", created.generation, ",", w.position.slots.len,
                    ",", w.ticks, ",", w.spawns, ",", w.destroyed, ",", w.moves, ",", w.collisions, ",", w.score);
                for slot in capacity { if w.entities[slot].alive { print("entity,", experiment_ecs::describe(w, experiment_ecs::Id { slot, w.entities[slot].generation })); } }
            }
            for slot in capacity { if w.entities[slot].alive { assert(experiment_ecs::despawn(w, experiment_ecs::Id { slot, w.entities[slot].generation }) == 0); } }
            experiment_ecs::check(w); assert(w.position.slots.len == 0 && w.velocity.slots.len == 0 && w.health.slots.len == 0);
            print("empty,", capacity, ",", initial, ",", w.spawns, ",", w.destroyed);
        }
    }
    print("ECS game experiment passed");
}
