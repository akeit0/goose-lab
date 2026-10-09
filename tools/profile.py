"""Manual UI/workbench profiling; Python stdlib only, with optional OS memory data."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from run import executable


def memory(pid):
    if sys.platform == "win32":
        from ctypes import wintypes
        class Counters(ctypes.Structure):
            _fields_ = [("size", wintypes.DWORD), ("faults", wintypes.DWORD)] + [
                (name, ctypes.c_size_t) for name in ("peak_rss", "rss", "peak_paged", "paged", "peak_nonpaged", "nonpaged", "pagefile", "peak_pagefile", "private")]
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        psapi = ctypes.WinDLL("psapi", use_last_error=True)
        kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel.OpenProcess.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        handle = kernel.OpenProcess(0x0400 | 0x0010, False, pid)
        if not handle: return None
        try:
            counters = Counters(); counters.size = ctypes.sizeof(counters)
            if psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.size):
                return {"rss": counters.rss, "private": counters.private}
        finally:
            kernel.CloseHandle(handle)
    elif sys.platform.startswith("linux"):
        try:
            text = Path(f"/proc/{pid}/status").read_text()
            found = re.search(r"^VmRSS:\s+(\d+)\s+kB", text, re.M)
            if found: return {"rss": int(found[1]) * 1024}
        except (OSError, ValueError): pass
    elif sys.platform == "darwin":
        try:
            result = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True, timeout=1)
            if result.returncode == 0: return {"rss": int(result.stdout.strip()) * 1024}
        except (OSError, ValueError, subprocess.TimeoutExpired): pass
    return None


def measure(program, arguments, root, stem, timeout):
    started = time.monotonic(); peaks = {}; samples = []; timed_out = False
    with stem.with_suffix(".out").open("wb") as out, stem.with_suffix(".err").open("wb") as err:
        options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
        process = subprocess.Popen([str(program), *map(str, arguments)], cwd=root, stdout=out, stderr=err, **options)
        try:
            while process.poll() is None:
                elapsed = time.monotonic() - started
                if elapsed > timeout:
                    timed_out = True; process.kill(); break
                usage = memory(process.pid)
                if usage:
                    for key, value in usage.items(): peaks[key] = max(peaks.get(key, 0), value)
                    if (not samples and elapsed >= 2) or (len(samples) == 1 and elapsed >= 8):
                        samples.append({"seconds": round(elapsed, 1), **usage})
                time.sleep(0.25)
            code = process.wait()
        finally:
            if process.poll() is None: process.kill(); process.wait()
    return {"exit_code": code, "timed_out": timed_out, "seconds": round(time.monotonic()-started, 2),
            "sampled_peak_bytes": peaks, "samples": samples, "stdout": stem.with_suffix(".out").read_text(encoding="utf-8", errors="replace").strip()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("ui", "editor"))
    parser.add_argument("--build", default="build")
    parser.add_argument("--configuration", default="Release")
    parser.add_argument("--label", default="memory")
    parser.add_argument("--frames", type=int, help="Override frames for a short diagnostic run")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9-]+", args.label) or (args.frames is not None and args.frames <= 0):
        parser.error("Use a simple label and a positive frame count")
    root = Path(__file__).resolve().parents[1]; build = Path(args.build).resolve()
    program = executable(build, args.configuration, "ui_profile" if args.mode == "ui" else "workbench")
    if args.mode == "ui":
        cases = [(stage, ["--stage", stage, "--frames", args.frames or 240], None) for stage in ("empty", "text", "field", "editor")]
    else:
        normal = build / f"{args.label}-normal.txt"; long = build / f"{args.label}-long.txt"
        line = b"let memory_profile = 123456789;\n"; normal.write_bytes((line * (2097152//len(line)+1))[:2097152]); long.write_bytes(b"a" * 262144)
        cases = [(name, ["--headless", "--root", root, "--file", path, "--frames", args.frames or frames, "--screenshot", build/f"{args.label}-{name}.png"], path)
                 for name, path, frames in (("small", root/"README.md", 900), ("normal-2MiB", normal, 900), ("one-line-256KiB", long, 48))]
    results = []
    for name, options, path in cases:
        result = {"case": name, **measure(program, options, root, build/f"{args.label}-{name}", 45)}
        if path:
            result["input_bytes"] = path.stat().st_size
            result["loaded"] = f'bytes={result["input_bytes"]} ' in result["stdout"] and "screenshot=true" in result["stdout"]
        results.append(result); print(json.dumps(result, ensure_ascii=True))
    (build/f"{args.label}.json").write_text(json.dumps({"platform": sys.platform, "results": results}, indent=2)+"\n", encoding="utf-8")
    return int(any(item["exit_code"] != 0 or item["timed_out"] or not item.get("loaded", True) for item in results))


if __name__ == "__main__":
    raise SystemExit(main())
