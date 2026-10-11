"""Barrier-controlled loopback server and independent client-generation oracle."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
import subprocess
import sys
import threading


class Server(ThreadingHTTPServer):
    # Windows rejects connections immediately when the default backlog of five
    # fills during an eight-worker burst. That is a fixture capacity, not HTTP
    # client routing behavior.
    request_queue_size = 128


class Handler(BaseHTTPRequestHandler):
    lock = threading.Lock()
    barriers = {}

    def log_message(self, *_):
        pass

    @classmethod
    def barrier(cls, key):
        with cls.lock:
            return cls.barriers.setdefault(key, (threading.Event(), threading.Event()))

    def do_GET(self):
        kind, _, key = self.path[1:].partition("/")
        body, status = key.encode(), 200
        if kind == "hold":
            ready, release = self.barrier(key)
            ready.set()
            if not release.wait(15):
                status = 504
        elif kind == "ready":
            ready, _ = self.barrier(key)
            status = 200 if ready.wait(5) else 504
            body = b""
        elif kind == "release":
            _, release = self.barrier(key)
            release.set()
            body = b""
        elif kind == "failure":
            status, body = 503, b"failure"
        elif kind == "large":
            body = b"x" * 12000
        elif kind != "value":
            status = 404
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except ConnectionError:
            pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except ConnectionError:
            pass


def validate(stdout):
    """Reconstruct lifetime/serial transitions without using library descriptors."""
    lines = stdout.splitlines()
    expected = ["lifetime, routing, queued cancellation and shutdown passed",
                "client, inflight, mailbox and storage bounds passed"]
    for count in (3, 16, 64):
        serials, generations = [0] * count, [1] * count
        for round_number in range(12):
            for client in range(count):
                serials[client] += 1
                if (client + round_number) % 4 == 0:
                    expected.append(f"closed,{count},{round_number},{client}")
                    generations[client] += 1
                    serials[client] = 0
                else:
                    cancelled = (client + round_number) % 3 == 0
                    body = "" if cancelled else f"{count}-{round_number}-{client}"
                    expected.append(f"result,{count},{round_number},{client},{serials[client]},{generations[client]},{7 if cancelled else 0},{body}")
        expected.append(f"many,{count},passed")
    expected.append("HTTP client contracts passed")
    if lines != expected:
        mismatch = next((i for i, (a, b) in enumerate(zip(lines, expected)) if a != b), min(len(lines), len(expected)))
        raise AssertionError(f"Independent result oracle mismatch at row {mismatch}: {lines[mismatch:mismatch+1]} expected {expected[mismatch:mismatch+1]}")
    return len(expected)


def run(binary):
    Handler.barriers = {}
    server = Server(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    env = dict(os.environ, NO_PROXY="127.0.0.1,localhost", no_proxy="127.0.0.1,localhost")
    try:
        process = subprocess.run([str(binary), f"http://127.0.0.1:{server.server_port}"], capture_output=True, text=True, env=env, timeout=60)
        if process.returncode:
            print(process.stdout, end=""); print(process.stderr, file=sys.stderr, end=""); process.check_returncode()
        rows = validate(process.stdout)
        corrupt = process.stdout.replace("3-0-1", "3-0-2", 1)
        try:
            validate(corrupt)
        except AssertionError:
            pass
        else:
            raise AssertionError("Oracle accepted misrouted response")
        print(f"3/16/64 HTTP clients: 996 requests, {rows} independently checked trace rows; lifecycle/bounds passed")
        return process
    finally:
        for _, release in Handler.barriers.values():
            release.set()
        server.shutdown(); server.server_close(); thread.join()


if __name__ == "__main__":
    run(sys.argv[1])
