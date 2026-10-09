"""Exercise the fork's project import search order and relative imports."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def check(compiler, main, *options, succeeds=True):
    run = subprocess.run([compiler, "--check", "--roundtrip", *map(str, options), str(main)],
                         capture_output=True, text=True)
    if (run.returncode == 0) != succeeds:
        raise AssertionError(run.stdout + run.stderr)


def main():
    compiler = str(Path(sys.argv[1]).resolve())
    stdlib = Path(sys.argv[2]).resolve()
    # Public library imports must resolve without any sample/tool module roots.
    library = Path(__file__).resolve().parents[1] / "lib"
    for source in library.rglob("*.goose"):
        for module in re.findall(r"^import\s+([\w.]+)\s*;", source.read_text(encoding="utf-8"), re.M):
            if module.startswith("lab."):
                assert (library / (module.replace(".", "/") + ".goose")).is_file(), (source, module)
            else:
                assert (stdlib / (module.replace(".", "/") + ".goose")).is_file(), (source, module)
    with tempfile.TemporaryDirectory(prefix="goose-lab modules ") as directory:
        root = Path(directory)
        first, second, local = (root / name for name in ("first modules", "second", "app"))
        for folder in (first, second, local):
            folder.mkdir()
        (first / "dep.goose").write_text('import .helper;\nfn answer() -> i64 { helper() }\n')
        (first / "helper.goose").write_text('fn helper() -> i64 { 42 }\n')
        # If the first path is ignored, this deliberately fails to typecheck.
        (second / "dep.goose").write_text('fn answer() -> i64 { "wrong path" }\n')
        source = local / "main.goose"
        source.write_text('import std; import dep;\nfn main() { print(answer()); }\n')
        opts = ("--stdlib", stdlib, "--module-dir", first, "-I", second)
        check(compiler, source, *opts)
        check(compiler, source, "--stdlib", stdlib, succeeds=False)
        # Root-file modules keep precedence over project search directories.
        (local / "dep.goose").write_text('fn answer() -> i64 { 7 }\n')
        check(compiler, source, "--stdlib", stdlib, "--module-dir", second)
        # Existing imports without new flags continue to work.
        source.write_text('import std; fn main() { print("ok"); }\n')
        check(compiler, source, "--stdlib", stdlib)
    print("Module search contract passed")


if __name__ == "__main__":
    main()
