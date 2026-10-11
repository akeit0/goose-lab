"""Socket-free GPU practice, then two simultaneous GPU clients on a real server."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from arena import server


def check_png(png):
    contents = png.read_bytes(); assert contents[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", contents[16:24]) == (960, 720)


with tempfile.TemporaryDirectory(prefix="goose star race gfx ") as directory:
    root = Path(directory); binary = str(Path(sys.argv[2]).resolve())
    solo = subprocess.run([binary, '--solo', '--headless', '--demo', '--frames', '400', '--screenshot', str(root / 'solo.png')],
                          capture_output=True, text=True, timeout=20)
    assert solo.returncode == 0, solo.stdout + solo.stderr
    assert 'offline=true' in solo.stdout and 'failed=false' in solo.stdout; check_png(root / 'solo.png'); print(solo.stdout, end='')
    with server(Path(sys.argv[1]).resolve()) as (port, output):
        clients = []
        try:
            for index in range(2):
                png = root / f'p{index}.png'
                clients.append(subprocess.Popen([binary, str(port), '--headless', '--demo', '--frames', '400', '--screenshot', str(png)],
                                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            peers = set()
            for index, process in enumerate(clients):
                stdout, stderr = process.communicate(timeout=20); assert process.returncode == 0, stdout + stderr
                assert 'offline=false' in stdout and 'failed=false' in stdout and 'frames=400' in stdout and 'seen_players=2' in stdout
                peers.add(stdout.split('peer=')[1].split()[0]); check_png(root / f'p{index}.png'); print(stdout, end='')
            assert peers == {'0', '1'}
        finally:
            for process in clients:
                if process.poll() is None: process.kill(); process.communicate(timeout=5)
    print("Star Race graphics passed: offline with no sockets, two independent versus players, server native sockets=0")
