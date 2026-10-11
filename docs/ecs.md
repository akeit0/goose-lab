# Bounded ECS identity and components

`lab.ecs.pool` and `lab.ecs.sparse` are pure Goose primitives. They contain no
position, damage, score, simulation clock, rendering or network policy. The
[arena sample](apps/arena.md) supplies those rules.

[`Pool`](../lib/lab/ecs/pool.goose) has 1..64 logical slots, generation-checked
`Id { slot, generation }`, and a live count. `create` reports INVALID for an
unsupported capacity. `acquire` returns an ID and OK, or an invalid ID and LIMIT.
`release`/`valid` reject stale IDs. A slot reaching `u64::MAX` retires after release
rather than wrapping. Capacity/stale refusal preserves state.

The caller owns a Pool and its component stores together. Remove components
before releasing an entity. Pools are separate identity domains; an ID does not
encode a Pool's address. Pair each store with one specific Pool. Exposed fields
are implementation state; boundary tests deliberately seed unreachable counters.

[`Index`](../lib/lab/ecs/sparse.goose) maps a logical slot to a dense row in O(1).
`insert` returns the existing/new row. `remove` returns the removed row and former
last row, swaps the last logical slot into the hole, and repairs the sparse map.
The owner applies that same swap/truncation to every parallel column. `check`
verifies both map directions. This supports SoA without prescribing a schema:
the arena's Position, Velocity and Health each own an Index and separate columns.

`Store<T>` offers an AoS alternative with owned fixed-size values. `put` validates
the ID against its Pool. `lookup` returns an optional borrowed value and checks
both Pool liveness and stored generation. `erase` matches stored generation, so
an old ID cannot erase a newer value. `prune` removes rows whose IDs are no longer
live. A retained old row is invisible after release/reuse, even before cleanup.
Use erase for normal teardown; prune is a recovery operation, not a collector.

```goose
import lab.ecs.pool;
import lab.ecs.sparse;
struct Counter { value: i64 }
var entities = lab_ecs_pool::create(16);
var counters = lab_ecs_sparse::Store<Counter> {};
let id, code = lab_ecs_pool::acquire(entities);
assert(code == 0);
assert(lab_ecs_sparse::put(counters, entities, id, Counter { 42 }) == 0);
assert(lab_ecs_sparse::erase(counters, id));
assert(lab_ecs_pool::release(entities, id) == 0);
```

Row references borrow their owner and must not survive structural operations or
teardown. Store<T> reserves 64 fixed rows and expects fixed-size T. Entity-wide
teardown and deferred structural changes are application policy.

The [contract](../tests/ecs_contract.goose) compares 9000 operations at 3/16/64
capacity with flat live/generation/value tables, instantiates two Store types,
and checks stale visibility, unchanged refusals and cleanup. The arena experiment
also compares complete game states with an independent Python dictionary model.
