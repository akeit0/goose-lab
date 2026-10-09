"""Locate CMake outputs without assuming MSVC directories or an .exe suffix."""
import argparse
from pathlib import Path
import os
import subprocess


def executable(build, configuration, name):
    if Path(name).name != name or name in (".", ".."):
        raise ValueError("Use a CMake program target name, not a path")
    filename = name + (".exe" if os.name == "nt" else "")
    build = Path(build).resolve()
    for path in (build / configuration / filename, build / filename):
        if path.is_file():
            return path
    raise FileNotFoundError(f"Build target {name} first; no executable found under {build}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="build")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("program")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        program = executable(args.build, args.configuration, args.program)
    except (FileNotFoundError, ValueError) as error:
        parser.exit(2, f"{error}\n")
    return subprocess.call([str(program), *args.arguments])


if __name__ == "__main__":
    raise SystemExit(main())
