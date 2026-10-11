"""Rebuild the document Store contract at Goose O0/O2 and measure fixed layouts."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from document_experiment import cache, digest, revision
from run import executable

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="build-core")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    build = Path(args.build).resolve()
    checkout = Path(cache(build)["GOOSE_SOURCE_DIR"])
    compiler = executable(build / "goose", args.configuration, "goose")
    spec = importlib.util.spec_from_file_location("document_qualification_toolchain", checkout / "scripts/toolchain.py")
    tc = importlib.util.module_from_spec(spec); sys.modules[spec.name] = tc; spec.loader.exec_module(tc)
    cc = tc.test_cc("native")
    output = Path(args.output).resolve(); output.mkdir(parents=True, exist_ok=False)
    shutil.copytree(ROOT / "lib", output / "sources/lib")
    shutil.copytree(ROOT / "tools/experiments", output / "sources/tools/experiments")
    shutil.copytree(checkout / "stdlib", output / "sources/stdlib")
    shutil.copyfile(ROOT / "tests/document_store_contract.goose", output / "sources/contract.goose")
    shutil.copyfile(checkout / "scripts/toolchain.py", output / "sources/toolchain.py")
    shutil.copyfile(Path(__file__), output / "sources/qualification.py")
    record = {"complete": False, "lab": revision(ROOT), "toolchain": revision(checkout), "compiler_sha256": digest(compiler),
              "native_compiler": cc.desc, "native_optimization": 2,
              "source_sha256": {str(p.relative_to(output / "sources")): digest(p) for p in (output / "sources").rglob("*") if p.is_file()}, "levels": []}
    extra = ["/utf-8", "/F67108864"] if cc.style == "msvc" else ["-Wl,--stack,67108864"] if os.name == "nt" else []

    def save():
        (output / "results.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")

    save()
    try:
        for level in (0, 2):
            generated = output / f"contract-O{level}.c"; binary = generated.with_suffix(tc.EXE_SUFFIX)
            command = [str(compiler), f"-O{level}", "--stdlib", str(output / "sources/stdlib"), "--module-dir", str(output / "sources/lib"),
                       "--module-dir", str(output / "sources/tools"), "--standalone", "-o", str(generated), str(output / "sources/contract.goose")]
            generated_run = subprocess.run(command, capture_output=True, text=True, timeout=60)
            (output / f"generate-O{level}.log").write_text(generated_run.stdout + generated_run.stderr, encoding="utf-8"); generated_run.check_returncode()
            ok, log = cc.compile(generated, binary, opt=2, extra=extra)
            (output / f"compile-O{level}.log").write_text(log, encoding="utf-8")
            if not ok:
                raise RuntimeError(f"C compilation failed at O{level}")
            run = subprocess.run([str(binary), str(output / f"saved-O{level}.txt")], capture_output=True, text=True, timeout=60)
            (output / f"O{level}.stdout").write_text(run.stdout, encoding="utf-8"); (output / f"O{level}.stderr").write_text(run.stderr, encoding="utf-8")
            run.check_returncode()
            expected = [f"{count} documents: 2400 independent snapshot-model operations passed" for count in (3, 16, 64)]
            expected.append("three 60000-byte documents: 600 cross-piece snapshot comparisons passed")
            if run.stdout.splitlines() != expected:
                raise RuntimeError("Incomplete model coverage")
            record["levels"].append({"level": level, "exit_code": run.returncode, "binary_sha256": digest(binary), "generated_sha256": digest(generated)})
            save(); print(f"O{level}: 3/16/64 document contracts passed", flush=True)
        profile = output / "profile.c"
        command = [str(compiler), "-O1", "--stdlib", str(output / "sources/stdlib"), "--module-dir", str(output / "sources/lib"),
                   "--module-dir", str(output / "sources/tools"), "--standalone", "-o", str(profile),
                   str(output / "sources/tools/experiments/document_store_profile.goose")]
        generated_run = subprocess.run(command, capture_output=True, text=True, timeout=60)
        (output / "profile-generate.log").write_text(generated_run.stdout + generated_run.stderr, encoding="utf-8"); generated_run.check_returncode()
        record["layout_generated_sha256"] = digest(profile)
        text = profile.read_text(encoding="utf-8")
        stores = set(re.findall(r"struct (lab_document_store_Store_\w+) \{", text))
        tables = set(re.findall(r"(l64_experiment_pool_document_Document_\w+) experiment_pool_document_documents_\w+;", text))
        if len(stores) != 1 or len(tables) != 1:
            raise RuntimeError("Expected one layout for each representation")
        wrapper = output / "layout.c"
        wrapper.write_text('#define main profile_entry\n#include "profile.c"\n#undef main\n'
                           f'int main(void) {{ printf("%zu,%zu\\n", sizeof({stores.pop()}), sizeof({tables.pop()})); return 0; }}\n', encoding="utf-8")
        probe = wrapper.with_suffix(tc.EXE_SUFFIX); ok, log = cc.compile(wrapper, probe, opt=2, extra=extra)
        (output / "layout.log").write_text(log, encoding="utf-8")
        if not ok:
            raise RuntimeError("C layout probe failed")
        run = subprocess.run([str(probe)], capture_output=True, text=True, timeout=60, check=True)
        store, snapshot_table = map(int, run.stdout.strip().split(","))
        record["fixed_layout"] = {"shared_store_bytes": store, "snapshot_document_table_bytes": snapshot_table,
                                  "limits": "Fixed representation only; excludes runtime pool/freelist state, backing allocation rounding and temporaries."}
        record["complete"] = True
    except Exception as error:
        record["error"] = str(error)
        raise
    finally:
        save()
    print(record["fixed_layout"])


if __name__ == "__main__":
    main()
