"""Snapshot and qualify HTTP client lifetimes at Goose O0/O1/O2 on Windows/MSVC."""
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
import xml.etree.ElementTree as ET

from document_experiment import cache, digest, revision
from run import executable

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); sys.modules[name] = module; spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="build-core")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if os.name != "nt" or args.configuration != "Release" or not 1 <= args.repeats <= 20:
        parser.error("This qualification requires Windows/MSVC Release and 1..20 repeats")
    build = Path(args.build).resolve(); output = Path(args.output).resolve()
    if output.exists():
        parser.error("Output already exists; use a fresh directory")
    # CMake owns dependency freshness and the exact native link closure.
    subprocess.run(["cmake", "--build", str(build), "--config", args.configuration,
                    "--target", "http_clients_contract", "--parallel", "4"], check=True, timeout=180)
    checkout = Path(cache(build)["GOOSE_SOURCE_DIR"])
    compiler = executable(build / "goose", args.configuration, "goose")
    tc = load("http_clients_toolchain", checkout / "scripts/toolchain.py"); cc = tc.test_cc("native")
    if cc.style != "msvc":
        parser.error("This qualification currently supports the MSVC CMake generator")
    project = build / "http_clients_contract.vcxproj"
    ns = {"m": "http://schemas.microsoft.com/developer/msbuild/2003"}
    dependencies = None
    for group in ET.parse(project).getroot().findall("m:ItemDefinitionGroup", ns):
        if "'Release|x64'" in group.attrib.get("Condition", ""):
            dependencies = group.findtext("m:Link/m:AdditionalDependencies", namespaces=ns)
    if dependencies is None or "%(" in dependencies:
        raise RuntimeError("Cannot resolve the Release native link closure")
    output.mkdir(parents=True, exist_ok=False)
    sources = output / "sources"
    shutil.copytree(ROOT / "lib", sources / "lib")
    shutil.copytree(ROOT / "native", sources / "native")
    shutil.copytree(checkout / "stdlib", sources / "stdlib")
    for source, target in ((ROOT / "tests/http_clients_contract.goose", "contract.goose"),
                           (ROOT / "tests/http_clients_fixture.py", "fixture.py"),
                           (Path(__file__), "qualification.py"), (project, "link.vcxproj"),
                           (ROOT / "tools/document_experiment.py", "document_experiment.py"),
                           (ROOT / "tools/run.py", "run.py"), (ROOT / "tools/profile.py", "profile.py"),
                           (checkout / "scripts/toolchain.py", "toolchain.py")):
        shutil.copyfile(source, sources / target)
    libraries, library_hashes = [], {}
    for dependency in dependencies.split(";"):
        if not dependency:
            continue
        original = build / dependency
        if original.is_file():
            copied = sources / "archives" / original.name; copied.parent.mkdir(exist_ok=True)
            shutil.copyfile(original, copied); libraries.append(str(copied))
            library_hashes[dependency] = digest(copied)
        else:
            if "/" in dependency or "\\" in dependency:
                raise RuntimeError(f"Missing link input: {original}")
            libraries.append(dependency)
    record = {"complete": False, "lab": revision(ROOT), "toolchain": revision(checkout),
              "compiler_sha256": digest(compiler), "native_compiler": cc.desc, "native_optimization": 2,
              "native_archives": library_hashes, "link_inputs": libraries,
              "source_sha256": {str(p.relative_to(sources)): digest(p) for p in sources.rglob("*") if p.is_file()},
              "repeats": args.repeats, "levels": [], "limits": "Loopback correctness qualification; no speed or queue/RSS memory ranking."}
    extra = ["/utf-8", "/MT", "/F67108864", f"/I{sources / 'native'}"]
    defines = ["GOOSE_LAB_HTTP=1", "GOOSE_LAB_CANCEL=1"]
    fixture = load("http_clients_fixture", sources / "fixture.py")

    def save():
        (output / "results.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")

    save()
    try:
        for level in (0, 1, 2):
            generated = output / f"contract-O{level}.c"; binary = generated.with_suffix(".exe")
            command = [str(compiler), f"-O{level}", "--stdlib", str(sources / "stdlib"), "--module-dir", str(sources / "lib"),
                       "--standalone", "--include", str(sources / "native/goose_lab.h"), "-o", str(generated), str(sources / "contract.goose")]
            generation = subprocess.run(command, capture_output=True, text=True, timeout=60)
            (output / f"generate-O{level}.log").write_text(generation.stdout + generation.stderr, encoding="utf-8"); generation.check_returncode()
            ok, log = cc.compile(generated, binary, opt=2, extra=extra, defines=defines, libs=libraries)
            (output / f"compile-O{level}.log").write_text(log, encoding="utf-8")
            if not ok:
                raise RuntimeError(f"C compilation failed at O{level}")
            item = {"level": level, "generation_command": command, "binary_sha256": digest(binary), "generated_sha256": digest(generated), "runs": []}
            record["levels"].append(item); save()
            for repeat in range(args.repeats):
                started = time.monotonic(); process = fixture.run(binary)
                (output / f"O{level}-{repeat}.stdout").write_text(process.stdout, encoding="utf-8")
                (output / f"O{level}-{repeat}.stderr").write_text(process.stderr, encoding="utf-8")
                item["runs"].append({"repeat": repeat, "exit_code": process.returncode, "model_requests": 996,
                                     "checked_rows": fixture.validate(process.stdout), "wall_seconds": time.monotonic() - started})
                save(); print(f"O{level}, repeat {repeat + 1}: passed", flush=True)
        generated = output / "contract-O1.c"
        typename = re.search(r"typedef struct (lab_net_http_clients_Service_\w+)\b", generated.read_text(encoding="utf-8"))
        if not typename:
            raise RuntimeError("Cannot identify generated Service representation")
        probe = output / "layout.c"; probe_binary = probe.with_suffix(".exe")
        probe.write_text(f'#define main contract_main\n#include "{generated.as_posix()}"\n#undef main\nint main(void) {{ printf("%zu\\n", sizeof({typename[1]})); return 0; }}\n', encoding="utf-8")
        ok, log = cc.compile(probe, probe_binary, opt=2, extra=extra, defines=defines, libs=libraries)
        (output / "layout.log").write_text(log, encoding="utf-8")
        if not ok:
            raise RuntimeError("Layout probe compilation failed")
        measured = subprocess.run([str(probe_binary)], check=True, capture_output=True, text=True, timeout=10)
        record["fixed_service_bytes"] = int(measured.stdout)
        record["fixed_layout_limits"] = "Includes reserved client/flight/buffer descriptors and tail header; excludes arena backing, queues, workers, native HTTP and temporaries."
        record["complete"] = True
    except Exception as error:
        record["error"] = str(error); raise
    finally:
        save()
    print(f"Fixed Service representation: {record['fixed_service_bytes']} bytes")


if __name__ == "__main__":
    main()
