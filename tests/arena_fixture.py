"""Independent dictionary simulation and unsolicited two-peer state delivery."""
from collections import deque
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from arena import server
from server_experiment_fixture import Client


class Game:
    def __init__(self):
        self.entities = {}; self.players = {}; self.generations = [0] * 16
        self.ticks = 0; self.round = 1; self.winner = (-1, 0); self.remaining = self.collected = 0
        self.seed()

    def spawn(self, x, y, kind):
        slot = next(i for i in range(16) if i not in self.entities)
        self.generations[slot] += 1
        self.entities[slot] = dict(x=x, y=y, kind=kind)
        return slot

    def seed(self):
        for y in (3, 7, 11, 15, 19, 23): self.spawn(20, y, 2)

    def join(self, peer):
        slot = self.spawn(4 if peer[0] % 2 == 0 else 36, 4 + peer[0] // 2 * 5, 1)
        self.players[slot] = dict(peer=peer, score=0, ack=0, received=0, inputs=deque())

    def leave(self, peer):
        slot = next(slot for slot, p in self.players.items() if p['peer'] == peer)
        del self.players[slot]; del self.entities[slot]

    def input(self, peer, sequence, dx, dy):
        p = next(p for p in self.players.values() if p['peer'] == peer)
        if not 1 <= sequence <= 1_000_000_000 or dx not in (-1, 0, 1) or dy not in (-1, 0, 1): return False
        if sequence <= p['received']: return True
        if sequence != p['received'] + 1 or len(p['inputs']) == 8: return False
        p['inputs'].append((sequence, dx, dy)); p['received'] = sequence; return True

    def tick(self):
        self.ticks += 1
        paused = self.remaining > 0 or len(self.players) < 2
        for slot, p in self.players.items():
            if p['inputs']:
                sequence, dx, dy = p['inputs'].popleft(); p['ack'] = sequence
                if not paused:
                    b = self.entities[slot]; b['x'] = min(40, max(0, b['x'] + dx)); b['y'] = min(24, max(0, b['y'] + dy))
        if self.remaining:
            self.remaining -= 1
            if not self.remaining:
                self.round += 1; self.winner = (-1, 0)
                for slot, p in self.players.items():
                    p['score'] = 0; peer = p['peer'][0]; self.entities[slot].update(x=4 if peer % 2 == 0 else 36, y=4 + peer // 2 * 5)
                self.entities = {slot: b for slot, b in self.entities.items() if b['kind'] == 1}; self.seed()
            return
        if paused: return
        gems = sorted(slot for slot, b in self.entities.items() if b['kind'] == 2)
        for slot in gems:
            gem = self.entities[slot]
            candidates = [(s, p) for s, p in self.players.items() if abs(self.entities[s]['x'] - gem['x']) <= 1 and abs(self.entities[s]['y'] - gem['y']) <= 1]
            if not candidates: continue
            _, p = min(candidates, key=lambda item: (item[1]['peer'][0] - self.ticks) % 8)
            p['score'] += 1; self.collected += 1; del self.entities[slot]
            self.spawn(8 + self.collected * 11 % 25, 3 + self.collected * 7 % 19, 2)
            if p['score'] >= 8: self.winner = p['peer']; self.remaining = 60; break

    def frame(self):
        lines = [f"FRAME 2 1 {self.ticks} {self.round} {self.winner[0]} {self.winner[1]} {self.remaining} {self.collected} {len(self.players)} 6\n"]
        for slot in sorted(self.players):
            p = self.players[slot]; b = self.entities[slot]
            lines.append(f"PLAYER {slot} {self.generations[slot]} {p['peer'][0]} {p['peer'][1]} {b['x']} {b['y']} {p['score']} {p['ack']}\n")
        for slot in sorted(self.entities):
            b = self.entities[slot]
            if b['kind'] == 2: lines.append(f"GEM {slot} {self.generations[slot]} {b['x']} {b['y']}\n")
        return [line.encode() for line in lines] + [b"END\n"]


class Peer(Client):
    def packet(self):
        line = self.line()
        if not line.startswith(b"FRAME "): return [line]
        lines = [line]
        while lines[-1] != b"END\n":
            assert len(lines) < 16; lines.append(self.line())
        return lines

    def response(self, wanted):
        for _ in range(100):
            packet = self.packet()
            if packet == [wanted]: return
            assert packet[0].startswith(b"FRAME "), packet
        raise AssertionError("Missing response")

    def state(self, game):
        wanted = game.frame()
        for _ in range(100):
            packet = self.packet(); assert packet[0].startswith(b"FRAME "), packet
            tick = int(packet[0].split()[3]); assert tick <= game.ticks
            if tick == game.ticks and packet == wanted: return
        raise AssertionError("Missing latest state")


def main():
    with server(Path(sys.argv[1]).resolve(), manual=True) as (port, output):
        a = Peer(port); b = None; c = None; game = Game()
        try:
            assert a.line() == b"WELCOME 2 0 1\n"; game.join((0, 1)); a.state(game)

            def command(peer, text, wanted):
                peer.send(text); peer.response(wanted)

            def step(count=1, peers=None):
                command(a, f"STEP {count}\n".encode(), b"STEPPED\n")
                for _ in range(count): game.tick()
                for peer in peers or (a, b):
                    if peer: peer.state(game)

            # Waiting consumes input numbers without giving the first joiner a head start.
            a.send(b"INPUT 1 1 1\nPING\n"); a.response(b"PONG\n"); assert game.input((0, 1), 1, 1, 1)
            step(peers=(a,)); assert game.entities[6]['x'] == 4
            b = Peer(port); assert b.line() == b"WELCOME 2 1 1\n"; game.join((1, 1)); a.state(game); b.state(game)
            # Fragmented input does not hold up another peer or advance movement early.
            b.send(b"INP"); command(a, b"PING\n", b"PONG\n")
            b.send(b"UT 1 -1 0\nPING\n"); b.response(b"PONG\n"); assert game.input((1, 1), 1, -1, 0); step()
            seen_winner = False
            for tick in range(240):
                for peer, identity in ((a, (0, 1)), (b, (1, 1))):
                    slot, p = next((s, p) for s, p in game.players.items() if p['peer'] == identity); body = game.entities[slot]
                    if identity[0] == 0:
                        gem = min((g for g in game.entities.values() if g['kind'] == 2), key=lambda g: abs(g['x'] - body['x']) + abs(g['y'] - body['y']))
                        dx = (gem['x'] > body['x']) - (gem['x'] < body['x']); dy = (gem['y'] > body['y']) - (gem['y'] < body['y'])
                    else: dx, dy = (tick // 7 % 3) - 1, (tick // 11 % 3) - 1
                    sequence = p['received'] + 1
                    peer.send(f"INPUT {sequence} {dx} {dy}\nPING\n".encode()); peer.response(b"PONG\n")
                    assert game.input(identity, sequence, dx, dy)
                step(); seen_winner |= game.remaining > 0
            assert seen_winner and game.round >= 2 and game.collected >= 8
            p = next(p for p in game.players.values() if p['peer'] == (0, 1)); sequence = p['received']
            a.send(f"INPUT {sequence} -1 -1\nPING\n".encode()); a.response(b"PONG\n"); assert game.input((0, 1), sequence, -1, -1)
            step()  # Duplicate must not move twice.
            before = game.frame()
            for bad in (b"INPUT 999999 1 0\n", b"INPUT 1 2 0\n", b"INPUT -9223372036854775808 0 0\n", b"INPUT 1 0 0 1\n", b"FIRE 0\n"):
                command(b, bad, b"ERR input\n"); assert game.frame() == before
            # Eight queued commands are bounded; the refused ninth is retriable.
            p = next(p for p in game.players.values() if p['peer'] == (1, 1)); start = p['received'] + 1
            for sequence in range(start, start + 8):
                b.send(f"INPUT {sequence} 1 0\n".encode()); assert game.input((1, 1), sequence, 1, 0)
            command(b, f"INPUT {start + 8} 1 0\n".encode(), b"ERR input\n"); assert not game.input((1, 1), start + 8, 1, 0)
            step(8); b.send(f"INPUT {start + 8} 0 0\nPING\n".encode()); b.response(b"PONG\n"); assert game.input((1, 1), start + 8, 0, 0); step()
            old_slot = next(slot for slot, p in game.players.items() if p['peer'] == (1, 1)); old_generation = game.generations[old_slot]
            command(b, b"CLOSE\n", b"BYE\n"); b.eof(); game.leave((1, 1)); a.state(game)
            c = Peer(port); assert c.line() == b"WELCOME 2 1 2\n"; game.join((1, 2)); a.state(game); c.state(game)
            assert game.generations[old_slot] > old_generation
            command(a, b"PING\n", b"PONG\n")
        finally:
            for peer in (a, b, c):
                if peer: peer.close()
    print("Arena versus integration passed: 252 ticks, two owned players, pushed states, wins/restarts, duplicate/refused inputs and reconnect generations")


if __name__ == '__main__': main()
