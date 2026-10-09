"""Child executable used to test actual argv and capture/lifetime boundaries."""
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")
mode = sys.argv[1]
if mode == "echo":
    print(json.dumps(sys.argv[2:], ensure_ascii=False))
elif mode == "exit":
    sys.stderr.write("intentional failure")
    sys.exit(42)
elif mode == "sleep":
    time.sleep(20)
elif mode == "bytes":
    os.write(1, b"\x00\r\n\n\x1a\xff")
elif mode == "stdin-echo":
    # Produce enough output before reading to deadlock a serial write-then-read.
    os.write(1, b"x" * 131072)
    while True:
        data = os.read(0, 4096)
        if not data:
            break
        os.write(1, data)
    os.write(2, b"EOF\n")
elif mode == "stdin-dialog":
    for line in sys.stdin.buffer:
        os.write(1, b"reply:" + line)
elif mode == "stdin-closed":
    os.close(0)
    os.write(1, b"closed\n")
    time.sleep(0.1)
    os.write(1, b"still output\n")
elif mode == "stream":
    os.write(1, b"first\n")
    os.write(2, b"warning:\xff\n")
    time.sleep(0.35)
    encoded = "日本語\n".encode("utf-8")
    os.write(1, encoded[:2])
    time.sleep(0.05)
    os.write(1, encoded[2:] + b"last\n")
elif mode == "tree-stall":
    subprocess.Popen([sys.executable, __file__, "child", sys.argv[2]])
    os.write(1, b"spawned\n")
    time.sleep(20)
elif mode == "flood":
    def write(fd):
        for _ in range(512):
            os.write(fd, b"x" * 4096)
    worker = threading.Thread(target=write, args=(2,))
    worker.start()
    write(1)
    worker.join()
elif mode == "tree":
    subprocess.Popen([sys.executable, __file__, "child", sys.argv[2]])
elif mode == "child":
    time.sleep(1)
    Path(sys.argv[2]).write_text("orphan survived", encoding="utf-8")
elif mode == "touch":
    Path(sys.argv[2]).write_text("unexpected external diff", encoding="utf-8")
