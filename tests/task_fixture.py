"""Real UI events, restart persistence, narrow layout and blocked-file recovery."""
from pathlib import Path
import subprocess
import sys
import tempfile


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout


def main():
    driver, app = map(Path, sys.argv[1:3])
    capture = Path.cwd() / "task-inbox-interacted.png"
    with tempfile.TemporaryDirectory(prefix="goose task inbox ") as directory:
        data = Path(directory) / "inbox café.gxt"
        print(run(driver, data, capture).strip())
        print(run(driver, Path(directory) / "scaled.gxt",
                  Path.cwd() / "task-inbox-scale125.png", "1.25").strip())
        restarted = run(app, "--headless", "--frames", 3, "--data", data,
                        "--width", 560, "--height", 860,
                        "--screenshot", Path.cwd() / "task-inbox-restarted.png")
        assert "tasks=3 completed=1 dirty=false blocked=false screenshot=true" in restarted, restarted
        assert capture.is_file()
        broken = Path(directory) / "broken.gxt"
        original = b"not a valid task document"
        broken.write_bytes(original)
        blocked = run(app, "--headless", "--frames", 3, "--demo", "--data", broken,
                      "--screenshot", Path.cwd() / "task-inbox-blocked.png")
        assert "blocked=true" in blocked and broken.read_bytes() == original, blocked
    print("Separate-process restart and corrupt-file preservation passed")


if __name__ == "__main__":
    main()
