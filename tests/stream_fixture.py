"""Independent producer/page and flat-file search oracles, no public network."""
import csv
from pathlib import Path
import subprocess
import sys
import tempfile


def validate_producer(stdout):
    traces = {(count, client): [] for count in (3, 16, 64) for client in range(count)}
    summaries = []
    for row in csv.reader(stdout.splitlines()):
        if row[0] != "page":
            summaries.append(",".join(row)); continue
        if len(row) != 6:
            raise AssertionError("Malformed page trace")
        _, count, client, sequence, done, text = row
        key = int(count), int(client); sequence = int(sequence)
        if key not in traces or sequence != len(traces[key]) + 1:
            raise AssertionError("Missing, duplicate or misrouted page")
        if done != ("true" if sequence == 4 else "false") or text != ("" if sequence == 4 else f"{client}:1:{sequence}"):
            raise AssertionError("Cross-client producer payload or terminal mismatch")
        traces[key].append(sequence)
    if any(values != [1, 2, 3, 4] for values in traces.values()):
        raise AssertionError("Incomplete producer stream")
    if summaries != ["stream races and typed ACK isolation passed", "many,3,passed", "many,16,passed", "many,64,passed",
                     "stream stalled-lane bounds and shutdown passed", "Stream contracts passed"]:
        raise AssertionError("Incomplete lifecycle/bounds coverage")
    return {"clients": 83, "pages": sum(map(len, traces.values())), "ack_cancel_races": 100}


def files(root):
    texts = {}
    for name in ["A", "B", "C"] + [f"M{i}" for i in range(64)]:
        directory = root / name; directory.mkdir()
        text = "".join(f"{name}:{i:03} needle 日本語\r\n" for i in range(96)).encode("utf-8")
        path = f"data-{name}.txt"; (directory / path).write_bytes(text); texts[name] = (path, text)
        (directory / "binary.dat").write_bytes(b"needle\0binary")
        (directory / "invalid.dat").write_bytes(b"\xffneedle")
    return texts


def hits(path, text, query):
    query = query.encode("utf-8"); result = set(); offset = 0
    while True:
        start = text.find(query, offset)
        if start < 0:
            break
        line = text[:start].count(b"\n") + 1
        line_start = text.rfind(b"\n", 0, start) + 1
        column = len(text[line_start:start].decode("utf-8")) + 1
        result.add((path, line, column, start, start + len(query))); offset = start + 1
    return result


def cases(texts):
    expected = {}
    def add(label, owner, slot, generation, serial, query="needle", code=0, result=0, matches=96, partial=False, payload=True):
        path, text = texts[owner]; all_hits = hits(path, text, query) if payload else set()
        if partial:
            all_hits = set(sorted(all_hits, key=lambda h: h[3])[:matches])
        expected[label] = {"identity": (slot, generation, serial), "hits": all_hits,
                           "issues": {("binary.dat", 1), ("invalid.dat", 2)} if payload else set(),
                           "done": (slot, generation, serial, code, result, matches), "partial": partial}
    add("B", "B", 1, 1, 1); add("C", "C", 2, 1, 1); add("A2", "A", 0, 2, 1, query="日本語")
    add("B-missing", "B", 1, 1, 2, query="absent", matches=0)
    add("C-timeout", "C", 2, 1, 2, code=8, result=5, matches=32, payload=False)
    add("C-invalid", "C", 2, 1, 3, code=9, result=1, matches=0, payload=False)
    add("C-io", "C", 2, 1, 4, code=9, result=2, matches=0, payload=False)
    add("A-limit", "A", 0, 2, 2, code=9, result=3, matches=2, partial=True)
    add("B-cancel", "B", 1, 1, 3, code=7, result=4, matches=0, payload=False)
    for count in (3, 16, 64):
        for client in range(count):
            add(f"many-{count}-{client}", f"M{client}", client, 1, 1)
    return expected


def validate_search(stdout, expected):
    observed = {label: {"hits": set(), "issues": set(), "done": None} for label in expected}; summaries = []
    for row in csv.reader(stdout.splitlines()):
        if row[0] not in ("hit", "issue", "done"):
            summaries.append(",".join(row)); continue
        kind, label, *values = row
        if label not in expected:
            raise AssertionError(f"Unexpected client label: {label}")
        item, model = observed[label], expected[label]
        if item["done"] is not None:
            raise AssertionError("Data after terminal or duplicate terminal")
        if kind == "hit":
            identity = tuple(map(int, values[:3])); hit = (values[3], *map(int, values[4:]))
            if identity != model["identity"] or hit not in model["hits"] or hit in item["hits"]:
                raise AssertionError(f"Misrouted, duplicate or incorrect flat-file match: {row}")
            item["hits"].add(hit)
        elif kind == "issue":
            issue = values[0], int(values[1])
            if issue not in model["issues"] or issue in item["issues"]:
                raise AssertionError(f"Unknown or duplicate file issue: {row}")
            item["issues"].add(issue)
        else:
            item["done"] = tuple(map(int, values))
            if item["done"] != model["done"]:
                raise AssertionError(f"Terminal mismatch: {row} expected {model['done']}")
    for label, model in expected.items():
        item = observed[label]
        if item["hits"] != model["hits"] or item["done"] != model["done"] or (not model["partial"] and item["issues"] != model["issues"]):
            raise AssertionError(f"Incomplete search coverage: {label}")
    if summaries != ["real search lifetimes and native cleanup passed", "search-many,3,passed", "search-many,16,passed", "search-many,64,passed", "Search stream contracts passed"]:
        raise AssertionError("Incomplete native/lifecycle coverage")
    return {"streams": len(expected), "matches": sum(len(x["hits"]) for x in observed.values())}


def capture(command, prefix=None):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
    if prefix is not None:
        prefix.with_suffix(".stdout").write_text(result.stdout, encoding="utf-8")
        prefix.with_suffix(".stderr").write_text(result.stderr, encoding="utf-8")
    if result.returncode:
        print(result.stdout[-4000:], end=""); print(result.stderr, file=sys.stderr, end=""); result.check_returncode()
    return result


def rejects(check, text):
    try:
        check(text)
    except (AssertionError, ValueError, IndexError):
        return
    raise AssertionError("Independent oracle accepted corrupted trace")


def run(producer, search, logs=None):
    first = capture([producer], logs / "producer" if logs else None); producer_result = validate_producer(first.stdout)
    rejects(validate_producer, first.stdout.replace("0:1:1", "1:1:1", 1))
    rejects(validate_producer, "\n".join(first.stdout.splitlines()[:-1]))
    with tempfile.TemporaryDirectory(prefix="goose-stream-") as directory:
        root = Path(directory); expected = cases(files(root)); second = capture([search, root], logs / "search" if logs else None)
        search_result = validate_search(second.stdout, expected)
        rejects(lambda text: validate_search(text, expected), second.stdout.replace("data-B.txt", "data-A.txt", 1))
        rejects(lambda text: validate_search(text, expected), "\n".join(second.stdout.splitlines()[:-1]))
    print(f"Stream oracles passed: {producer_result['pages']} producer pages; {search_result['streams']} real streams, {search_result['matches']} flat-file matches")
    return first, second, producer_result, search_result


if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2])
