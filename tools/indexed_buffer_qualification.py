"""Qualify one Goose toolchain with bounded capacity and long byte-buffer traces."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

from document_experiment import cache, digest, git, revision
from run import executable

ROOT = Path(__file__).resolve().parents[1]
CAPACITY_LINE = "maximum capacity: 4096 chunks, 64 reuse cycles, high-water 16777216 passed"


def expected_coverage(rounds, seed):
    """Independent RNG/branch oracle; close/refusal choices do not depend on length."""
    reopens = refusals = 0
    for _ in range(rounds):
        seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
        choice = (seed >> 24) % 7
        reopens += choice == 0
        refusals += choice == 3
    return reopens, refusals


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="build")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--rounds", type=int, default=30000)
    parser.add_argument("--seed", type=int, action="append")
    parser.add_argument("--level", type=int, choices=(0, 1, 2), action="append")
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output", required=True, help="A new directory; never overwrite a run")
    args = parser.parse_args()
    seeds = list(dict.fromkeys(args.seed or [238147, 3984127, 4294967294]))
    levels = list(dict.fromkeys(args.level or [0, 1, 2]))
    if not (900 <= args.rounds <= 1000000 and args.timeout > 0 and all(0 <= seed <= 4294967295 for seed in seeds)):
        parser.error("Rounds, seed or timeout outside supported bounds")
    build = Path(args.build).resolve()
    checkout = Path(cache(build)["GOOSE_SOURCE_DIR"]).resolve()
    compiler = executable(build / "goose", args.configuration, "goose")
    helper = checkout / "scripts/toolchain.py"
    spec = importlib.util.spec_from_file_location("goose_lab_qualification_toolchain", helper)
    tc = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = tc
    spec.loader.exec_module(tc)
    cc = tc.test_cc("native")
    if cc is None:
        parser.error("No native C compiler found by the selected Goose checkout")
    output = Path(args.output).resolve()
    try:
        output.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        parser.error("Output directory already exists; choose a new run directory")
    sources = output / "sources"
    inputs = [ROOT / "tests/indexed_buffer_contract.goose", ROOT / "lib/lab/buffer/indexed.goose", Path(__file__).resolve()]
    hashes = {}
    for source in inputs:
        relative = source.relative_to(ROOT)
        target = sources / "lab" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        hashes[str(relative).replace("\\", "/")] = digest(target)
    # Compile the snapshots, so every recorded run uses exactly these source bytes.
    shutil.copytree(checkout / "stdlib", sources / "stdlib")
    shutil.copyfile(helper, sources / "toolchain.py")
    cc_path = shutil.which(cc.cc)
    report = {
        "schema_version": 1, "complete": False, "started_utc": datetime.now(timezone.utc).isoformat(),
        "lab": revision(ROOT), "toolchain": revision(checkout), "build": str(build),
        "compiler": str(compiler), "compiler_sha256": digest(compiler),
        "native_compiler": {"name": cc.name, "description": cc.desc, "path": cc_path or cc.cc,
                            "sha256": digest(Path(cc_path)) if cc_path else None, "optimization": 2},
        "platform": platform.platform(), "python": sys.version, "rounds_per_count": args.rounds,
        "counts": [3, 16, 64], "seeds": seeds, "levels": levels, "source_sha256": hashes,
        "toolchain_helper_sha256": digest(sources / "toolchain.py"),
        "stdlib_sha256": {str(p.relative_to(sources / "stdlib")).replace("\\", "/"): digest(p)
                          for p in sorted((sources / "stdlib").rglob("*")) if p.is_file()},
        "limits": "Correctness and retained arena bounds; not hours of uptime, OS memory release or comparative speed.",
        "cases": [], "layouts": [],
    }
    (output / "lab.diff").write_text(git(ROOT, "diff", "HEAD", "--no-ext-diff"), encoding="utf-8")
    (output / "toolchain.diff").write_text(git(checkout, "diff", "HEAD", "--no-ext-diff"), encoding="utf-8")

    def save():
        (output / "results.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    save()
    try:
        extra = ["/utf-8", "/F67108864"] if cc.style == "msvc" else ["-Wl,--stack,67108864"] if os.name == "nt" else []
        for level in levels:
            generated = output / f"contract-O{level}.c"
            binary = generated.with_suffix(tc.EXE_SUFFIX)
            command = [str(compiler), f"-O{level}", "--stdlib", str(sources / "stdlib"), "--module-dir",
                       str(sources / "lab/lib"), "--standalone", "-o", str(generated),
                       str(sources / "lab/tests/indexed_buffer_contract.goose")]
            result = subprocess.run(command, capture_output=True, text=True, errors="replace", timeout=args.timeout)
            (output / f"generate-O{level}.log").write_text(result.stdout + result.stderr, encoding="utf-8")
            result.check_returncode()
            ok, log = cc.compile(generated, binary, opt=2, extra=extra)
            (output / f"compile-O{level}.log").write_text(log, encoding="utf-8")
            if not ok:
                raise RuntimeError(f"Native compilation failed at O{level}; see compile log")
            for seed in seeds:
                name = f"O{level}-seed-{seed}"
                started = time.monotonic()
                command = [str(binary), str(args.rounds), str(seed)]
                with (output / f"{name}.stdout").open("w", encoding="utf-8") as out, (output / f"{name}.stderr").open("w", encoding="utf-8") as err:
                    result = subprocess.run(command, stdout=out, stderr=err, timeout=args.timeout)
                result.check_returncode()
                text = (output / f"{name}.stdout").read_text(encoding="utf-8")
                if text.splitlines()[0] != CAPACITY_LINE:
                    raise RuntimeError(f"Missing maximum capacity check in {name}")
                metrics = []
                expected = expected_coverage(args.rounds, seed)
                for count in (3, 16, 64):
                    match = re.search(rf"^{count} buffers: {args.rounds} model operations, seed {seed}, (\d+) reopens, (\d+) refusals passed$", text, re.M)
                    if not match or tuple(map(int, match.groups())) != expected or min(expected) == 0:
                        raise RuntimeError(f"Model coverage disagrees with Python oracle for {count} buffers in {name}")
                    metrics.append({"buffers": count, "reopens": int(match[1]), "refusals": int(match[2])})
                report["cases"].append({"level": level, "seed": seed, "command": command, "exit_code": 0,
                                        "wall_seconds": time.monotonic() - started, "binary_sha256": digest(binary),
                                        "generated_sha256": digest(generated), "coverage": metrics})
                save()
                print(f"{name}: capacity and {args.rounds * 3} model operations passed", flush=True)
            # Measure this generated representation, including scalar fields, lengths,
            # padding and the tail header. It is not a process/RSS measurement.
            symbols = set(re.findall(r"struct (lab_buffer_indexed_Store_\w+) \{", generated.read_text(encoding="utf-8")))
            if len(symbols) != 1:
                raise RuntimeError("Expected one generated Store layout")
            symbol = symbols.pop()
            wrapper = output / f"layout-O{level}.c"
            wrapper.write_text(
                '#define main contract_entry\n#include ' + json.dumps(generated.as_posix()) + '\n#undef main\n'
                '#include <stddef.h>\nint main(void) {\n'
                f'printf("%zu,%zu,%zu,%zu\\n", sizeof({symbol}), offsetof({symbol}, data_g), '
                f'sizeof((({symbol}*)0)->buffers_g), sizeof((({symbol}*)0)->next_g));\nreturn 0; }}\n', encoding="utf-8")
            probe = wrapper.with_suffix(tc.EXE_SUFFIX)
            ok, log = cc.compile(wrapper, probe, opt=2, extra=extra)
            (output / f"layout-O{level}.log").write_text(log, encoding="utf-8")
            if not ok:
                raise RuntimeError("Layout probe failed; see log")
            result = subprocess.run([str(probe)], capture_output=True, text=True, timeout=args.timeout, check=True)
            fixed, tail_offset, buffers, freelist = map(int, result.stdout.strip().split(","))
            assert fixed >= tail_offset >= buffers + freelist >= 147456
            report["layouts"].append({"level": level, "fixed_store_bytes": fixed, "tail_header_offset": tail_offset,
                                      "buffers_field_bytes": buffers, "freelist_field_bytes": freelist})
            save()
        report["complete"] = True
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        save()
    print(f"Recorded {len(report['cases'])} cases from one toolchain in {output}", flush=True)


if __name__ == "__main__":
    main()
