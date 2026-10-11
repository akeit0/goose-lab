"""Compare geometric runs and fixed chunks on the same validated buffer lifetimes."""
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
FIELDS = ["phase", "operation", "elapsed_ns", "logical_bytes", "capacity_bytes", "high_water_bytes",
          "free_bytes", "largest_free_run_bytes", "moved_capacity_bytes", "zeroed_bytes",
          "application_write_bytes", "alloc_calls", "realloc_calls", "free_calls", "live_runs",
          "metadata_live_slots", "metadata_high_water_slots", "read_calls", "address_visits"]
UNTIMED = {"append_reserved", "growth_end", "retired_end", "reopened_end", "cleanup_end"}


def envelope(count, step, rounds, chunk_size, workload, indexed=False):
    maximum = step * rounds * (1 if workload == "uniform" else 5)
    reopened = (count + 1) // 2 if workload == "churn" else 0
    work_bound = count * maximum + reopened * step * max(1, rounds // 2) * 5
    if max(work_bound * 4, work_bound + (count + reopened) * chunk_size) > 134217728:
        raise ValueError("Pessimistic allocation trace bound exceeds 128 MiB")
    if count * ((maximum + chunk_size - 1) // chunk_size) > 4096:
        raise ValueError("Chunk metadata envelope exceeds 4096 slots")
    if indexed and (maximum > 2097152 or (maximum + chunk_size - 1) // chunk_size > 512):
        raise ValueError("Indexed buffer byte/directory envelope exceeds library limits")


def expected_trace(count, step, rounds, chunk_size, workload, mode):
    """Independent integer oracle for logical work, capacity, calls and addressing."""
    used = [0] * count
    capacities = [0] * count
    counters = dict.fromkeys(["zeroed_bytes", "application_write_bytes", "alloc_calls", "realloc_calls",
                              "free_calls", "metadata_high_water_slots", "read_calls", "address_visits"], 0)
    chunked = mode in ("chunked", "indexed")

    def state(phase, operation):
        live = sum(capacity // chunk_size if chunked else int(capacity > 0) for capacity in capacities)
        if chunked:
            counters["metadata_high_water_slots"] = max(counters["metadata_high_water_slots"], live)
        return {"phase": phase, "operation": operation, "logical_bytes": sum(used),
                "capacity_bytes": sum(capacities), "live_runs": live,
                "metadata_live_slots": live if chunked else 0, **counters}

    def append(index, round_, phase):
        size = step * (1 if workload == "uniform" else index % 4 + 1 + round_ % 2)
        required = used[index] + size
        old = capacities[index]
        target = ((required + chunk_size - 1) // chunk_size) * chunk_size if chunked else max(required, old * 2) if required > old else old
        operation = "append_reserved"
        if target > old:
            counters["zeroed_bytes"] += target - old
            if chunked:
                counters["alloc_calls"] += (target - old) // chunk_size
                operation = "append_alloc"
            else:
                counters["realloc_calls"] += 1
                operation = "append_realloc"
        used[index] = required
        capacities[index] = target
        counters["application_write_bytes"] += size
        if mode == "indexed":
            operation = "append_library"
        return state(phase, operation)

    def close(index, phase):
        counters["free_calls"] += capacities[index] // chunk_size if chunked else int(capacities[index] > 0)
        used[index] = capacities[index] = 0
        return state(phase, "close_library" if mode == "indexed" else "close")

    def read(phase):
        for index, size in enumerate(used):
            if size:
                for sample in range(64):
                    offset = (sample * 7919 + index * 101) % size
                    counters["read_calls"] += 1
                    counters["address_visits"] += offset // chunk_size + 1 if mode == "chunked" else 1
        return state(phase, "read_probe")

    for round_ in range(rounds):
        for index in range(count):
            yield append(index, round_, "grow")
    yield state("grow", "growth_end")
    yield read("grow")
    if workload == "churn":
        for index in range(0, count, 2):
            yield close(index, "retire")
        yield state("retire", "retired_end")
        for round_ in range(max(1, rounds // 2)):
            for index in range(0, count, 2):
                yield append(index, round_ + rounds, "reopen")
        yield state("reopen", "reopened_end")
        yield read("reopen")
    for parity in range(2):
        for index in range(parity, count, 2):
            yield close(index, "cleanup")
    yield state("cleanup", "cleanup_end")
    yield state("cleanup", "reuse_library" if mode == "indexed" else "reuse_probe")


def read_rows(path, count, step, rounds, chunk_size, workload, mode):
    with path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != FIELDS:
            raise ValueError("Unexpected buffer-storage CSV schema")
        data = []
        for raw in reader:
            if None in raw or any(raw[key] is None for key in FIELDS):
                raise ValueError("Incomplete buffer-storage measurement")
            row = {key: value if key in ("phase", "operation") else int(value) if value else None
                   for key, value in raw.items()}
            if (row["elapsed_ns"] is None) != (row["operation"] in UNTIMED):
                raise ValueError("Allocator/read timing presence does not match the operation")
            if row["elapsed_ns"] is not None and row["elapsed_ns"] < 0:
                raise ValueError("Negative operation duration")
            if any(row[key] is None or row[key] < 0 for key in FIELDS[3:]):
                raise ValueError("Invalid buffer-storage accounting")
            if not row["logical_bytes"] <= row["capacity_bytes"] <= row["high_water_bytes"]:
                raise ValueError("Logical/capacity/high-water ordering failed")
            if row["free_bytes"] != row["high_water_bytes"] - row["capacity_bytes"] or row["largest_free_run_bytes"] > row["free_bytes"]:
                raise ValueError("Inconsistent pool free-storage accounting")
            if data and (row["high_water_bytes"] < data[-1]["high_water_bytes"] or row["moved_capacity_bytes"] < data[-1]["moved_capacity_bytes"]):
                raise ValueError("High-water or copy counter went backwards")
            if mode in ("chunked", "indexed") and row["moved_capacity_bytes"] != 0:
                raise ValueError("A fixed chunk reported relocation")
            data.append(row)
    expected = list(expected_trace(count, step, rounds, chunk_size, workload, mode))
    if len(data) != len(expected):
        raise ValueError("Incomplete lifetime trace")
    for index, (row, oracle) in enumerate(zip(data, expected)):
        if any(row[key] != value for key, value in oracle.items()):
            raise ValueError(f"Logical/capacity/call/address oracle mismatch at row {index}: {row} vs {oracle}")
    if data[-1]["capacity_bytes"] or data[-1]["largest_free_run_bytes"] != data[-1]["high_water_bytes"]:
        raise ValueError("Full cleanup/reuse accounting failed")
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="append", required=True)
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--documents", type=int, action="append", choices=range(1, 65))
    parser.add_argument("--workload", action="append", choices=("uniform", "mixed", "churn"))
    parser.add_argument("--mode", action="append", choices=("geometric", "chunked", "indexed"))
    parser.add_argument("--chunk-bytes", type=int, action="append")
    parser.add_argument("--step", type=int, default=256)
    parser.add_argument("--rounds", type=int, default=64)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output")
    args = parser.parse_args()
    counts = list(dict.fromkeys(args.documents or [3, 16, 64]))
    workloads = list(dict.fromkeys(args.workload or ["uniform", "mixed", "churn"]))
    sizes = list(dict.fromkeys(args.chunk_bytes or [4096]))
    modes = list(dict.fromkeys(args.mode or ["geometric", "chunked", "indexed"]))
    if not (1 <= args.step <= 65536 and 1 <= args.rounds <= 256 and 1 <= args.repeats <= 100 and args.timeout > 0 and all(1 <= size <= 65536 for size in sizes)):
        parser.error("Invalid workload bounds")
    try:
        for count in counts:
            for size in sizes:
                for workload in workloads:
                    envelope(count, args.step, args.rounds, size, workload, "indexed" in modes)
    except ValueError as error:
        parser.error(str(error))
    source = ROOT / "tools/experiments/runtime/buffer_storage.goose"
    toolchains = []
    for index, argument in enumerate(args.build):
        build = Path(argument).resolve()
        program = executable(build, args.configuration, "buffer_storage")
        if source.stat().st_mtime_ns > program.stat().st_mtime_ns:
            raise RuntimeError(f"Rebuild {program} before recording modified sources")
        values = cache(build)
        checkout = Path(values["GOOSE_SOURCE_DIR"])
        compiler = executable(build / "goose", args.configuration, "goose")
        indexed_program = executable(build, args.configuration, "indexed_buffer") if "indexed" in modes else None
        if indexed_program and any(path.stat().st_mtime_ns > indexed_program.stat().st_mtime_ns for path in
                                   [source.with_name("indexed_buffer.goose"), ROOT / "lib/lab/buffer/indexed.goose"]):
            raise RuntimeError(f"Rebuild {indexed_program} before recording modified library sources")
        toolchains.append({"label": f"toolchain-{index + 1}", "build": str(build), "checkout": str(checkout),
                           **revision(checkout), "program": str(program), "program_sha256": digest(program),
                           "compiler_sha256": digest(compiler), "configuration": args.configuration,
                           "indexed_program": str(indexed_program) if indexed_program else None,
                           "indexed_program_sha256": digest(indexed_program) if indexed_program else None,
                           "cmake": {key: value for key, value in values.items() if key.startswith(("CMAKE_C_COMPILER", "CMAKE_C_FLAGS", "CMAKE_CXX_COMPILER", "CMAKE_CXX_FLAGS", "GOOSE_")) or key == "CMAKE_GENERATOR"}})
    output = Path(args.output).resolve() if args.output else Path(args.build[0]).resolve() / "experiments" / datetime.now(timezone.utc).strftime("storage-%Y%m%dT%H%M%S.%fZ")
    output.mkdir(parents=True, exist_ok=False)
    sources = [source, source.with_name("indexed_buffer.goose"), ROOT / "lib/lab/buffer/indexed.goose", ROOT / "tests/indexed_buffer_contract.goose",
               source.with_name("CMakeLists.txt"), Path(__file__).resolve(), ROOT / "tests/buffer_storage_experiment_fixture.py",
               ROOT / "tools/document_experiment.py", ROOT / "tools/profile.py", ROOT / "tools/run.py"]
    for path in sources:
        target = output / "sources" / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    (output / "lab.diff.patch").write_text(git(ROOT, "diff", "HEAD", "--no-ext-diff") + "\n", encoding="utf-8")
    for toolchain in toolchains:
        (output / f"{toolchain['label']}.diff.patch").write_text(git(Path(toolchain["checkout"]), "diff", "HEAD", "--no-ext-diff") + "\n", encoding="utf-8")
    record = {"schema_version": 2, "started_utc": datetime.now(timezone.utc).isoformat(), "lab": revision(ROOT),
              "hypothesis": "Fixed chunks avoid payload relocation at the cost of metadata and addressing work using existing Goose.",
              "comparison": "Geometric runs, linked pool chunks and the indexed Goose library; equal deterministic payload/read/lifetime operations.",
              "source_sha256": {str(path.relative_to(ROOT)): digest(path) for path in sources},
              "environment": {"platform": platform.platform(), "machine": platform.machine(), "python": sys.version},
              "toolchains": toolchains, "modes": modes, "cases": [], "timing_summary": {}, "complete": False,
              "indexed_metadata": {"reserved_directory_entries": 32768, "reserved_freelist_entries": 4096,
                                   "entry_type": "i32", "raw_entry_bytes": 147456,
                                   "limits": "Counts exclude buffer fields, array length headers and native padding."},
              "measurement_limits": [
                  "Allocator durations sum only native allocation/reallocation/free calls; bookkeeping, validation, writes and CSV are excluded.",
                  "Indexed append_library/close_library/reuse_library time the complete library operation, including writes/metadata. They are distinct from control allocator-only timings and cannot be compared as allocator latency.",
                  "Read probes include addressing, visit counters and assertions for 64 deterministic reads per live buffer; they are not allocator measurements.",
                  "Moved bytes are inferred from relocation and old capacity; zeroed bytes count logical initialization volume.",
                  "Control metadata is counted in slots, not native bytes. Geometric and linked controls share a binary with the fixed 4096-slot table; RSS does not isolate its overhead.",
                  "The geometric/linked controls share their binary. The indexed library has a separate binary and explicit Store with fixed directory/freelist capacity; its reserved entries are recorded independently of live chunk slots.",
                  "The indexed library uses a grow-only arena and a library freelist rather than runtime alloc_slice. Counters count logical chunk allocation/release, not native pool calls.",
                  "Counters cover growth, close and reopening, but exclude the final full-pool reuse probe.",
                  "Owned export is covered by the library contract, not a timed equal-work contiguous-consumer benchmark. No document Undo, recoverable OS allocation or OS-memory release is tested."]}
    manifest = output / "results.json"
    def save():
        manifest.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    save()
    try:
        for toolchain in toolchains:
            for count in counts:
                for size in sizes:
                    for workload in workloads:
                        for mode in modes:
                            name = f"{toolchain['label']}-{mode}-{workload}-{count}-{size}"
                            observations = []
                            for repeat in range(args.repeats):
                                stem = output / f"{name}-{repeat + 1}"
                                program = toolchain["indexed_program"] if mode == "indexed" else toolchain["program"]
                                command = [program, mode, str(count), str(args.step), str(args.rounds), str(size), workload]
                                measurement = run(command, stem.with_suffix(".csv"), stem.with_suffix(".err"), args.timeout)
                                data = read_rows(stem.with_suffix(".csv"), count, args.step, args.rounds, size, workload, mode)
                                observations.extend(data)
                                record["cases"].append({"name": name, "repeat": repeat + 1, "documents": count,
                                                        "chunk_bytes": size, "step_bytes": args.step, "rounds": args.rounds,
                                                        "mode": mode, "workload": workload, "command": command,
                                                        "raw_csv": stem.with_suffix(".csv").name,
                                                        "checkpoints": {row["operation"]: row for row in data if row["operation"].endswith("_end")},
                                                        "final": data[-1], **measurement})
                                save()
                            summary = {}
                            for operation in ("append_alloc", "append_realloc", "close", "read_probe", "reuse_probe", "append_library", "close_library", "reuse_library"):
                                timings = [row["elapsed_ns"] for row in observations if row["operation"] == operation]
                                summary[operation] = {"samples": len(timings), "total_ns": sum(timings),
                                                      **({key: percentile(timings, fraction) for key, fraction in (("median_ns", .5), ("p95_ns", .95), ("p99_ns", .99))} if timings else {})}
                            record["timing_summary"][name] = summary
                            print(f"{name}: moved={data[-1]['moved_capacity_bytes']}B high_water={data[-1]['high_water_bytes']}B metadata_slots={data[-1]['metadata_high_water_slots']} visits={data[-1]['address_visits']}")
        record["complete"] = True
    except Exception as error:
        record["error"] = str(error)
        raise
    finally:
        save()
        print(f"Recorded {manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
