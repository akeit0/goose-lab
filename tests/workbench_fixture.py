"""Drive a complete edit -> save -> Git -> search workflow in a disposable repo."""
from pathlib import Path
import subprocess
import sys
import tempfile

contract, app = map(lambda value: str(Path(value).resolve()), sys.argv[1:3])
with tempfile.TemporaryDirectory(prefix="goose workbench ") as directory:
    root = Path(directory) / "日本語 project"
    root.mkdir()
    def git(*args):
        subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)
    git("init", "-q")
    git("config", "user.name", "Fixture")
    git("config", "user.email", "fixture@example.invalid")
    git("config", "core.autocrlf", "false")
    for scale in ("1.0", "1.25"):
        for name in ("a.txt", "b.txt"):
            (root / name).write_bytes(f"{name} needle before\n".encode())
        git("add", "--all")
        git("commit", "--allow-empty", "-qm", "fixture")
        (root / "b.txt").write_bytes(b"b.txt needle after\n")
        index = (root / ".git/index").read_bytes()
        args = [contract, str(root), str(Path.cwd() / f"workbench-{scale}.png"), scale]
        if scale == "1.25":
            nested = root / "nested"
            nested.mkdir()
            for name in ("one.txt", "two.txt"):
                (nested / name).write_bytes(b"nested needle\n")
            args[1] = str(nested)
            args.append(str(root / "a.txt"))
        subprocess.run(args, check=True, timeout=45)
        assert (root / ".git/index").read_bytes() == index, "Workbench modified the Git index"
    for mode in ([], ["--git"], ["--history"], ["--staged"]):
        subprocess.run([app, "--root", str(root), *mode, "--headless", "--frames", "3", "--width", "560", "--height", "860", "--screenshot", str(Path.cwd() / f"workbench-compact{''.join(mode)}.png")], check=True, timeout=30)
