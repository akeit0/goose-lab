"""Two real peers compare the sample's authoritative world to an independent model."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from arena import server
from ecs_game_fixture import World
from server_experiment_fixture import Client


class Game:
    def __init__(self):
        self.world = World(16); self.misses = self.shots = self.wave = 0; self.initial()

    def initial(self):
        for y in (-8, 0, 8): assert self.world.spawn(-16, y, 1, 0, True, 1, 64, 2)[1] == 0

    def tick(self):
        if self.misses >= 5: return
        self.misses += sum(e["team"] == 2 and (e["ttl"] == 1 or e["x"] + e["velocity"][0] > 32) for e in self.world.entities.values())
        self.world.tick()
        if self.world.ticks % 8 == 0:
            y = (-16, -8, 0, 8, 16)[self.wave % 5]; self.wave += 1
            self.world.spawn(-24, y, 1, 0, True, 1, 64, 2)

    def snapshot(self):
        w = self.world
        lines = [f"FRAME {w.ticks} {w.score} {self.misses} {self.shots} {len(w.entities)}\n".encode()]
        lines += [f"ENTITY {w.describe((slot,w.generations[slot]))}\n".encode() for slot in sorted(w.entities)]
        return lines + [b"END\n"]


def main():
    checks = 0
    with server(Path(sys.argv[1]).resolve(), manual=True) as (port, output):
        a, b = Client(port), Client(port); game = Game()
        try:
            assert a.line() == b"HELLO 0 1\n" and b.line() == b"HELLO 1 1\n"

            def request(peer, command, wanted):
                nonlocal checks
                peer.send(command); assert peer.line() == wanted; checks += 1

            def snapshot(peer):
                nonlocal checks
                peer.send(b"SNAPSHOT\n")
                for wanted in game.snapshot(): assert peer.line() == wanted; checks += 1

            snapshot(a); snapshot(b)
            b.send(b"FIR"); b.quiet()
            request(a, b"STEP 1\n", b"STEPPED\n"); game.tick(); snapshot(a)
            b.send(b"E 0\n"); identity, code = game.world.spawn(28, 0, -3, 0, True, 1, 40, 1); assert code == 0; game.shots += 1
            assert b.line() == f"FIRED {identity[0]} {identity[1]}\n".encode(); checks += 1
            for tick in range(80):
                peer = a if tick % 2 else b
                if tick % 4 == 0:
                    victim = next((e for e in game.world.entities.values() if e["team"] == 2), None)
                    if victim:
                        identity, code = game.world.spawn(28, victim["y"], -3, 0, True, 1, 40, 1)
                        wanted = b"ERR capacity\n" if code else f"FIRED {identity[0]} {identity[1]}\n".encode()
                        if not code: game.shots += 1
                        request(peer, f"FIRE {victim['y']}\n".encode(), wanted)
                request(a, b"STEP 1\n", b"STEPPED\n"); game.tick(); snapshot(a); snapshot(b)
            assert game.world.score > 0
            before = game.snapshot()
            for bad in (b"FIRE -9223372036854775808\n", b"FIRE 21\n", b"FIRE nope\n"):
                request(b, bad, b"ERR aim\n"); snapshot(a); assert game.snapshot() == before
            old_ids = [(slot, game.world.generations[slot]) for slot in game.world.entities]
            request(a, b"RESET\n", b"RESET\n")
            for identity in old_ids: game.world.despawn(identity)
            w = game.world; w.ticks = w.spawns = w.destroyed = w.moves = w.collisions = w.score = 0
            game.misses = game.shots = game.wave = 0; game.initial()
            assert all(not game.world.valid(identity) for identity in old_ids); snapshot(a); snapshot(b)
            for _ in range(4):
                request(a, b"STEP 32\n", b"STEPPED\n")
                for _ in range(32): game.tick()
                snapshot(b)
            assert game.misses >= 5; frozen = game.snapshot()
            request(a, b"FIRE 0\n", b"ERR aim\n"); request(a, b"STEP 1\n", b"STEPPED\n"); game.tick()
            snapshot(b); assert game.snapshot() == frozen
            request(b, b"CLOSE\n", b"BYE\n"); b.eof(); request(a, b"PING\n", b"PONG\n")
        finally:
            a.close(); b.close()
    print(f"Arena integration passed: 81 manual ticks, {checks} checked response lines, score and shared snapshots verified")


if __name__ == "__main__":
    main()
