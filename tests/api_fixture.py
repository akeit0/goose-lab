"""Exercise the complete HTTP -> JSON -> owned model -> modern UI path locally."""
import json
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

items = [{"id": 9007199254740993, "title": "Inspect café data 🚀",
          "body": ("A long response remains readable. Scroll this description independently while the list keeps its selection. " * 18),
          "completed": False}]
items += [{"id": i, "title": f"Review record {i:02d}",
           "body": "Validate the response, then bring it into your application.", "completed": i % 5 == 0}
          for i in range(2, 41)]

class Handler(BaseHTTPRequestHandler):
    waiting = threading.Event()
    finish_wait = threading.Event()
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == "/waiting":
            ready = self.waiting.wait(2)
            self.waiting.clear()
            self.send_response(200 if ready else 503)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/stall":
            self.send_response(200)
            self.send_header("Content-Length", "4096")
            self.end_headers()
            try:
                self.wfile.write(b"[")
                self.wfile.flush()
                self.waiting.set()
                self.finish_wait.wait(10)
            except ConnectionError:
                pass
            return
        status = 200
        if self.path == "/slow":
            time.sleep(0.45)
        if self.path in ("/items", "/slow"):
            data = json.dumps({"items": items}, ensure_ascii=False).encode("utf-8")
        elif self.path == "/bad":
            data = b'[\n{"id":1,}]'
        elif self.path == "/schema":
            data = b'[{"id":1,"title":"first"},{"id":1,"title":"duplicate"}]'
        elif self.path == "/empty":
            data = b"[]"
        elif self.path == "/long":
            data = json.dumps([{"id": 1, "title": "An unbroken description", "body": "x" * 2048}]).encode("utf-8")
        else:
            status, data = 503, b"Unavailable"
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

def run(args):
    result = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", timeout=45)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    print(result.stdout.strip())
    return result.stdout

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
base = f"http://127.0.0.1:{server.server_port}"
try:
    with tempfile.TemporaryDirectory(prefix="goose-api-") as temp:
        for scale in ("1.0", "1.25"):
            snapshot = Path(temp) / f"記録-{scale}.json"
            run([sys.argv[1], base, str(Path.cwd() / f"api-browser-interacted-{scale}.png"), scale, str(snapshot)])
            data = json.loads(snapshot.read_text(encoding="utf-8"))
            assert data["records"][0]["completed"] and data["selected"] == 9007199254740993 and data["query"] == "CAF"
            out = run([sys.argv[2], "--headless", "--frames", "3", "--data", str(snapshot),
                       "--screenshot", str(Path.cwd() / f"api-browser-restored-{scale}.png")])
            assert "records=40 error=0 busy=false status=0 screenshot=true" in out, out
            assert "restored=true selected=9007199254740993 changed=true blocked=false dirty=false" in out, out
        for content in (b"{broken", b'{"format":"goose-api-browser","version":2}', b"{}", b" " * 2097153):
            snapshot.write_bytes(content)
            out = run([sys.argv[2], "--headless", "--frames", "1", "--data", str(snapshot),
                       "--screenshot", str(Path.cwd() / "api-browser-rejected-file.png")])
            assert "restored=false selected=1 changed=false blocked=true dirty=false" in out, out
            assert snapshot.read_bytes() == content
        missing = Path(temp) / "missing.json"
        out = run([sys.argv[2], "--headless", "--frames", "1", "--data", str(missing)])
        assert "restored=false selected=1 changed=false blocked=false dirty=false" in out and not missing.exists()

    with tempfile.TemporaryDirectory(prefix="goose-api-compact-") as compact:
        out = run([sys.argv[2], "--headless", "--data", str(Path(compact) / "snapshot.json"), "--fetch", "--url", base + "/items", "--frames", "3",
                   "--width", "560", "--height", "860", "--screenshot", str(Path.cwd() / "api-browser-compact.png")])
        assert "records=40 error=0 busy=false status=200 screenshot=true" in out, out
    out = run([sys.argv[2], "--headless", "--no-data", "--fetch", "--url", base + "/long", "--frames", "3",
               "--screenshot", str(Path.cwd() / "api-browser-long-word.png")])
    assert "records=1 error=0 busy=false status=200 screenshot=true" in out, out
finally:
    Handler.finish_wait.set()
    server.shutdown()
    server.server_close()
    thread.join()
