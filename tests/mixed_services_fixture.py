"""HTTP/search composition with server barriers and a flat-file result oracle."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

from http_clients_fixture import Handler, Server


def files(root):
    texts = {}
    for label in ("A", "B"):
        directory = root / label
        directory.mkdir()
        text = "".join(f"{label}:{line:03} needle payload\r\n" for line in range(96)).encode()
        (directory / "data.txt").write_bytes(text)
        texts[label] = text
    return texts


def expected_hits(text):
    result = set()
    offset = 0
    for line, raw in enumerate(text.splitlines(keepends=True), 1):
        start = raw.index(b"needle")
        result.add(("data.txt", line, start + 1, offset + start, offset + start + 6,
                    raw.rstrip(b"\r\n").decode()))
        offset += len(raw)
    return result


def validate(stdout):
    expected = {"after-http": ("A", (0, 1, 1)), "reopened-search": ("B", (0, 2, 1)),
                "quota-recovery": ("B", (1, 1, 1))}
    texts = {label: "".join(f"{label}:{line:03} needle payload\r\n" for line in range(96)).encode()
             for label in ("A", "B")}
    observed = {(r, label): set() for r in range(3) for label in expected}
    flat = {label: expected_hits(text) for label, text in texts.items()}
    done, http, tokens, clean, quota = set(), set(), set(), set(), set()
    lines = stdout.splitlines()
    for row in lines:
        parts = row.split(",")
        kind = parts[0]
        if kind in ("hit", "done"):
            round_number, label = int(parts[1]), parts[2]
            owner, identity = expected[label]
            if tuple(map(int, parts[3:6])) != identity or (round_number, label) not in observed:
                raise AssertionError(f"Wrong search identity: {row}")
            if kind == "hit":
                hit = (parts[6], *map(int, parts[7:11]), parts[11])
                bucket = observed[round_number, label]
                if len(parts) != 12 or hit in bucket or hit not in flat[owner]:
                    raise AssertionError(f"Unexpected/duplicate search hit: {row}")
                bucket.add(hit)
            else:
                key = (round_number, label)
                if len(parts) != 7 or int(parts[6]) != 96 or key in done:
                    raise AssertionError(f"Wrong/duplicate search completion: {row}")
                done.add(key)
        elif kind == "http":
            round_number, label = int(parts[1]), parts[2]
            identities = {"http-close": (1, 1, 1, 200, f"http-live-{round_number}"),
                          "http-reopen": (0, 2, 1, 200, f"reopen-{round_number}"),
                          "after-search": (0, 1, 1, 200, f"held-{round_number}"),
                          "quota-recovery": (1, 1, 1, 200, f"recovered-{round_number}"),
                          "quota-survivor": (0, 1, 1, 200, f"quota-held-{round_number}")}
            key = (round_number, label)
            if round_number not in range(3) or len(parts) != 8 or (*map(int, parts[3:7]), parts[7]) != identities[label] or key in http:
                raise AssertionError(f"Wrong/duplicate HTTP result: {row}")
            http.add(key)
        elif kind == "quota":
            round_number = int(parts[1])
            if round_number not in range(3) or round_number in quota or list(map(int, parts[2:])) != [2, 2, 2, 1, 0, 2, 1]:
                raise AssertionError(f"Wrong quota refusal/serial accounting: {row}")
            quota.add(round_number)
        elif kind in ("tokens", "clean"):
            key = (int(parts[1]), parts[2])
            bucket = tokens if kind == "tokens" else clean
            labels = ("http-stopped", "search-stopped") if kind == "tokens" else ("http-stopped", "search-stopped", "quota")
            if key[0] not in range(3) or key[1] not in labels or key in bucket or (kind == "tokens" and parts[3:] != ["63"]) or (kind == "clean" and len(parts) != 3):
                raise AssertionError(f"Wrong cleanup accounting: {row}")
            bucket.add(key)
        elif row not in ("native,64,16,16", "Mixed service contracts passed"):
            raise AssertionError(f"Unexpected trace row: {row}")
    for key, bucket in observed.items():
        if bucket != flat[expected[key[1]][0]] or key not in done:
            raise AssertionError(f"Missing search results: {key}")
    if len(lines) != 908 or len(http) != 15 or len(tokens) != 6 or len(clean) != 9 or len(quota) != 3 or lines[-2:] != ["native,64,16,16", "Mixed service contracts passed"]:
        raise AssertionError("Incomplete composition/cleanup trace")
    return {"rows": len(lines), "search_hits": sum(map(len, observed.values())), "http_results": len(http),
            "search_completions": len(done), "lifecycle_cases": len(clean), "quota_refusals": len(quota) * 3}


def run(binary):
    Handler.barriers = {}
    server = Server(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = dict(os.environ, NO_PROXY="127.0.0.1,localhost", no_proxy="127.0.0.1,localhost")
    try:
        with tempfile.TemporaryDirectory(prefix="goose-mixed-") as directory:
            root = Path(directory)
            files(root)
            process = subprocess.run([str(binary), f"http://127.0.0.1:{server.server_port}", str(root)],
                                     capture_output=True, text=True, encoding="utf-8", env=env, timeout=60)
        if process.returncode:
            print(process.stdout, end="")
            print(process.stderr, file=sys.stderr, end="")
            process.check_returncode()
        barriers = {f"{label}-{r}" for label in ("http-stop", "held", "quota-held") for r in range(3)}
        if set(Handler.barriers) != barriers or any(not ready.is_set() or not release.is_set()
                                                  for ready, release in Handler.barriers.values()):
            raise AssertionError("Missing server-confirmed active transfer or release")
        metrics = validate(process.stdout)
        for corrupted in (process.stdout.replace("http-live-0", "http-live-1", 1),
                          process.stdout.replace("hit,0,after-http,0,1,1", "hit,0,after-http,0,2,1", 1),
                          process.stdout.replace("tokens,0,http-stopped,63", "tokens,0,http-stopped,64", 1),
                          process.stdout.replace("quota,0,2,2,2,1,0,2,1", "quota,0,2,2,2,1,1,2,1", 1),
                          "\n".join(process.stdout.splitlines()[1:])):
            try:
                validate(corrupted)
            except (AssertionError, ValueError, KeyError, IndexError):
                pass
            else:
                raise AssertionError("Oracle accepted a corrupted composition trace")
        print(f"Mixed services: {metrics['search_hits']} flat-model hits, {metrics['http_results']} HTTP results, "
              f"{metrics['lifecycle_cases']} lifecycle/quota cases passed")
        return process
    finally:
        for _, release in Handler.barriers.values():
            release.set()
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    run(sys.argv[1])
