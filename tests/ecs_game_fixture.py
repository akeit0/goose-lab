"""Independent dictionary-based projectile game, without dense/sparse storage."""
import subprocess
import sys


class World:
    def __init__(self, capacity):
        self.capacity = capacity
        self.generations = [0] * capacity
        self.entities = {}
        self.ticks = self.spawns = self.destroyed = self.moves = self.collisions = self.score = 0

    def spawn(self, x, y, vx, vy, moving, hp, ttl, team):
        if not (abs(x) <= 32 and abs(y) <= 32 and -8 <= vx <= 8 and -8 <= vy <= 8 and 1 <= hp <= 99 and 1 <= ttl <= 128 and team in (1, 2)):
            return (-1, 0), 1
        slot = next((s for s in range(self.capacity) if s not in self.entities and self.generations[s] < (1 << 64) - 1), None)
        if slot is None:
            return (-1, 0), 2
        self.generations[slot] += 1
        self.entities[slot] = dict(x=x, y=y, velocity=(vx, vy) if moving else None, hp=hp, ttl=ttl, team=team)
        self.spawns += 1
        return (slot, self.generations[slot]), 0

    def valid(self, identity):
        slot, generation = identity
        return slot in self.entities and self.generations[slot] == generation

    def despawn(self, identity):
        if not self.valid(identity):
            return 3
        del self.entities[identity[0]]
        self.destroyed += 1
        return 0

    def velocity(self, identity, enabled, x, y):
        if not self.valid(identity):
            return 3
        if not (-8 <= x <= 8 and -8 <= y <= 8):
            return 1
        self.entities[identity[0]]["velocity"] = (x, y) if enabled else None
        return 0

    def tick(self):
        survivors = {}
        for slot, e in self.entities.items():
            if e["velocity"] is not None:
                e["x"] += e["velocity"][0]; e["y"] += e["velocity"][1]; self.moves += 1
            e["ttl"] -= 1
            if e["ttl"] and abs(e["x"]) <= 32 and abs(e["y"]) <= 32:
                survivors[slot] = e
        # Reference model removes objects from a snapshot of survivors, rather than
        # traversing component storage or recording a deferred destruction bitmap.
        for bullet in sorted(list(survivors)):
            if bullet not in survivors or survivors[bullet]["team"] != 1:
                continue
            b = survivors[bullet]
            victim = next((s for s, e in sorted(survivors.items()) if e["team"] == 2 and abs(b["x"]-e["x"]) <= 1 and abs(b["y"]-e["y"]) <= 1), None)
            if victim is not None:
                survivors[victim]["hp"] -= 1; self.collisions += 1
                if survivors[victim]["hp"] == 0:
                    del survivors[victim]; self.score += 1
                del survivors[bullet]
        self.destroyed += len(self.entities) - len(survivors)
        self.entities = survivors
        self.ticks += 1

    def describe(self, identity):
        if not self.valid(identity):
            return "STALE"
        slot, generation = identity; e = self.entities[slot]
        vx, vy = e["velocity"] or (0, 0)
        return ",".join(map(str, (slot, generation, e["x"], e["y"], e["hp"], e["ttl"], e["team"], int(e["velocity"] is not None), vx, vy)))


def expected():
    w = World(3); w.generations[0] = (1 << 64) - 2
    last, code = w.spawn(0, 0, 1, 0, True, 1, 5, 1)
    assert code == 0 and last == (0, (1 << 64) - 1)
    w.despawn(last)
    first, _ = w.spawn(1, 2, 0, 0, False, 2, 10, 2)
    second, _ = w.spawn(2, 3, 1, 0, True, 3, 20, 2)
    _, limit = w.spawn(0, 0, 0, 0, False, 1, 5, 1)
    _, invalid = w.spawn(-(1 << 63), 0, 0, 0, False, 1, 5, 1)
    velocity = w.velocity(first, True, -(1 << 63), 0); stale = w.despawn(last)
    rows = [f"retired,{w.generations[0]},{limit},{invalid},{velocity},{stale},{w.spawns},{w.destroyed}",
            "boundary," + w.describe(first), "boundary," + w.describe(second)]
    for capacity in (3, 16, 64):
        for initial in (238147, 4294967294):
            w = World(capacity); seed = initial
            w.spawn(2, 0, 0, 0, False, 1, 20, 2); w.spawn(0, 0, 1, 0, True, 1, 4, 1); w.tick()
            assert w.score == w.collisions == 1 and not w.entities
            for i in range(capacity): w.spawn(i % 8, 3, 0, 0, False, 2, 128, 2)
            assert w.spawn(0, 0, 0, 0, False, 1, 5, 1) == ((-1, 0), 2)
            old = (1, w.generations[1]); w.despawn(old); w.spawn(7, 7, 1, 0, True, 3, 128, 2)
            assert w.velocity(old, True, 2, 0) == 3
            for step in range(400):
                seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
                slot, choice = (seed >> 8) % capacity, (seed >> 24) % 10
                identity = (slot, w.generations[slot]); created = (-1, 0)
                if choice < 5:
                    created, code = w.spawn((seed >> 16) % 9-4, (seed >> 12) % 9-4, seed % 5-2, (seed >> 4) % 5-2, bool(seed & 1), seed % 3+1, seed % 15+1, seed % 2+1)
                elif choice < 7:
                    code = w.despawn(identity)
                else:
                    code = w.velocity(identity, choice != 7, seed % 5-2, (seed >> 4) % 5-2)
                w.tick()
                rows.append(",".join(map(str, ("frame", capacity, initial, step, code, *created, len(w.entities), w.ticks, w.spawns, w.destroyed, w.moves, w.collisions, w.score))))
                rows.extend("entity," + w.describe((s, w.generations[s])) for s in sorted(w.entities))
            for slot in list(w.entities): w.despawn((slot, w.generations[slot]))
            rows.append(f"empty,{capacity},{initial},{w.spawns},{w.destroyed}")
    return rows + ["ECS game experiment passed"]


def validate(stdout):
    actual, wanted = stdout.splitlines(), expected()
    if actual != wanted:
        mismatch = next((i for i, pair in enumerate(zip(actual, wanted)) if pair[0] != pair[1]), min(len(actual), len(wanted)))
        raise AssertionError(f"Game differs at row {mismatch}: {actual[mismatch:mismatch+1]} expected {wanted[mismatch:mismatch+1]}")
    return {"frames": 2400, "entity_rows": sum(s.startswith("entity,") for s in actual), "rows": len(actual)}


def run(binary):
    process = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
    if process.returncode:
        print(process.stdout[-2000:]); print(process.stderr, file=sys.stderr); process.check_returncode()
    metrics = validate(process.stdout)
    for damaged in (process.stdout.replace("entity,0,", "entity,1,", 1), "\n".join(process.stdout.splitlines()[:-1])):
        try: validate(damaged)
        except AssertionError: pass
        else: raise AssertionError("Game oracle accepted a damaged trace")
    print(f"ECS game: {metrics}")
    return process, metrics


if __name__ == "__main__":
    run(sys.argv[1])
