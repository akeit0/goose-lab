"""Real TCP peers exercise Goose framing/backpressure and the independent game model."""
import os
from pathlib import Path
import queue
import re
import socket
import struct
import subprocess
import sys
import threading
import time

from ecs_game_fixture import World


class Client:
    def __init__(self, port, receive_buffer=None):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            if receive_buffer is not None:
                self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, receive_buffer)
            self.socket.settimeout(5)
            self.socket.connect(("127.0.0.1", port))
        except BaseException:
            self.socket.close(); raise
        self.socket.settimeout(8)
        self.buffer = bytearray()

    def send(self, data):
        self.socket.sendall(data)

    def line(self):
        while b"\n" not in self.buffer:
            part = self.socket.recv(4096)
            if not part: raise AssertionError("Unexpected connection EOF")
            self.buffer += part
        line, _, rest = self.buffer.partition(b"\n")
        self.buffer = bytearray(rest)
        return bytes(line) + b"\n"

    def quiet(self):
        assert not self.buffer
        self.socket.settimeout(0.05)
        try:
            part = self.socket.recv(1)
        except socket.timeout:
            pass
        else:
            raise AssertionError(f"Incomplete frame/full slots produced traffic: {part!r}")
        finally:
            self.socket.settimeout(8)

    def eof(self):
        assert not self.buffer and self.socket.recv(1) == b"", "Connection failed to drain and close"

    def close(self):
        self.socket.close()


def response(world, line):
    text = line.rstrip(b"\r\n")
    if re.fullmatch(rb"[A-Z]+(?: -?[0-9]{1,19}){0,7}", text) is None:
        return b"ERR syntax\n"
    fields = text.split(b" "); command = fields[0]; values = list(map(int, fields[1:]))
    if any(not -(1 << 63) <= v < (1 << 63) for v in values):
        return b"ERR syntax\n"
    if command == b"PING" and not values: return b"PONG\n"
    if command in (b"CLOSE", b"SHUTDOWN") and not values: return b"BYE\n"
    if command == b"BURST" and len(values) == 1 and 1 <= values[0] <= 1024: return b"DATA " + b"x" * values[0] + b"\n"
    if command == b"SPAWN" and len(values) == 7:
        x, y, vx, vy, hp, ttl, team = values
        identity, code = world.spawn(x, y, vx, vy, True, hp, ttl, team)
        return f"ID {identity[0]} {identity[1]}\n".encode() if not code else f"ERR {code}\n".encode()
    if command == b"STEP" and len(values) == 1 and 1 <= values[0] <= 32:
        for _ in range(values[0]): world.tick()
        return f"TICK {world.ticks} {world.score} {len(world.entities)}\n".encode()
    if command in (b"STATE", b"DESPAWN", b"VELOCITY") and len(values) >= 2 and values[0] >= 0 and values[1] > 0:
        identity = tuple(values[:2])
        if command == b"STATE" and len(values) == 2: return f"STATE {world.describe(identity)}\n".encode()
        if command == b"DESPAWN" and len(values) == 2: return f"CODE {world.despawn(identity)}\n".encode()
        if command == b"VELOCITY" and len(values) == 5 and values[2] in (0, 1):
            return f"CODE {world.velocity(identity, bool(values[2]), *values[3:])}\n".encode()
    if command == b"STATS" and not values:
        return f"STATS {world.ticks} {world.spawns} {world.destroyed} {world.moves} {world.collisions} {world.score} {len(world.entities)}\n".encode()
    return b"ERR command\n"


def accounting(stdout):
    summaries = [line for line in stdout.splitlines() if line.startswith("SERVER ")]
    assert len(summaries) == 1, "Missing final server accounting"
    values = list(map(int, summaries[0].split()[1:]))
    assert len(values) == 12
    assert all(value >= 0 for value in values)
    return dict(zip(("accepted", "closed", "requests", "paused_polls", "partial_writes", "written_bytes", "input_peak", "output_peak", "live_sockets", "blocked_writes", "compactions", "reclaimed_bytes"), values))


def validate(stdout):
    metrics = accounting(stdout)
    accepted, closed, requests, paused, partial, written, input_peak, output_peak, live, blocked, compactions, reclaimed = metrics.values()
    assert accepted == closed == 7 and live == 0
    assert requests > 80 and paused > 0 and partial > 0 and written > 4000
    assert input_peak == 256 and 1024 < output_peak <= 2048
    assert compactions > 0 and reclaimed >= compactions
    return metrics


def run_protocol(binary):
    process = subprocess.Popen([str(binary), "32"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
    lines, events, peers = [], queue.Queue(), []

    def read_stdout():
        for line in process.stdout:
            lines.append(line); events.put(line)
        events.put(None)

    reader = threading.Thread(target=read_stdout, daemon=True); reader.start()
    checked, requests, received_bytes = 0, 0, 0
    world = World(16)

    def expect(peer, wanted):
        nonlocal checked, received_bytes
        actual = peer.line()
        if actual != wanted: raise AssertionError(f"Server reply {actual!r} expected {wanted!r}")
        checked += 1; received_bytes += len(actual)
        return actual

    def connect(port, slot, generation):
        peer = Client(port); peers.append(peer)
        expect(peer, f"HELLO {slot} {generation}\n".encode())
        return peer

    def request(peer, line):
        nonlocal requests
        peer.send(line); requests += 1
        return expect(peer, response(world, line))

    def pipeline(peer, commands):
        nonlocal requests
        wanted = [response(world, command) for command in commands]
        peer.send(b"".join(commands)); requests += len(commands)
        for line in wanted: expect(peer, line)

    try:
        first = events.get(timeout=10)
        assert first and first.startswith("LISTEN "), f"Server failed before listening: {first}"
        port = int(first.split()[1])
        a, b, c = (connect(port, slot, 1) for slot in range(3))
        c.send(b"SPA"); c.quiet()
        tail = b"WN 2 0 0 0 1 20 2\n"; c.send(tail); requests += 1
        expect(c, response(world, b"SPA" + tail))
        spawn = b"SPAWN 0 0 1 0 1 4 1\r\n"
        for byte in spawn: a.send(bytes([byte]))
        a.send(b"PING\n"); requests += 2
        expect(a, response(world, spawn)); expect(a, b"PONG\n")
        request(b, b"STEP 1\n"); assert world.score == 1 and not world.entities
        request(c, b"STATE 0 1\n"); request(a, b"STATE 1 1\n")
        request(a, b"SPAWN 7 7 1 0 3 128 2\n")
        request(b, b"VELOCITY 0 1 1 2 0\n"); request(b, b"VELOCITY 0 2 0 0 0\n")
        # A fourth TCP peer remains in the OS backlog while all logical slots live.
        d = Client(port); peers.append(d); d.quiet()
        request(b, b"CLOSE\n"); b.eof()
        expect(d, b"HELLO 1 2\n")
        # Leave a large ordered pipeline unread; another connection stays useful.
        burst = b"BURST 1024\n"; a.send(burst * 4); requests += 4
        time.sleep(0.05); request(d, b"PING\n")
        for _ in range(4): expect(a, b"DATA " + b"x" * 1024 + b"\n")
        pipeline(d, [b"PING\n"] * 40)
        # Oversized framing closes only c, without touching the shared game.
        c.send(b"x" * 257); expect(c, b"ERR frame-limit\n"); c.eof()
        e = connect(port, 2, 2)
        e.send(b"PING\nPING\nSPAWN 1 0 0"); requests += 2; e.socket.shutdown(socket.SHUT_WR)
        expect(e, b"PONG\n"); expect(e, b"PONG\n"); expect(e, b"ERR truncated\n"); e.eof()
        f = connect(port, 2, 3)
        for bad in (b"\x00PING\n", b"PING 1\n", b"STEP 0\n", b"SPAWN 9999999999999999999 0 0 0 1 1 1\n",
                    b"SPAWN -9223372036854775808 0 0 0 1 1 1\n", b"SPAWN 0 0 9 0 1 1 1\n"):
            request(f, bad)
        request(f, b"STATS\n")
        for _ in range(15): request(d, b"SPAWN 2 2 0 0 2 128 2\n")
        before = response(world, b"STATS\n")
        request(f, b"SPAWN 0 0 0 0 1 5 1\n"); assert response(world, b"STATS\n") == before
        request(f, b"DESPAWN 5 1\n"); request(a, b"SPAWN -2 -2 1 1 1 20 1\n")
        request(f, b"STATE 5 1\n"); request(d, b"VELOCITY 3 1 0 0 0\n"); request(d, b"STEP 3\n")
        for slot in sorted(world.entities): request(f, f"STATE {slot} {world.generations[slot]}\n".encode())
        request(a, b"STATS\n")
        # Reset a connection carrying an incomplete frame: transport error must release it.
        d.send(b"SPAWN")
        d.socket.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("hh" if os.name == "nt" else "ii", 1, 0)); d.close()
        g = connect(port, 1, 3); request(g, b"CLOSE\n"); g.eof()
        f.send(b"SPAWN 1"); f.quiet()
        request(a, b"SHUTDOWN\n"); a.eof(); f.eof()
        process.wait(timeout=10); reader.join(timeout=2)
        stderr = process.stderr.read()
        if process.returncode: raise AssertionError(stderr + "".join(lines))
        stdout = "".join(lines); metrics = validate(stdout)
        assert metrics["requests"] == requests and metrics["written_bytes"] >= received_bytes
        metrics.update(checked_replies=checked, model_entities_checked=len(world.entities), game_score=world.score)
        summary = next(line for line in stdout.splitlines() if line.startswith("SERVER "))
        leaked = summary.split(); leaked[9] = "1"
        for damaged in (stdout.replace("SERVER 7 7", "SERVER 7 6", 1), stdout.replace(summary, " ".join(leaked)), "\n".join(stdout.splitlines()[:-1])):
            try: validate(damaged)
            except (AssertionError, ValueError): pass
            else: raise AssertionError("Server accounting oracle accepted a damaged trace")
        result = subprocess.CompletedProcess([str(binary), "32"], process.returncode, stdout, stderr)
        print(f"Server experiment: {metrics}")
        return result, metrics
    finally:
        for peer in peers: peer.close()
        if process.poll() is None: process.kill(); process.wait(timeout=5)
        reader.join(timeout=2)
        process.stdout.close(); process.stderr.close()


def run_pressure(binary):
    """Wait for an actual native would-block before resuming the unread peer."""
    process = subprocess.Popen([str(binary), "2048"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
    lines, events, peers = [], queue.Queue(), []

    def read_stdout():
        for line in process.stdout:
            lines.append(line); events.put(line)
        events.put(None)

    reader = threading.Thread(target=read_stdout, daemon=True); reader.start()
    received_bytes = checked = 0

    def expect(peer, wanted):
        nonlocal received_bytes, checked
        actual = peer.line()
        assert actual == wanted, f"Pressure reply {actual!r} expected {wanted!r}"
        received_bytes += len(actual); checked += 1

    try:
        first = events.get(timeout=10)
        assert first and first.startswith("LISTEN "), f"Pressure server failed: {first}"
        port = int(first.split()[1])
        a = Client(port, receive_buffer=4096); peers.append(a); expect(a, b"HELLO 0 1\n")
        b = Client(port); peers.append(b); expect(b, b"HELLO 1 1\n")
        sizes = [960 + i % 65 for i in range(512)]
        a.send(b"".join(f"BURST {size}\n".encode() for size in sizes))
        blocked = events.get(timeout=8)
        assert blocked == "BLOCKED 0 1\n", f"No native would-block on unread peer: {blocked!r}"
        # All a's responses remain unread here. b must parse and mutate the World.
        world = World(16)
        for command in (b"PING\n", b"SPAWN 3 4 1 -1 2 20 2\n", b"STATE 0 1\n"):
            b.send(command); expect(b, response(world, command))
        for size in sizes:
            expect(a, b"DATA " + b"x" * size + b"\n")
        b.send(b"SHUTDOWN\n"); expect(b, b"BYE\n"); b.eof(); a.eof()
        process.wait(timeout=10); reader.join(timeout=2)
        stderr = process.stderr.read(); stdout = "".join(lines)
        assert process.returncode == 0, stderr + stdout
        metrics = accounting(stdout)
        assert metrics["accepted"] == metrics["closed"] == 2 and metrics["live_sockets"] == 0
        assert metrics["requests"] == len(sizes) + 4 and metrics["written_bytes"] == received_bytes
        assert metrics["blocked_writes"] > 0 and metrics["paused_polls"] > 0
        assert metrics["input_peak"] <= 256 and 1024 < metrics["output_peak"] <= 2048
        metrics.update(checked_replies=checked, payload_responses=len(sizes))
        print(f"Kernel pressure: {metrics}")
        return subprocess.CompletedProcess([str(binary), "2048"], process.returncode, stdout, stderr), metrics
    finally:
        for peer in peers: peer.close()
        if process.poll() is None: process.kill(); process.wait(timeout=5)
        reader.join(timeout=2); process.stdout.close(); process.stderr.close()


def run(binary):
    protocol, metrics = run_protocol(binary)
    pressure, pressure_metrics = run_pressure(binary)
    metrics["kernel_pressure"] = pressure_metrics
    # Keep both transcripts; distinguish the second accounting record.
    combined = subprocess.CompletedProcess(protocol.args, 0, protocol.stdout + pressure.stdout.replace("SERVER ", "PRESSURE "), protocol.stderr + pressure.stderr)
    return combined, metrics


if __name__ == "__main__":
    run(Path(sys.argv[1]))
