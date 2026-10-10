"""Compare minimal Goose pool traces across explicitly selected toolchain builds."""
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
FIELDS = ["operation", "elapsed_ns", "logical_bytes", "capacity_bytes", "high_water_bytes",
          "free_bytes", "largest_free_run_bytes", "moved_capacity_bytes", "zeroed_growth_bytes",
          "application_write_bytes", "moves", "realloc_calls"]


def read_rows(path, count, step, rounds):
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != FIELDS:
            raise ValueError("Unexpected runtime pool CSV schema")
        data = []
        for raw in reader:
            if None in raw or any(raw[key] is None for key in FIELDS):
                raise ValueError("Incomplete runtime pool measurement")
            row = {key: value if key == "operation" else int(value) if value else None
                   for key, value in raw.items()}
            if row["elapsed_ns"] is None and row["operation"] != "append_reserved":
                raise ValueError("An allocator call has no duration")
            if row["elapsed_ns"] is not None and row["elapsed_ns"] < 0:
                raise ValueError("Negative allocator-call duration")
            if any(row[key] is None or row[key] < 0 for key in FIELDS[2:]):
                raise ValueError("Invalid pool accounting")
            if not row["logical_bytes"] <= row["capacity_bytes"] <= row["high_water_bytes"]:
                raise ValueError("Logical/capacity/high-water ordering failed")
            if row["free_bytes"] != row["high_water_bytes"] - row["capacity_bytes"]:
                raise ValueError("Free bytes do not match retained capacity")
            if row["largest_free_run_bytes"] > row["free_bytes"]:
                raise ValueError("Largest free run exceeds total free bytes")
            data.append(row)
    expected = count * rounds + count + 1
    if len(data) != expected or data[-1]["operation"] != "reuse_probe" or data[-1]["capacity_bytes"] != 0:
        raise ValueError("Incomplete trace/cleanup")
    if data[count * rounds - 1]["logical_bytes"] != count * step * rounds:
        raise ValueError("The logical workload did not finish")
    if data[-1]["application_write_bytes"] != count * step * rounds:
        raise ValueError("Application work differs from the requested workload")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="append", required=True, help="Repeat to compare toolchains")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--documents", type=int, action="append", choices=range(1, 65))
    parser.add_argument("--step", type=int, default=256)
    parser.add_argument("--rounds", type=int, default=64)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output")
    args = parser.parse_args()
    counts = list(dict.fromkeys(args.documents or [3, 16, 64]))
    if not (1 <= args.step <= 65536 and 1 <= args.rounds <= 256 and 1 <= args.repeats <= 100 and args.timeout > 0):
        parser.error("Invalid size, round, repeat or timeout bounds")
    if max(counts) * args.step * args.rounds * (args.rounds + 1) > 134217728:
        parser.error("The pessimistic allocation trace bound exceeds 128 MiB")
    source = ROOT / "tools/experiments/runtime/pool_runtime.goose"
    builds = []
    for index, argument in enumerate(args.build):
        build = Path(argument).resolve()
        values = cache(build)
        program = executable(build, args.configuration, "pool_runtime")
        compiler = executable(build / "goose", args.configuration, "goose")
        exhaustion = executable(build, args.configuration, "pool_exhaustion")
        if source.stat().st_mtime_ns > program.stat().st_mtime_ns:
            raise RuntimeError(f"Rebuild {program} before recording modified sources")
        if source.with_name("reservation_exhaustion.goose").stat().st_mtime_ns > exhaustion.stat().st_mtime_ns:
            raise RuntimeError(f"Rebuild {exhaustion} before recording modified sources")
        checkout = Path(values["GOOSE_SOURCE_DIR"])
        builds.append((program, {
            "label": f"toolchain-{index + 1}", "build": str(build), "checkout": str(checkout),
            **revision(checkout), "program_sha256": digest(program), "compiler_sha256": digest(compiler),
            "exhaustion_program_sha256": digest(exhaustion), "exhaustion_reservation_bytes": 1048576,
            "configuration": args.configuration,
            "cmake": {key: value for key, value in values.items()
                      if key.startswith(("CMAKE_C_COMPILER", "CMAKE_C_FLAGS", "CMAKE_CXX_COMPILER", "CMAKE_CXX_FLAGS", "GOOSE_"))
                      or key == "CMAKE_GENERATOR"},
        }))
    output = Path(args.output).resolve() if args.output else Path(args.build[0]).resolve() / "experiments" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    output.mkdir(parents=True, exist_ok=False)
    sources = [source, source.with_name("CMakeLists.txt"), source.with_name("index_of_descriptor.goose"), source.with_name("reservation_exhaustion.goose"), Path(__file__).resolve(),
               ROOT / "tests/pool_compiler_fixture.py", ROOT / "tests/pool_runtime_experiment_fixture.py",
               ROOT / "tests/pool_exhaustion_fixture.py",
               ROOT / "tools/document_experiment.py", ROOT / "tools/profile.py", ROOT / "tools/run.py"]
    for path in sources:
        target = output / "sources" / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    (output / "lab.diff.patch").write_text(git(ROOT, "diff", "HEAD", "--no-ext-diff") + "\n", encoding="utf-8")
    for program, build in builds:
        (output / f"{build['label']}.diff.patch").write_text(git(Path(build["checkout"]), "diff", "HEAD", "--no-ext-diff") + "\n", encoding="utf-8")
    record = {
        "schema_version": 1, "started_utc": datetime.now(timezone.utc).isoformat(),
        "hypothesis": "Growth policy can reduce copying using existing Goose slice pools; separated free runs and stale views have distinct contracts.",
        "comparison": "Exact vs geometric capacity growth, same interleaved logical appends; identical minimal source on explicitly pinned toolchains.",
        "lab": revision(ROOT), "source_sha256": {str(path.relative_to(ROOT)): digest(path) for path in sources},
        "environment": {"platform": platform.platform(), "machine": platform.machine(), "python": sys.version},
        "toolchains": [build for program, build in builds], "contracts": [], "diagnostics": [], "exhaustion": [], "cases": [], "timing_summary": {},
        "measurement_limits": [
            "Only reallocation/free/allocation calls are timed; payload checks/writes, observation and CSV output are outside those durations.",
            "Reserved appends have no allocator call and an empty duration, not a zero-time measurement.",
            "Moved capacity bytes are inferred from relocation and old capacity, not a runtime instrumentation counter.",
            "Zeroed growth bytes are logical initialization volume, not a count of physical stores or committed pages.",
            "Counters cover the growth workload; local contracts and the full-pool reuse probe are excluded.",
            "No Undo, saved snapshot, document preflight or GUI exists in this source; these results isolate a different workload.",
            "OS peaks are sampled; runtime reservation/commit counters and recovery are unmeasured. Exhaustion is a separate 1 MiB-reservation child probe.",
        ], "complete": False,
    }
    manifest = output / "results.json"
    def save():
        manifest.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    save()
    try:
        # Correctness on every toolchain before any comparative timing.
        for program, build in builds:
            label = build["label"]
            command = [str(program), "contract", "3", str(args.step), "4"]
            measurement = run(command, output / f"{label}-contract.out", output / f"{label}-contract.err", args.timeout)
            if (output / f"{label}-contract.out").read_text(encoding="utf-8").strip() != "pool runtime contract OK":
                raise ValueError("Missing successful contract marker")
            record["contracts"].append({"toolchain": label, "command": command, **measurement})
            diagnostic_command = [sys.executable, str(ROOT / "tests/pool_compiler_fixture.py"),
                                  str(executable(Path(build["build"]) / "goose", args.configuration, "goose")),
                                  str(Path(build["checkout"]) / "stdlib"), str(source.with_name("index_of_descriptor.goose"))]
            diagnostic = run(diagnostic_command, output / f"{label}-diagnostic.out", output / f"{label}-diagnostic.err", args.timeout)
            record["diagnostics"].append({"toolchain": label, "command": diagnostic_command, **diagnostic})
            exhaustion_command = [sys.executable, str(ROOT / "tests/pool_exhaustion_fixture.py"),
                                  str(executable(Path(build["build"]), args.configuration, "pool_exhaustion"))]
            failure = run(exhaustion_command, output / f"{label}-exhaustion.out", output / f"{label}-exhaustion.err", args.timeout)
            record["exhaustion"].append({"toolchain": label, "command": exhaustion_command, **failure})
        for program, build in builds:
            for count in counts:
                for mode in ("exact", "geometric"):
                    name = f"{build['label']}-{mode}-{count}"
                    observations = []
                    for repeat in range(args.repeats):
                        stem = output / f"{name}-{repeat + 1}"
                        command = [str(program), mode, str(count), str(args.step), str(args.rounds)]
                        measurement = run(command, stem.with_suffix(".csv"), stem.with_suffix(".err"), args.timeout)
                        data = read_rows(stem.with_suffix(".csv"), count, args.step, args.rounds)
                        observations.extend(data)
                        record["cases"].append({"name": name, "repeat": repeat + 1, "documents": count,
                                                "step_bytes": args.step, "rounds": args.rounds, "mode": mode,
                                                "command": command, "raw_csv": stem.with_suffix(".csv").name,
                                                "growth_end": data[count * args.rounds - 1], "final": data[-1], **measurement})
                        save()
                    summary = {}
                    for operation in ("realloc", "free", "reuse_probe"):
                        timings = [row["elapsed_ns"] for row in observations if row["operation"] == operation]
                        summary[operation] = {"samples": len(timings), "total_ns": sum(timings),
                                              "median_ns": percentile(timings, .5), "p95_ns": percentile(timings, .95),
                                              "p99_ns": percentile(timings, .99)}
                    record["timing_summary"][name] = summary
                    print(f"{name}: moved={data[-1]['moved_capacity_bytes']}B high_water={data[-1]['high_water_bytes']}B realloc_calls={data[-1]['realloc_calls']}")
        record["complete"] = True
        record["conclusion"] = "The minimal contracts passed on each recorded toolchain. Evaluate growth-policy copy/retention and allocator time separately before proposing language/runtime changes."
    except Exception as error:
        record["error"] = str(error)
        raise
    finally:
        save()
        print(f"Recorded {manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
