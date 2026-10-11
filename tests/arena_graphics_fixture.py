"""Optional GPU smoke: the graphical Goose client talks to a real Goose server."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from arena import server


with tempfile.TemporaryDirectory(prefix="goose arena gfx ") as directory:
    png = Path(directory) / "arena.png"
    with server(Path(sys.argv[1]).resolve()) as (port, output):
        result = subprocess.run([sys.argv[2], str(port), "--headless", "--demo", "--frames", "300", "--screenshot", str(png)],
                                capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "failed=false" in result.stdout and "GRAPHICS frames=300" in result.stdout
        contents = png.read_bytes(); assert contents[:8] == b"\x89PNG\r\n\x1a\n"
        assert struct.unpack(">II", contents[16:24]) == (960, 720)
        print(result.stdout, end="")
    print("Arena graphics integration passed; server native sockets=0")
