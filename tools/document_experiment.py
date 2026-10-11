"""Reproducible, GUI-free document experiments (Python standard library only)."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

from profile import memory
from run import executable


ROOT = Path(__file__).resolve().parents[1]
CASES = {
    **{f"snapshot-{count}": ("snapshot", count, "lines") for count in (3, 16, 64)},
    **{f"{mode}-{shape}": (mode, 1, shape)
       for shape in ("lines", "long-line", "unicode") for mode in ("snapshot", "piece-tree")},
}
FIELDS = ["operation", "elapsed_ns", "documents", "current_bytes", "saved_bytes",
          "undo_bytes", "used_bytes", "pool_high_water_bytes", "pool_free_bytes",
          "largest_free_run_bytes", "copied_bytes", "zeroed_bytes", "allocations", "preflight_scans"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(root, *args):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True,
                            encoding="utf-8", errors="replace", timeout=15)
    if result.returncode:
        raise RuntimeError(f"Cannot record Git provenance for {root}: {result.stderr.strip()}")
    return result.stdout.strip()


def revision(root):
    status = git(root, "status", "--porcelain")
    diff = git(root, "diff", "HEAD", "--no-ext-diff")
    return {"revision": git(root, "rev-parse", "HEAD"), "status": status,
            "dirty": bool(status), "tracked_diff_sha256": hashlib.sha256(diff.encode()).hexdigest()}


def cache(build):
    values = {}
    for line in (build / "CMakeCache.txt").read_text(encoding="utf-8").splitlines():
        found = re.match(r"([^:#]+):[^=]+=(.*)", line)
        if found:
            values[found[1]] = found[2]
    return values


def percentile(values, fraction):
    """Nearest rank, with no interpolation or discarding of slow samples."""
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def rows(path, mode):
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != FIELDS:
            raise ValueError(f"Unexpected measurement schema in {path}")
        data = []
        for row in reader:
            if None in row or any(row[key] is None for key in FIELDS):
                raise ValueError(f"Incomplete measurement in {path}: {row}")
            item = {key: int(value) if key != "operation" and value else value
                    for key, value in row.items()}
            if item["elapsed_ns"] < 0:
                raise ValueError("Negative operation duration")
            if mode == "snapshot":
                if item["used_bytes"] != item["current_bytes"] + item["saved_bytes"] + item["undo_bytes"]:
                    raise ValueError("Owned storage accounting is inconsistent")
                if item["pool_free_bytes"] != item["pool_high_water_bytes"] - item["used_bytes"]:
                    raise ValueError("Free storage accounting is inconsistent")
            data.append(item)
    if not data or (mode == "snapshot" and (data[-1]["operation"] != "close_all" or data[-1]["used_bytes"] != 0)):
        raise ValueError("Measurement did not complete cleanup")
    return data


def run(command, stdout, stderr, timeout):
    started = time.monotonic()
    peak = {}
    samples = 0
    with stdout.open("wb") as out, stderr.open("wb") as err:
        options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
        process = subprocess.Popen(command, cwd=ROOT, stdout=out, stderr=err, **options)
        try:
            while process.poll() is None:
                if time.monotonic() - started > timeout:
                    raise TimeoutError(f"Experiment exceeded {timeout}s: {command}")
                usage = memory(process.pid)
                if usage:
                    samples += 1
                    for key, value in usage.items():
                        peak[key] = max(peak.get(key, 0), value)
                time.sleep(0.01)
            code = process.wait()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    if code:
        raise RuntimeError(f"Experiment exited {code}; see {stderr}")
    return {"exit_code": code, "wall_seconds": time.monotonic() - started,
            "sampled_peak_bytes": peak or None, "memory_sample_count": samples,
            "memory_sample_interval_ms": 10}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="build-core")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--case", choices=CASES, action="append", dest="cases")
    parser.add_argument("--size", type=int, default=4096)
    parser.add_argument("--iterations", type=int, default=64)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output", help="A new output directory; never overwrites an earlier run")
    args = parser.parse_args()
    if not (1 <= args.size <= 2097152 and 1 <= args.iterations <= 10000 and 1 <= args.repeats <= 100 and args.timeout > 0):
        parser.error("Size, iterations, repeats or timeout are outside supported bounds")
    selected = args.cases or list(CASES)
    for name in selected:
        mode, count, shape = CASES[name]
        if mode == "snapshot" and count * args.size * (min(args.iterations, 32) + 4) > 67108864:
            parser.error(f"{name} would exceed the snapshot pool budget; reduce size or document count")
    build = Path(args.build).resolve()
    program = executable(build, args.configuration, "document_profile")
    contract = executable(build, args.configuration, "multi_document_contract")
    values = cache(build)
    toolchain = Path(values["GOOSE_SOURCE_DIR"])
    compiler = executable(build / "goose", args.configuration, "goose")
    output = Path(args.output).resolve() if args.output else build / "experiments" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    sources = [ROOT / "tools/document_experiment.py", ROOT / "tools/profile.py", ROOT / "tools/run.py",
               ROOT / "tools/experiments/document_profile.goose", ROOT / "tools/experiments/pool_document.goose",
               ROOT / "tests/multi_document_contract.goose", ROOT / "lib/lab/document/model.goose",
               ROOT / "lib/lab/document/piece_tree.goose", ROOT / "tests/document_experiment_fixture.py"]
    dependency_sources = [*sorted((ROOT / "lib").rglob("*.goose")), sources[4]]
    # A recorded source hash is useful only when the corresponding binary was
    # rebuilt. The runtime probe and contract have separate dependency closures.
    for binary, inputs in ((program, [sources[3], *dependency_sources]), (contract, [sources[5], *dependency_sources])):
        if any(path.stat().st_mtime_ns > binary.stat().st_mtime_ns for path in inputs):
            raise RuntimeError(f"Rebuild {binary.name} before recording modified sources")
    sources = list(dict.fromkeys([*sources, *dependency_sources]))
    output.mkdir(parents=True, exist_ok=False)
    for source in sources:
        destination = output / "sources" / source.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    (output / "lab.diff.patch").write_text(git(ROOT, "diff", "HEAD", "--no-ext-diff") + "\n", encoding="utf-8")
    (output / "toolchain.diff.patch").write_text(git(toolchain, "diff", "HEAD", "--no-ext-diff") + "\n", encoding="utf-8")
    record = {
        "schema_version": 2, "started_utc": datetime.now(timezone.utc).isoformat(),
        "hypothesis": "Slice pools can isolate resident documents, history and saved state; full snapshots make small edits copy whole texts.",
        "comparison": "Contiguous immutable snapshots vs the existing single-document persistent piece tree (one-document cases only).",
        "proposal_target": "goose-lab representation first; runtime allocation/observability only if measured costs remain.",
        "lab": revision(ROOT), "toolchain": revision(toolchain),
        "source_sha256": {str(path.relative_to(ROOT)): digest(path) for path in sources},
        "program_sha256": digest(program), "contract_sha256": digest(contract), "compiler_sha256": digest(compiler),
        "environment": {"platform": platform.platform(), "machine": platform.machine(),
                        "python": sys.version, "configuration": args.configuration,
                        "cmake": {key: value for key, value in values.items()
                                  if key.startswith(("CMAKE_C_COMPILER", "CMAKE_C_FLAGS", "CMAKE_CXX_COMPILER", "CMAKE_CXX_FLAGS"))
                                  or key in ("CMAKE_GENERATOR", "GOOSE_LAB_GUI", "GOOSE_LAB_BUILD_TOOLS")}},
        "measurement_limits": ["OS peaks are sampled, not exact; missing samples are null.",
                               "Runtime reservation/commit and native allocation counters are unavailable.",
                               "Snapshot counters cover pool writes/zero initialization, not owned result copies, descriptors or profiler output.",
                               "Operation durations exclude stats and CSV output; process wall time includes both.",
                               "mark_saved measures model adoption, not filesystem I/O; the contract separately verifies atomic write success/failure.",
                               "This is a short headless test; GUI shaping and long-session stability are unmeasured.",
                               "Binaries are hashed; source changes after a build require rebuilding to match the recorded source revision."],
        "contract": None, "cases": [], "complete": False,
    }
    manifest = output / "results.json"
    def save():
        manifest.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    save()
    try:
        record["contract"] = run([str(contract), str(output / "saved.txt")], output / "contract.out", output / "contract.err", args.timeout)
        for name in selected:
            mode, count, shape = CASES[name]
            observations = []
            for repeat in range(args.repeats):
                stem = output / f"{name}-{repeat + 1}"
                command = [str(program), mode, str(count), str(args.size), str(args.iterations), shape]
                measurement = run(command, stem.with_suffix(".csv"), stem.with_suffix(".err"), args.timeout)
                data = rows(stem.with_suffix(".csv"), mode)
                observations.extend(data)
                record["cases"].append({"name": name, "repeat": repeat + 1, "mode": mode,
                                        "documents": count, "input_bytes_per_document": args.size,
                                        "iterations": args.iterations, "shape": shape, "command": command,
                                        "raw_csv": stem.with_suffix(".csv").name, **measurement,
                                        "final": data[-1]})
                save()
            summary = {}
            for operation in dict.fromkeys(row["operation"] for row in observations):
                timings = [row["elapsed_ns"] for row in observations if row["operation"] == operation]
                summary[operation] = {"samples": len(timings), "median_ns": percentile(timings, 0.5),
                                      "p95_ns": percentile(timings, 0.95), "p99_ns": percentile(timings, 0.99)}
            record.setdefault("timing_summary", {})[name] = summary
            print(f"{name}: edit median={summary['edit']['median_ns']}ns p95={summary['edit']['p95_ns']}ns")
        record["complete"] = True
        record["conclusion"] = "The contract passed for independent edits, real save publication/failure, selection, history, budget refusal and stale IDs at 3/16/64 documents. Performance conclusions require comparing the recorded cases and their limits."
    except Exception as error:
        record["error"] = str(error)
        raise
    finally:
        save()
        print(f"Recorded {manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
