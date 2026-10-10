"""Verify reservation exhaustion is a classified child-process failure."""
import os
import subprocess
import sys


def main():
    options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
    for mode, diagnostic in (("single", "invalid slice length"), ("cumulative", "data stack overflow")):
        result = subprocess.run([sys.argv[1], mode], capture_output=True, encoding="utf-8",
                                errors="replace", timeout=15, **options)
        assert result.returncode != 0, "The small-reservation allocation unexpectedly returned"
        assert "unexpected allocation success" not in result.stdout
        assert f"goose runtime error: {diagnostic}" in result.stderr, repr(result.stderr)
        print(f"{mode} classified_exit={result.returncode}: {result.stderr.strip()}")


if __name__ == "__main__":
    main()
