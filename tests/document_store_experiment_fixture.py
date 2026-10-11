"""Check equal-work/source accounting, bounded history and invalid records."""
import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    script, build, configuration = sys.argv[1:]
    sys.path.insert(0, str(Path(script).parent))
    spec = importlib.util.spec_from_file_location("document_store_experiment", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix="goose-shared-documents-") as temporary:
        output = Path(temporary) / "results"
        command = [sys.executable, script, "--build", build, "--configuration", configuration,
                   "--size", "128", "--iterations", "12", "--history", "2", "--repeats", "1", "--output", str(output)]
        subprocess.run(command, check=True, timeout=60)
        record = json.loads((output / "results.json").read_text(encoding="utf-8"))
        assert record["complete"] and len(record["cases"]) == 18 and record["history_limit"] == 2
        assert record["contract"]["exit_code"] == 0
        assert all(len(value) == 64 for value in record["source_sha256"].values())
        for case in record["cases"]:
            assert case["final"]["used_bytes"] == 0
            assert case["history"] == 2
            assert record["timing_summary"][case["name"]]["edit"]["samples"] == case["documents"] * 12
        case = next(c for c in record["cases"] if c["mode"] == "shared-tree")
        raw = output / case["raw_csv"]
        with raw.open(newline="", encoding="utf-8") as source:
            data = list(csv.DictReader(source))
        # Corrupt the collected source-byte count without breaking the simple
        # used=text+nodes invariant: only the independent root oracle catches it.
        checkpoint = next(row for row in data if row["operation"] == "collect")
        checkpoint["text_bytes"] = str(int(checkpoint["text_bytes"]) + 1)
        checkpoint["used_bytes"] = str(int(checkpoint["used_bytes"]) + 1)
        bad = output / "corrupt.csv"
        with bad.open("w", newline="", encoding="utf-8") as target:
            writer = csv.DictWriter(target, fieldnames=module.FIELDS); writer.writeheader(); writer.writerows(data)
        try:
            module.rows(bad, case["documents"], 128, 12, 2, "shared-tree")
            raise AssertionError("Corrupted source accounting was accepted")
        except ValueError:
            pass
        bad.write_text("\n".join(raw.read_text(encoding="utf-8").splitlines()[:-1]) + "\n", encoding="utf-8")
        try:
            module.rows(bad, case["documents"], 128, 12, 2, "shared-tree")
            raise AssertionError("Truncated lifetime trace was accepted")
        except ValueError:
            pass
        original = (output / "results.json").read_bytes()
        retry = subprocess.run(command, capture_output=True, timeout=30)
        assert retry.returncode != 0 and (output / "results.json").read_bytes() == original
        rejected = Path(temporary) / "oversized"
        retry = subprocess.run([sys.executable, script, "--build", build, "--size", "2097152", "--output", str(rejected)], capture_output=True, timeout=30)
        assert retry.returncode != 0 and not rejected.exists()


if __name__ == "__main__":
    main()
