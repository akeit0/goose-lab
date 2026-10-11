"""List-model admission oracle and repeated real HTTP/search resource recovery."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

from http_clients_fixture import Handler, Server
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from profile import memory


TEXT = "".join(f"A:{i:03} needle payload\r\n" for i in range(96)).encode()


def validate(stdout):
    lines = iter(stdout.splitlines())
    for domains in (2, 3, 8):
        pending, cursor, ticket, queued, accepted, cancelled = [], 0, 0, 0, 0, 0
        seed, last = 19, 0
        for step in range(600):
            seed = (seed * 37 + 11) % 9973
            op, domain, key = seed % 10, (seed // 10) % (domains + 2), (seed // 100) % 13
            target = seed % (ticket + 2) if step % 3 == 0 else last
            result, code = (0, -1, 0), 0
            if op < 4:
                if domain >= domains:
                    code = 1
                elif any(d[1:] == (domain, key) for d in pending):
                    code = 4
                elif len(pending) == 17:
                    code = 2
                else:
                    ticket += 1; result = (ticket, domain, key)
                    pending.append(result); queued += 1
            elif op < 7:
                candidates = [d for d in pending if key & (1 << d[1])]
                if candidates:
                    result = min(candidates, key=lambda d: ((d[1] - cursor) % domains, d[0]))
                else:
                    code = 5
            else:
                found = next((d for d in pending if d[0] == target), None)
                if found is None:
                    code = 3
                else:
                    pending.remove(found)
                    if op < 9:
                        cursor = (found[1] + 1) % domains; accepted += 1
                    else:
                        cancelled += 1
            if result[0]:
                last = result[0]
            expected = f"model,{domains},{step},{op},{domain},{key},{target},{code}," + ",".join(map(str, (*result, len(pending), queued, accepted, cancelled)))
            if next(lines) != expected:
                raise AssertionError(f"Admission list model mismatch: {domains}/{step}")
    rows = list(lines)
    marker = rows.pop()
    if not marker.startswith("Admission service contracts passed,"):
        raise AssertionError("Missing shutdown completion")
    rounds = int(marker.split(",")[1])
    if not 1 <= rounds <= 4096:
        raise AssertionError("Invalid cycle count")
    serials, generations = [0] * 4, [1] * 4
    search_serial, search_generation = 0, 1
    at, hit_count, arena = 0, 0, []

    def expect(row):
        nonlocal at
        if rows[at] != row:
            raise AssertionError(f"Service trace mismatch: {rows[at]} expected {row}")
        at += 1

    for cycle in range(rounds):
        expect(f"refused,{cycle},{serials[0]},{search_serial}")
        order = [(0, 0), (1, 0), (0, 1), (0, 2), (0, 3)] if cycle == 0 else [(1, 0), (0, 0), (0, 1), (0, 2), (0, 3)]
        for domain, client in order:
            expect(f"admit,{cycle},{domain},{client}")
            if domain == 0:
                serials[client] += 1
                size = 12000 if (cycle + client) % 3 == 0 else len(f"{cycle}-{client}")
                expect(f"http,{cycle},{client},{generations[client]},{serials[client]},{size}")
            else:
                search_serial += 1
                stopped = cycle % 4 == 0
                offset = 0
                for number, raw in enumerate(TEXT.splitlines(keepends=True)[:32 if stopped else 96], 1):
                    start = raw.index(b"needle")
                    expect(f"hit,{cycle},{search_generation},{search_serial},data.txt,{number},{start+1},{offset+start},{offset+start+6},{raw.rstrip().decode()}")
                    offset += len(raw); hit_count += 1
                expect(f"search,{cycle},{search_generation},{search_serial},{7 if stopped else 0},{0 if stopped else 96}")
        fields = rows[at].split(","); at += 1
        prefix = ["cycle", cycle, (cycle + 1) * 4, cycle + 1, (cycle + 1) * 6, (cycle + 1) * 5, cycle + 1]
        if fields[:7] != list(map(str, prefix)) or len(fields) != 9 or not 0 <= int(fields[7]) <= 12864 or not 0 < int(fields[8]) <= 65536:
            raise AssertionError("Wrong cleanup/capacity accounting")
        arena.append({"cycle": cycle, "http_arena_bytes": int(fields[7]), "search_peak_arena_bytes": int(fields[8])})
        slot = cycle % 4; generations[slot] += 1; serials[slot] = 0
        if cycle % 4 == 0:
            search_generation += 1; search_serial = 0
    if at != len(rows):
        raise AssertionError("Trailing service trace")
    return {"cycles": rounds, "model_operations": 1800, "admissions": rounds * 5,
            "http_results": rounds * 4, "search_hits": hit_count, "search_completions": rounds,
            "quota_refusals": rounds * 2, "resource_reacquisitions": rounds + 1,
            "rows": 1800 + len(rows) + 1, "retained_arenas": arena}


def run(binary, cycles=16):
    pid_ready = threading.Event()
    pid, samples = [], []

    class SampleHandler(Handler):
        def do_GET(self):
            if self.path.startswith("/checkpoint/"):
                if not pid_ready.wait(5):
                    raise TimeoutError("Process ID unavailable")
                samples.append({"cycle": int(self.path.rsplit("/", 1)[1]), "bytes": memory(pid[0])})
                self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()
            else:
                super().do_GET()

    server = Server(("127.0.0.1", 0), SampleHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    env = dict(os.environ, NO_PROXY="127.0.0.1,localhost", no_proxy="127.0.0.1,localhost")
    process = None
    try:
        with tempfile.TemporaryDirectory(prefix="goose-admission-") as directory:
            (Path(directory) / "data.txt").write_bytes(TEXT)
            process = subprocess.Popen([str(binary), f"http://127.0.0.1:{server.server_port}", directory, str(cycles)],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", env=env)
            pid.append(process.pid); pid_ready.set()
            stdout, stderr = process.communicate(timeout=max(60, cycles * 2))
        result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
        if result.returncode:
            print(stdout, end=""); print(stderr, file=sys.stderr, end=""); result.check_returncode()
        metrics = validate(stdout)
        checkpoints = sorted(set(range(7, cycles, 8)) | {cycles - 1})
        if metrics["cycles"] != cycles or [s["cycle"] for s in samples] != checkpoints:
            raise AssertionError("Wrong cycle/checkpoint coverage")
        for damaged in (stdout.replace("admit,0,1,0", "admit,0,0,0", 1),
                        stdout.replace("http,0,0,1,1", "http,0,0,2,1", 1),
                        stdout.replace("hit,0,1,1", "hit,0,2,1", 1),
                        stdout.replace("refused,0,0,0", "refused,0,1,0", 1),
                        "\n".join(stdout.splitlines()[1:])):
            try:
                validate(damaged)
            except (AssertionError, ValueError, IndexError, StopIteration):
                pass
            else:
                raise AssertionError("Oracle accepted corrupt admission/lifetime trace")
        result.observations = {"checkpoint_memory": samples}
        print(f"Admission: 1800 list-model operations, {cycles} reuse cycles, {metrics['admissions']} fair admissions, "
              f"{metrics['search_hits']} search hits; native capacities recovered")
        return result
    finally:
        if process is not None and process.poll() is None:
            process.kill(); process.communicate()
        server.shutdown(); server.server_close(); thread.join()


if __name__ == "__main__":
    run(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 16)
