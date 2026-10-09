"""Deterministic loopback HTTP/TLS contract; never contacts public services."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import ssl
import subprocess
import sys
import threading
import time


class Handler(BaseHTTPRequestHandler):
    plain_base = ""
    cancel_received = threading.Event()
    cancel_finish = threading.Event()
    def log_message(self, *_):
        pass

    def do_HEAD(self):
        self.do_GET(head=True)

    def do_GET(self, head=False):
        if self.path == "/cancel-ready":
            ready = self.cancel_received.wait(2)
            self.cancel_received.clear()
            self.send_response(200 if ready else 503)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/cancel-wait":
            self.send_response(200)
            self.send_header("Content-Length", "4096")
            self.end_headers()
            try:
                self.wfile.write(b"partial")
                self.wfile.flush()
                self.cancel_received.set()
                self.cancel_finish.wait(10)
            except (ConnectionError, ssl.SSLError):
                pass
            return
        body = b"Hello from the fixture\n"
        status = 200
        if self.path == "/slow":
            time.sleep(0.3)
        if self.path == "/missing":
            status, body = 404, b"Not found"
        if self.path == "/large":
            body = b"x" * 131072
        if self.path in ("/redirect", "/loop", "/downgrade", "/file-redirect"):
            self.send_response(302)
            destinations = {"/redirect": "/hello", "/loop": "/loop",
                            "/downgrade": self.plain_base + "/hello",
                            "/file-redirect": "file:///etc/passwd"}
            self.send_header("Location", destinations[self.path])
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/chunked":
            self.protocol_version = "HTTP/1.1"
            self.send_response(200)
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            try:
                self.wfile.write(b"40\r\n" + b"x" * 64 + b"\r\n0\r\n\r\n")
            except (ConnectionError, ssl.SSLError):
                pass
            return
        self.send_response(status)
        self.send_header("X-Goose-Fixture", "yes")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head:
            try:
                self.wfile.write(body)
            except (ConnectionError, ssl.SSLError):
                pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_PUT = do_POST


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    tls_server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    here = Path(__file__).parent
    context.load_cert_chain(here / "localhost-cert.pem", here / "localhost-key.pem")
    tls_server.socket = context.wrap_socket(tls_server.socket, server_side=True)
    threads = [threading.Thread(target=s.serve_forever, daemon=True) for s in (server, tls_server)]
    for thread in threads:
        thread.start()
    base = f"http://127.0.0.1:{server.server_port}"
    Handler.plain_base = base
    tls_base = f"https://localhost:{tls_server.server_port}"
    wrong_host = f"https://127.0.0.1:{tls_server.server_port}"
    env = dict(os.environ, NO_PROXY="127.0.0.1,localhost", no_proxy="127.0.0.1,localhost")
    try:
        command = [sys.argv[1], base, tls_base, str((here / "localhost-cert.pem").resolve()), wrong_host]
        result = subprocess.run(command, capture_output=True, text=True, env=env, timeout=30)
        print(result.stdout, end="")
        print(result.stderr, end="", file=sys.stderr)
        if result.returncode:
            return result.returncode
        return 0
    finally:
        Handler.cancel_finish.set()
        for s in (server, tls_server):
            s.shutdown()
            s.server_close()


if __name__ == "__main__":
    sys.exit(main())
