"""Check mixed, boundary-crossing chunks and non-LIFO retirement against an oracle."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    script, build, configuration = sys.argv[1:]
    sys.path.insert(0, str(Path(script).parent))
    spec = importlib.util.spec_from_file_location("buffer_storage_experiment", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix="goose-buffer-storage-") as temporary:
        output = Path(temporary) / "record"
        command = [sys.executable, script, "--build", build, "--configuration", configuration,
                   "--documents", "3", "--documents", "5", "--chunk-bytes", "64", "--step", "32",
                   "--rounds", "5", "--workload", "mixed", "--workload", "churn", "--repeats", "1", "--output", str(output)]
        subprocess.run(command, check=True, timeout=30)
        record = json.loads((output / "results.json").read_text(encoding="utf-8"))
        assert record["complete"] and len(record["cases"]) == 8
        assert all(len(value) == 64 for value in record["source_sha256"].values())
        assert len(record["toolchains"][0]["revision"]) == 40
        for case in record["cases"]:
            data = module.read_rows(output / case["raw_csv"], case["documents"], 32, 5, 64, case["workload"], case["mode"])
            end = case["final"]
            assert end["capacity_bytes"] == end["logical_bytes"] == end["live_runs"] == end["metadata_live_slots"] == 0
            if case["mode"] == "chunked":
                assert end["moved_capacity_bytes"] == end["realloc_calls"] == 0
                assert end["alloc_calls"] == end["free_calls"] > 0
                assert end["address_visits"] > end["read_calls"]
            else:
                assert end["alloc_calls"] == end["metadata_high_water_slots"] == 0
                assert end["address_visits"] == end["read_calls"]
            if case["workload"] == "churn":
                assert "reopened_end" in case["checkpoints"] and "retired_end" in case["checkpoints"]
                if case["mode"] == "chunked":
                    # Reopen half-size buffers in reused descriptor slots, keeping the peak fixed.
                    assert end["metadata_high_water_slots"] == case["checkpoints"]["growth_end"]["metadata_live_slots"]
            # A truncated trace and altered work must not become a successful record.
            corrupt = Path(temporary) / "corrupt.csv"
            lines = (output / case["raw_csv"]).read_text(encoding="utf-8").splitlines()
            corrupt.write_text("\n".join(lines[:-1]) + "\n", encoding="utf-8")
            try:
                module.read_rows(corrupt, case["documents"], 32, 5, 64, case["workload"], case["mode"])
            except ValueError:
                pass
            else:
                raise AssertionError("Truncated lifetime trace was accepted")
            try:
                module.read_rows(output / case["raw_csv"], case["documents"], 33, 5, 64, case["workload"], case["mode"])
            except ValueError:
                pass
            else:
                raise AssertionError("A different logical workload was accepted")
        retry = subprocess.run(command, capture_output=True, timeout=30)
        assert retry.returncode != 0 and record == json.loads((output / "results.json").read_text(encoding="utf-8"))
        rejected = Path(temporary) / "rejected"
        bound = [sys.executable, script, "--build", build, "--documents", "64", "--chunk-bytes", "1",
                 "--output", str(rejected)]
        result = subprocess.run(bound, capture_output=True, text=True, timeout=15)
        assert result.returncode != 0 and "metadata envelope exceeds 4096" in result.stderr
        assert not rejected.exists()


if __name__ == "__main__":
    main()
