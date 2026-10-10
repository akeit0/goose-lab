"""Check complete raw pool traces, provenance and exact/geometric logical work."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    script, build, configuration = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="goose-raw-pool-") as temporary:
        output = Path(temporary) / "record"
        command = [sys.executable, script, "--build", build, "--configuration", configuration,
                   "--documents", "3", "--documents", "5", "--step", "32", "--rounds", "5",
                   "--repeats", "1", "--output", str(output)]
        subprocess.run(command, check=True, timeout=30)
        record = json.loads((output / "results.json").read_text(encoding="utf-8"))
        assert record["complete"] and len(record["cases"]) == 4
        assert len(record["toolchains"][0]["revision"]) == 40
        assert len(record["contracts"]) == len(record["diagnostics"]) == 1
        assert len(record["exhaustion"]) == 1
        assert record["toolchains"][0]["exhaustion_reservation_bytes"] == 1048576
        assert all(len(value) == 64 for value in record["source_sha256"].values())
        for case in record["cases"]:
            count = case["documents"]
            growth = case["growth_end"]
            assert growth["logical_bytes"] == count * 32 * 5
            assert case["final"]["application_write_bytes"] == growth["logical_bytes"]
            assert growth["capacity_bytes"] == count * 32 * (5 if case["mode"] == "exact" else 8)
            assert growth["realloc_calls"] == count * (5 if case["mode"] == "exact" else 4)
            assert growth["zeroed_growth_bytes"] == growth["capacity_bytes"]
            assert case["final"]["capacity_bytes"] == 0
            assert (output / case["raw_csv"]).is_file()
        retry = subprocess.run(command, capture_output=True, timeout=30)
        assert retry.returncode != 0 and record == json.loads((output / "results.json").read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
