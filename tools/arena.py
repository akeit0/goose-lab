"""Run the local Goose arena server and CLI or optional graphics client."""
import argparse
from contextlib import contextmanager
from pathlib import Path
import queue
import socket
import subprocess
import threading

from run import executable


@contextmanager
def server(binary, manual=False, duration=60):
    command = [str(binary), "--port", "0"]
    if duration: command += ["--duration", str(duration)]
    if manual: command.append("--manual")
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
    events, output = queue.Queue(), []

    def read():
        for line in process.stdout:
            output.append(line); events.put(line)
        events.put(None)

    reader = threading.Thread(target=read, daemon=True); reader.start(); port = None
    try:
        first = events.get(timeout=10)
        if not first or not first.startswith("LISTEN "): raise RuntimeError(f"Server failed to listen: {first}")
        port = int(first.split()[1]); yield port, output
    finally:
        if process.poll() is None and port is not None:
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=3) as connection:
                    connection.settimeout(3)
                    with connection.makefile("rb") as stream:
                        assert stream.readline().startswith(b"HELLO ")
                        connection.sendall(b"SHUTDOWN\n"); assert stream.readline() == b"BYE\n"
                process.wait(timeout=5)
            except (OSError, AssertionError, subprocess.TimeoutExpired):
                process.kill(); process.wait(timeout=5)
        if process.poll() is None: process.kill(); process.wait(timeout=5)
        reader.join(timeout=2); errors = process.stderr.read(); process.stdout.close(); process.stderr.close()
        if process.returncode: raise RuntimeError(errors + "".join(output))
        if not output or "native=0" not in output[-1]: raise RuntimeError("Server failed to release its sockets: " + "".join(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="build-core")
    parser.add_argument("--graphics", action="store_true")
    parser.add_argument("--demo", action="store_true")
    parser.add_argument("--frames", type=int, default=0)
    parser.add_argument("--ticks", type=int, default=80)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--screenshot", default="local/arena.png")
    args = parser.parse_args(); build = Path(args.build).resolve()
    client_target = "arena_game" if args.graphics else "arena_client"
    subprocess.run(["cmake", "--build", str(build), "--config", "Release", "--target", "arena_server", client_target, "--parallel", "4"], check=True, timeout=180)
    with server(executable(build, "Release", "arena_server"), duration=0 if args.graphics and not args.frames else 60) as (port, output):
        command = [str(executable(build, "Release", client_target)), str(port)]
        if args.demo: command.append("--demo")
        if args.graphics:
            if args.headless: command.append("--headless")
            if args.frames: command += ["--frames", str(args.frames)]
            screenshot = Path(args.screenshot).resolve(); screenshot.parent.mkdir(parents=True, exist_ok=True)
            command += ["--screenshot", str(screenshot)]
        else: command += ["--ticks", str(args.ticks)]
        result = subprocess.run(command, timeout=60 if args.frames or not args.graphics else None)
        result.check_returncode()
    print("".join(output), end="")


if __name__ == "__main__":
    main()
