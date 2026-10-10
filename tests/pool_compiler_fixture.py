"""Keep the observed descriptor-provenance diagnostic as a minimal compiler probe."""
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    compiler, stdlib, source = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="goose-pool-provenance-") as temporary:
        result = subprocess.run([compiler, "--stdlib", stdlib, "--standalone", "-o",
                                 str(Path(temporary) / "probe.c"), source],
                                capture_output=True, encoding="utf-8", errors="replace", timeout=15)
        assert result.returncode != 0, "Recorded compiler rejection changed; investigate before updating the probe"
        diagnostic = result.stdout + result.stderr
        assert ".index_of needs a reference rooted at the array itself" in diagnostic
        assert "pool" in diagnostic and "argv_text" in diagnostic
        print(diagnostic.strip())


if __name__ == "__main__":
    main()
