"""Snapshot and qualify regex/ECS/TCP workloads with one selected Goose compiler."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from document_experiment import cache, digest, revision
from run import executable

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    "regex": ("regex_experiment", "regex_probe.goose", "regex_experiment_fixture"),
    "ecs": ("ecs_game_experiment", "ecs_game.goose", "ecs_game_fixture"),
    "server": ("server_experiment", "server.goose", "server_experiment_fixture"),
}


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="build-core")
    parser.add_argument("--targets", nargs="+", choices=TARGETS, default=list(TARGETS))
    parser.add_argument("--levels", nargs="+", type=int, choices=(0, 1, 2), default=[0, 1, 2])
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if os.name != "nt" or not 1 <= args.repeats <= 10:
        parser.error("Qualification currently requires Windows/MSVC and 1..10 repeats")
    build, output = Path(args.build).resolve(), Path(args.output).resolve()
    if output.exists(): parser.error("Output already exists; choose a fresh directory")
    names = list(dict.fromkeys(args.targets))
    subprocess.run(["cmake", "--build", str(build), "--config", "Release", "--target",
                    *(TARGETS[n][0] for n in names), "--parallel", "4"], check=True, timeout=180)
    checkout = Path(cache(build)["GOOSE_SOURCE_DIR"])
    compiler = executable(build / "goose", "Release", "goose")
    toolchain = load("workload_toolchain", checkout / "scripts/toolchain.py")
    cc = toolchain.test_cc("native")
    if cc.style != "msvc": parser.error("This runner currently supports MSVC")
    output.mkdir(parents=True); sources = output / "sources"
    shutil.copytree(ROOT / "tools/experiments/workloads", sources / "workloads")
    shutil.copytree(checkout / "stdlib", sources / "stdlib")
    (sources / "fixtures").mkdir()
    for _, _, fixture in TARGETS.values():
        shutil.copyfile(ROOT / f"tests/{fixture}.py", sources / f"fixtures/{fixture}.py")
    for path in (Path(__file__), ROOT / "tools/document_experiment.py", ROOT / "tools/run.py", ROOT / "tools/profile.py",
                 ROOT / "cmake/Tools.cmake", checkout / "scripts/toolchain.py"):
        shutil.copyfile(path, sources / path.name)
    sys.path.insert(0, str(sources / "fixtures"))
    fixtures = {n: load(TARGETS[n][2], sources / f"fixtures/{TARGETS[n][2]}.py") for n in names}
    record = {"complete": False, "lab": revision(ROOT), "toolchain": revision(checkout), "compiler_sha256": digest(compiler),
              "native_compiler": cc.desc, "native_optimization": 2, "repeats": args.repeats,
              "source_sha256": {str(p.relative_to(sources)): digest(p) for p in sources.rglob("*") if p.is_file()},
              "runs": [], "layout": {}, "limits": "Bounded correctness workloads; not throughput, rendering, production-server or RSS qualification."}

    def save(): (output / "results.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")

    save()
    try:
        for name in names:
            target, source, _ = TARGETS[name]
            native = [sources / "workloads/server_transport.c"] if name == "server" else []
            libs = ["ws2_32.lib"] if name == "server" else []
            extra = ["/utf-8", "/MT", "/F67108864"]
            for level in sorted(set(args.levels)):
                generated = output / f"{name}-O{level}.c"; binary = generated.with_suffix(".exe")
                command = [str(compiler), f"-O{level}", "--stdlib", str(sources / "stdlib"), "--standalone", "-o", str(generated), str(sources / "workloads" / source)]
                result = subprocess.run(command, capture_output=True, text=True, timeout=90)
                (output / f"{name}-generate-O{level}.log").write_text(result.stdout + result.stderr, encoding="utf-8")
                result.check_returncode()
                ok, log = cc.compile([generated, *native], binary, opt=2, extra=extra, libs=libs)
                (output / f"{name}-compile-O{level}.log").write_text(log, encoding="utf-8")
                if not ok: raise RuntimeError(f"C compilation failed: {name} O{level}")
                for repeat in range(args.repeats):
                    started = time.monotonic(); process, metrics = fixtures[name].run(binary)
                    (output / f"{name}-O{level}-{repeat}.stdout").write_text(process.stdout, encoding="utf-8")
                    (output / f"{name}-O{level}-{repeat}.stderr").write_text(process.stderr, encoding="utf-8")
                    record["runs"].append({"target": name, "level": level, "repeat": repeat, "wall_seconds": time.monotonic()-started,
                                           "generation_command": command, "native_extra": extra, "native_libraries": libs,
                                           "binary_sha256": digest(binary), "generated_sha256": digest(generated), "metrics": metrics})
                    save(); print(f"{name} O{level} repeat {repeat+1}: passed", flush=True)
                if level == min(args.levels) and name in ("ecs", "server"):
                    body = generated.read_text(encoding="utf-8")
                    world = re.search(r"typedef struct (experiment_ecs_World_\w+)\b", body)[1]
                    connection = re.search(r"typedef struct (Connection_\w+)\b", body)[1] if name == "server" else None
                    expression = f'printf("%zu\\n", sizeof({world}));'
                    if connection: expression += f' printf("%zu\\n", sizeof({connection}));'
                    probe = output / f"{name}-layout.c"; probe_binary = probe.with_suffix(".exe")
                    probe.write_text(f'#define main experiment_main\n#include "{generated.as_posix()}"\n#undef main\nint main(void) {{ {expression} return 0; }}\n', encoding="utf-8")
                    ok, log = cc.compile([probe, *native], probe_binary, opt=2, extra=extra, libs=libs)
                    (output / f"{name}-layout.log").write_text(log, encoding="utf-8")
                    if not ok: raise RuntimeError("Layout probe failed")
                    measured = subprocess.run([str(probe_binary)], capture_output=True, text=True, check=True, timeout=10)
                    sizes = list(map(int, measured.stdout.splitlines()))
                    record["layout"][name] = {"world_bytes": sizes[0], "goose_level": level}
                    if connection: record["layout"][name]["connection_bytes"] = sizes[1]
                    save()
        record["complete"] = True
    finally:
        save()


if __name__ == "__main__":
    main()
