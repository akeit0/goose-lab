"""Compare snapshot and shared-tree documents with equal history and operation traces."""
import argparse
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import shutil
import sys

from document_experiment import cache, digest, git, percentile, revision, run
from run import executable

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ["operation", "elapsed_ns", "documents", "current_bytes", "saved_bytes", "history_versions",
          "used_bytes", "arena_bytes", "high_water_bytes", "text_bytes", "node_bytes", "inserted_bytes",
          "collected_bytes", "growth_moved_bytes", "node_writes", "collections", "scanned_nodes"]


def expected_trace(count, size, rounds, history, mode):
    """Version/source-byte oracle independent of tree nodes, balancing or collection."""
    documents = [None] * count
    written = retained_text = 0

    def state(operation):
        nonlocal retained_text
        live = [doc for doc in documents if doc is not None]
        versions = sum(len(doc["versions"]) - 1 for doc in live)
        expected = {"operation": operation, "documents": len(live), "current_bytes": len(live) * size,
                    "saved_bytes": len(live) * size, "history_versions": versions, "inserted_bytes": written}
        if mode == "snapshot":
            expected["used_bytes"] = (versions + len(live) * 2) * size
            expected["text_bytes"] = expected["used_bytes"]
        else:
            if operation in ("collect", "close_all"):
                retained_text = 0
                for doc in live:
                    roots = set(doc["versions"]) | {doc["saved"]}
                    # Every version shares the untouched suffix; each edit appends
                    # one distinct first-byte source, even when its value repeats.
                    retained_text += size - 1 + len(roots - {0}) + int(0 in roots)
            expected["text_bytes"] = retained_text
        return expected

    def open_(index, operation):
        nonlocal written, retained_text
        documents[index] = {"versions": [0], "saved": 0, "next": 0}
        written += size * (2 if mode == "snapshot" else 1)
        retained_text += size
        return state(operation)

    for index in range(count):
        yield open_(index, "open")
    for round_ in range(rounds):
        for doc in documents:
            doc["next"] += 1
            doc["versions"].append(doc["next"])
            doc["versions"] = doc["versions"][-(history + 1):]
            written += size if mode == "snapshot" else 1
            retained_text += 1
            yield state("edit")
            yield state("undo")
            yield state("redo")
            if round_ % 8 == 0:
                doc["saved"] = doc["next"]
                if mode == "snapshot":
                    written += size
                yield state("mark_saved")
        if round_ % 8 == 0:
            yield state("checkpoint" if mode == "snapshot" else "collect")
    for index in range(0, count, 2):
        documents[index] = None
        yield state("close")
    yield state("checkpoint" if mode == "snapshot" else "collect")
    for index in range(0, count, 2):
        yield open_(index, "reopen")
    documents = [None] * count
    yield state("close_all")


def rows(path, count, size, rounds, history, mode):
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != FIELDS:
            raise ValueError("Unexpected document-store schema")
        data = []
        for raw in reader:
            if None in raw or any(value is None for value in raw.values()):
                raise ValueError("Incomplete document-store row")
            row = {key: value if key == "operation" else int(value) if value else None for key, value in raw.items()}
            if any(row[key] is None or row[key] < 0 for key in FIELDS[1:12]):
                raise ValueError("Invalid document-store accounting")
            if mode == "shared-tree" and any(row[key] is None or row[key] < 0 for key in FIELDS[12:]):
                raise ValueError("Missing shared-tree work counters")
            if mode == "snapshot" and any(row[key] is not None for key in FIELDS[12:]):
                raise ValueError("Snapshot reported unavailable tree counters")
            if not row["used_bytes"] <= row["arena_bytes"] <= row["high_water_bytes"]:
                raise ValueError("Representation/arena/high-water ordering failed")
            if row["used_bytes"] != row["text_bytes"] + row["node_bytes"] or row["node_bytes"] % 56:
                raise ValueError("Text/node representation accounting failed")
            if data and any(row[key] < data[-1][key] for key in ("high_water_bytes", "inserted_bytes")):
                raise ValueError("Monotonic counter went backwards")
            data.append(row)
    expected = list(expected_trace(count, size, rounds, history, mode))
    if len(data) != len(expected):
        raise ValueError("Incomplete document lifetime trace")
    for index, (row, oracle) in enumerate(zip(data, expected)):
        if any(row[key] != value for key, value in oracle.items()):
            raise ValueError(f"Independent version/source oracle mismatch at row {index}: {row} vs {oracle}")
    if data[-1]["used_bytes"] != 0:
        raise ValueError("Cleanup retained document payload/nodes")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="build-core")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--documents", type=int, choices=(3, 16, 64), action="append")
    parser.add_argument("--shape", choices=("lines", "long-line", "unicode"), action="append")
    parser.add_argument("--size", type=int, default=4096)
    parser.add_argument("--iterations", type=int, default=64)
    parser.add_argument("--history", type=int, default=32)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    counts = list(dict.fromkeys(args.documents or [3, 16, 64]))
    shapes = list(dict.fromkeys(args.shape or ["lines", "long-line", "unicode"]))
    if not (2 <= args.size <= 2097152 and 1 <= args.iterations <= 10000 and 1 <= args.history <= 256 and 1 <= args.repeats <= 100 and args.timeout > 0):
        parser.error("Experiment bounds outside supported limits")
    if max(counts) * args.size * (min(args.iterations, args.history) + 4) > 67108864:
        parser.error("Pessimistic snapshot budget exceeds 64 MiB; reduce size, history or count")
    build = Path(args.build).resolve()
    program = executable(build, args.configuration, "document_store_profile")
    contract = executable(build, args.configuration, "document_store_contract")
    values = cache(build)
    checkout = Path(values["GOOSE_SOURCE_DIR"])
    compiler = executable(build / "goose", args.configuration, "goose")
    sources = [*sorted((ROOT / "lib").rglob("*.goose")), ROOT / "tools/experiments/pool_document.goose",
               ROOT / "tools/experiments/document_store_profile.goose", ROOT / "tests/document_store_contract.goose",
               ROOT / "tests/document_store_experiment_fixture.py", Path(__file__).resolve(),
               ROOT / "tools/document_experiment.py", ROOT / "tools/profile.py", ROOT / "tools/run.py"]
    shared_sources = [*sorted((ROOT / "lib").rglob("*.goose")), ROOT / "tools/experiments/pool_document.goose"]
    for binary, entry in ((program, ROOT / "tools/experiments/document_store_profile.goose"), (contract, ROOT / "tests/document_store_contract.goose")):
        if any(path.stat().st_mtime_ns > binary.stat().st_mtime_ns for path in [entry, *shared_sources]):
            raise RuntimeError(f"Rebuild {binary} before recording modified sources")
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    for path in sources:
        target = output / "sources" / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    (output / "lab.diff").write_text(git(ROOT, "diff", "HEAD", "--no-ext-diff"), encoding="utf-8")
    (output / "toolchain.diff").write_text(git(checkout, "diff", "HEAD", "--no-ext-diff"), encoding="utf-8")
    record = {"schema_version": 1, "complete": False, "started_utc": datetime.now(timezone.utc).isoformat(),
              "lab": revision(ROOT), "toolchain": revision(checkout), "history_limit": args.history,
              "source_sha256": {str(p.relative_to(ROOT)): digest(p) for p in sources},
              "compiler_sha256": digest(compiler), "program_sha256": digest(program), "contract_sha256": digest(contract),
              "environment": {"platform": platform.platform(), "python": sys.version, "configuration": args.configuration,
                              "cmake": {k: v for k, v in values.items() if k.startswith(("CMAKE_C_COMPILER", "CMAKE_C_FLAGS"))}},
              "limits": ["Fixed document/history descriptors and temporary collectors are excluded from arena counters.",
                         "Snapshot inserted_bytes counts full-version/baseline copies; shared-tree counts inserted source bytes.",
                         "Collection copy and node-prefix growth relocation are separate; owned exports are outside these counters.",
                         "Snapshot releases runs per edit/close; shared-tree close drops roots and collection reclaims them.",
                         "Only shared-tree collect rows time collection; snapshot checkpoints have zero placeholder duration.",
                         "Retained arena/high-water are logical backing sizes, not RSS or OS-release measurements."],
              "contract": None, "cases": [], "timing_summary": {}}

    def save():
        (output / "results.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")

    save()
    try:
        record["contract"] = run([str(contract), str(output / "saved.txt")], output / "contract.out", output / "contract.err", args.timeout)
        for count in counts:
            for shape in shapes:
                for mode in ("snapshot", "shared-tree"):
                    name = f"{mode}-{count}-{shape}"
                    observations = []
                    for repeat in range(args.repeats):
                        stem = output / f"{name}-{repeat + 1}"
                        command = [str(program), mode, str(count), str(args.size), str(args.iterations), shape, str(args.history)]
                        measurement = run(command, stem.with_suffix(".csv"), stem.with_suffix(".err"), args.timeout)
                        data = rows(stem.with_suffix(".csv"), count, args.size, args.iterations, args.history, mode)
                        observations.extend(data)
                        record["cases"].append({"name": name, "mode": mode, "documents": count, "shape": shape,
                                                "input_bytes": args.size, "iterations": args.iterations, "history": args.history,
                                                "repeat": repeat + 1, "command": command, **measurement,
                                                "raw_csv": stem.with_suffix(".csv").name, "final": data[-1]})
                        save()
                    summary = {}
                    for operation in dict.fromkeys(row["operation"] for row in observations):
                        if operation == "checkpoint":
                            continue
                        durations = [row["elapsed_ns"] for row in observations if row["operation"] == operation]
                        summary[operation] = {"samples": len(durations), "median_ns": percentile(durations, 0.5),
                                              "p95_ns": percentile(durations, 0.95), "p99_ns": percentile(durations, 0.99)}
                    record["timing_summary"][name] = summary
                    print(f"{name}: {args.repeats} independent traces passed", flush=True)
        record["complete"] = True
    except Exception as error:
        record["error"] = str(error)
        raise
    finally:
        record["finished_utc"] = datetime.now(timezone.utc).isoformat()
        save()
    print(f"Recorded {len(record['cases'])} processes on one toolchain in {output}")


if __name__ == "__main__":
    main()
