"""Snapshot and qualify bounded stream/ACK and real search contracts on one fork."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET

from document_experiment import cache, digest, revision
from http_clients_qualification import load
from run import executable

ROOT = Path(__file__).resolve().parents[1]
PROGRAMS = ("stream_contract", "search_stream_contract", "slot_arena_contract")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="build-core")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if os.name != "nt" or not 1 <= args.repeats <= 20:
        parser.error("Windows x64/MSVC Release and 1..20 repeats are required")
    build = Path(args.build).resolve(); output = Path(args.output).resolve()
    if output.exists():
        parser.error("Output already exists; use a fresh directory")
    subprocess.run(["cmake", "--build", str(build), "--config", "Release", "--target", *PROGRAMS, "--parallel", "4"], check=True, timeout=180)
    checkout = Path(cache(build)["GOOSE_SOURCE_DIR"]); compiler = executable(build / "goose", "Release", "goose")
    tc = load("stream_toolchain", checkout / "scripts/toolchain.py"); cc = tc.test_cc("native")
    if cc.style != "msvc":
        parser.error("This runner currently supports MSVC CMake projects")
    output.mkdir(parents=True, exist_ok=False); sources = output / "sources"
    for source, destination in ((ROOT / "lib", "lib"), (ROOT / "native", "native"), (checkout / "stdlib", "stdlib")):
        shutil.copytree(source, sources / destination)
    (sources / "tests/support").mkdir(parents=True)
    for program in PROGRAMS:
        shutil.copyfile(ROOT / f"tests/{program}.goose", sources / f"tests/{program}.goose")
    shutil.copyfile(ROOT / "tests/support/stream_producer.goose", sources / "tests/support/stream_producer.goose")
    for source, destination in ((ROOT / "tests/stream_fixture.py", "fixture.py"), (ROOT / "tests/slot_arena_fixture.py", "slot_arena_fixture.py"), (Path(__file__), "qualification.py"),
                                 (ROOT / "tools/http_clients_qualification.py", "http_clients_qualification.py"),
                                 (ROOT / "tools/document_experiment.py", "document_experiment.py"),
                                 (ROOT / "tools/run.py", "run.py"), (ROOT / "tools/profile.py", "profile.py"),
                                 (checkout / "scripts/toolchain.py", "toolchain.py")):
        shutil.copyfile(source, sources / destination)
    ns = {"m": "http://schemas.microsoft.com/developer/msbuild/2003"}; links = {}; archive_hashes = {}
    for program in PROGRAMS:
        project = build / f"{program}.vcxproj"; shutil.copyfile(project, sources / project.name)
        group = next(g for g in ET.parse(project).getroot().findall("m:ItemDefinitionGroup", ns) if "'Release|x64'" in g.attrib.get("Condition", ""))
        dependencies = group.findtext("m:Link/m:AdditionalDependencies", namespaces=ns)
        if not dependencies or "%(" in dependencies:
            raise RuntimeError("Cannot resolve native link closure")
        defines = [d for d in group.findtext("m:ClCompile/m:PreprocessorDefinitions", namespaces=ns).split(";") if d.startswith("GOOSE_LAB_")]
        libraries = []
        for dependency in dependencies.split(";"):
            if not dependency:
                continue
            original = build / dependency
            if original.is_file():
                copied = sources / "archives" / original.name; copied.parent.mkdir(exist_ok=True)
                if copied.exists() and digest(copied) != digest(original):
                    raise RuntimeError("Conflicting archive basename")
                shutil.copyfile(original, copied); libraries.append(str(copied)); archive_hashes[dependency] = digest(copied)
            else:
                if "/" in dependency or "\\" in dependency:
                    raise RuntimeError(f"Missing archive: {original}")
                libraries.append(dependency)
        links[program] = {"libraries": libraries, "defines": defines}
    extra = ["/utf-8", "/MT", "/F67108864", f"/I{sources / 'native'}"]
    record = {"complete": False, "lab": revision(ROOT), "toolchain": revision(checkout), "compiler_sha256": digest(compiler),
              "native_compiler": cc.desc, "native_optimization": 2, "native_flags": extra, "links": links, "archives": archive_hashes,
              "source_sha256": {str(p.relative_to(sources)): digest(p) for p in sources.rglob("*") if p.is_file()}, "repeats": args.repeats,
              "levels": [], "limits": "Correctness/bounds qualification, not throughput or total process memory measurement."}
    fixture = load("stream_fixture", sources / "fixture.py")
    arena_fixture = load("slot_arena_fixture", sources / "slot_arena_fixture.py")
    def save():
        (output / "results.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    save()
    try:
        for level in (0, 1, 2):
            item = {"level": level, "programs": {}, "runs": []}; record["levels"].append(item); binaries = {}
            for program in PROGRAMS:
                generated = output / f"{program}-O{level}.c"; binary = generated.with_suffix(".exe"); binaries[program] = binary
                command = [str(compiler), f"-O{level}", "--stdlib", str(sources / "stdlib"), "--module-dir", str(sources / "lib"),
                           "--module-dir", str(sources / "tests"), "--standalone", "--include", str(sources / "native/goose_lab.h"),
                           "-o", str(generated), str(sources / f"tests/{program}.goose")]
                generation = subprocess.run(command, capture_output=True, text=True, timeout=60)
                (output / f"generate-{program}-O{level}.log").write_text(generation.stdout + generation.stderr, encoding="utf-8"); generation.check_returncode()
                ok, log = cc.compile(generated, binary, opt=2, extra=extra, defines=links[program]["defines"], libs=links[program]["libraries"])
                (output / f"compile-{program}-O{level}.log").write_text(log, encoding="utf-8")
                if not ok:
                    raise RuntimeError(f"Native compile failed: {program} O{level}")
                item["programs"][program] = {"command": command, "binary_sha256": digest(binary), "generated_sha256": digest(generated)}; save()
            for repeat in range(args.repeats):
                logs = output / f"O{level}-{repeat}"; logs.mkdir(); started = time.monotonic()
                producer, search, pm, sm = fixture.run(binaries[PROGRAMS[0]], binaries[PROGRAMS[1]], logs)
                arena, am = arena_fixture.run(binaries[PROGRAMS[2]], logs / "slot-arena")
                item["runs"].append({"repeat": repeat, "producer": pm, "search": sm, "slot_arena": am,
                                    "exit_codes": [producer.returncode, search.returncode, arena.returncode], "wall_seconds": time.monotonic() - started})
                save(); print(f"O{level}, repeat {repeat+1}: passed", flush=True)
        generated = output / "search_stream_contract-O1.c"; text = generated.read_text(encoding="utf-8")
        names = [re.search(pattern, text)[1] for pattern in (
            r"typedef struct (lab_fs_search_clients_Service_\w+)\b",
            r"typedef struct (lab_fs_search_Batch_\w+)\b",
            r"typedef struct (lab_io_stream_Service_\w+_support_stream_producer_Payload_\w+)\b",
            r"typedef struct (lab_io_stream_Page_\w+_lab_fs_search_Batch_\w+)\b",
            r"typedef struct (lab_io_stream_Packet_\w+_lab_fs_search_Batch_\w+)\b",
            r"typedef struct (lab_buffer_slot_arena_Store_\w+)\b")]
        probe = output / "layout.c"; binary = probe.with_suffix(".exe")
        probe.write_text('#define main contract_main\n#include "search_stream_contract-O1.c"\n#undef main\n'
                         + 'int main(void) { printf("%zu,%zu,%zu,%zu,%zu,%zu,%zu\\n", '+', '.join(f"sizeof({n})" for n in names)+f', offsetof({names[4]}, data_g) + 8); return 0; }}\n', encoding="utf-8")
        ok, log = cc.compile(probe, binary, opt=2, extra=extra, defines=links[PROGRAMS[1]]["defines"], libs=links[PROGRAMS[1]]["libraries"])
        (output / "layout.log").write_text(log, encoding="utf-8")
        if not ok:
            raise RuntimeError("Layout probe failed")
        layout = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=10)
        record["fixed_bytes"] = dict(zip(("search_service", "search_batch", "producer_service", "search_page", "search_packet_header", "slot_arena", "queue_image_prefix"), map(int, layout.stdout.strip().split(","))))
        if record["fixed_bytes"]["queue_image_prefix"] != 61:
            raise RuntimeError("Queue byte counters do not match generated packet prefix")
        record["complete"] = True
    except Exception as error:
        record["error"] = str(error); raise
    finally:
        save()
    print(record["fixed_bytes"])


if __name__ == "__main__":
    main()
