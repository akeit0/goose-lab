"""Automatic ticks with two CLI players and delayed/fragmented pushed state."""
from collections import deque
from contextlib import contextmanager
from pathlib import Path
import re
import select
import socket
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from arena import server


@contextmanager
def delayed(port):
    listener = socket.socket(); listener.bind(('127.0.0.1', 0)); listener.listen(1); listener.settimeout(1)
    stopped = threading.Event(); errors = []; connected = []

    def relay():
        try:
            while not stopped.is_set():
                try: front, _ = listener.accept(); break
                except socket.timeout: continue
            else: return
            back = socket.create_connection(('127.0.0.1', port), timeout=3); connected.extend((front, back))
            front.setblocking(False); back.setblocking(False)
            upstream = bytearray(); downstream = deque(); buffered = 0
            while not stopped.is_set():
                now = time.monotonic()
                writes = ([back] if upstream else []) + ([front] if downstream and downstream[0][0] <= now else [])
                reads, writes, _ = select.select([front, back], writes, [], 0.005)
                if front in reads:
                    data = front.recv(4096)
                    if not data: break
                    upstream += data; assert len(upstream) <= 65536
                if back in reads:
                    data = back.recv(4096)
                    if not data: break
                    # Fragment headers, entity records and END across reads.
                    for offset in range(0, len(data), 23):
                        part = data[offset:offset+23]; downstream.append((time.monotonic() + 0.350, part)); buffered += len(part)
                    assert buffered <= 65536
                if back in writes and upstream:
                    sent = back.send(upstream); del upstream[:sent]
                if front in writes and downstream:
                    deadline, data = downstream[0]; sent = front.send(data); buffered -= sent
                    if sent == len(data): downstream.popleft()
                    else: downstream[0] = (deadline, data[sent:])
        except (ConnectionResetError, BrokenPipeError): pass  # Client's bounded run ends normally.
        except BaseException as error: errors.append(error)
        finally:
            for connection in connected: connection.close()

    thread = threading.Thread(target=relay, daemon=True); thread.start()
    try: yield listener.getsockname()[1]
    finally:
        stopped.set(); thread.join(timeout=4); listener.close(); assert not thread.is_alive()
        if errors: raise errors[0]


binary = str(Path(sys.argv[2]).resolve())
with server(Path(sys.argv[1]).resolve()) as (port, output):
    with delayed(port) as delayed_port:
        clients = []
        try:
            for destination in (delayed_port, port):
                clients.append(subprocess.Popen([binary, str(destination), '--demo', '--ticks', '100'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            peers = set()
            for index, process in enumerate(clients):
                stdout, stderr = process.communicate(timeout=20); assert process.returncode == 0, stdout + stderr
                assert 'offline=false' in stdout and 'failed=false' in stdout
                assert int(re.search(r'collected=(\d+)', stdout)[1]) > 0
                peers.add(re.search(r'peer=(\d+)', stdout)[1])
                if index == 0: assert int(re.search(r'history_peak=(\d+)', stdout)[1]) >= 6
                print(stdout, end='')
            assert peers == {'0', '1'}
        finally:
            for process in clients:
                if process.poll() is None: process.kill(); process.communicate(timeout=5)
print('Arena runtime passed: two CLI players, 350 ms delayed/23-byte fragmented state, numbered input history and zero server sockets')
