"""Exercise provenance, CSV/accounting and all shape/comparison paths."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    script, build, configuration = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="goose-document-experiment-") as temporary:
        output = Path(temporary) / "results"
        command = [sys.executable, script, "--build", build, "--configuration", configuration,
                   "--size", "128", "--iterations", "4", "--repeats", "1", "--output", str(output)]
        subprocess.run(command, check=True, timeout=30)
        record = json.loads((output / "results.json").read_text(encoding="utf-8"))
        assert record["complete"] and len(record["cases"]) == 9
        assert len(record["lab"]["revision"]) == 40 and len(record["toolchain"]["revision"]) == 40
        assert all(len(value) == 64 for value in record["source_sha256"].values())
        assert record["contract"]["exit_code"] == 0
        for case in record["cases"]:
            assert (output / case["raw_csv"]).is_file()
            assert case["exit_code"] == 0 and case["memory_sample_count"] >= 0
            assert record["timing_summary"][case["name"]]["edit"]["samples"] == case["documents"] * 4
            if case["mode"] == "snapshot":
                assert case["final"]["used_bytes"] == 0
                assert case["final"]["pool_free_bytes"] == case["final"]["pool_high_water_bytes"]
        # An earlier measurement directory cannot be replaced accidentally.
        retry = subprocess.run(command, capture_output=True, timeout=30)
        assert retry.returncode != 0 and (output / "results.json").is_file()


if __name__ == "__main__":
    main()
