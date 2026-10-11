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
                        assert stream.readline().startswith(b"WELCOME 2 ")
                        connection.sendall(b"SHUTDOWN\n")
                        for _ in range(128):
                            if stream.readline() == b"BYE\n": break
                        else: raise AssertionError("Shutdown did not drain BYE")
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
    parser.add_argument("--versus", action="store_true", help="Own a server and launch separate competing clients")
    parser.add_argument("--join", type=int, metavar="PORT", help="Join a server you own separately")
    parser.add_argument("--players", type=int, default=2, help="Clients for --versus, 2..8")
    parser.add_argument("--demo", action="store_true")
    parser.add_argument("--frames", type=int, default=0)
    parser.add_argument("--ticks", type=int, default=80)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--screenshot", default="local/arena.png")
    args = parser.parse_args(); build = Path(args.build).resolve()
    if args.join is not None and (args.versus or not 1 <= args.join <= 65535): parser.error("Use either --versus or --join PORT")
    if not 2 <= args.players <= 8: parser.error("--players must be 2..8")
    if args.headless and (not args.graphics or not args.frames): parser.error("--headless requires --graphics and --frames")
    if args.frames < 0 or not 1 <= args.ticks <= 400: parser.error("Use positive --frames and --ticks 1..400")
    client_target = "arena_game" if args.graphics else "arena_client"
    targets = [client_target] + (["arena_server"] if args.versus else [])
    subprocess.run(["cmake", "--build", str(build), "--config", "Release", "--target", *targets, "--parallel", "4"], check=True, timeout=180)

    def clients(port, count):
        running = []
        try:
            for index in range(count):
                command = [str(executable(build, "Release", client_target)), str(port) if port else "--solo"]
                if args.demo: command.append("--demo")
                if args.graphics:
                    if args.headless: command.append("--headless")
                    if args.frames: command += ["--frames", str(args.frames)]
                    png = Path(args.screenshot).resolve()
                    if count > 1: png = png.with_name(f"{png.stem}-p{index+1}{png.suffix}")
                    png.parent.mkdir(parents=True, exist_ok=True); command += ["--screenshot", str(png)]
                else: command += ["--ticks", str(args.ticks)]
                running.append(subprocess.Popen(command))
            for process in running:
                result = process.wait(timeout=60 if args.frames or not args.graphics else None)
                if result: raise subprocess.CalledProcessError(result, process.args)
        finally:
            for process in running:
                if process.poll() is None: process.terminate(); process.wait(timeout=5)

    if args.versus:
        with server(executable(build, "Release", "arena_server"), duration=0 if args.graphics and not args.frames else 60) as (port, output):
            clients(port, args.players)
        print("".join(output), end="")
    else: clients(args.join or 0, 1)


if __name__ == "__main__":
    main()
