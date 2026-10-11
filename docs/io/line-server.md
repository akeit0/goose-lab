# Caller-owned loopback line server and client

`lab.net.line_server` and `lab.net.line_client` provide bounded TCP progress.
Link `goose_lab_tcp`. They know no game state, regex syntax, application commands,
rendering or update rate. Native [tcp.c](../../native/net/tcp/tcp.c) owns sockets
and their handle registry; framing, queues and lifecycle are Goose code.

## Server

[`Service`](../../lib/lab/net/line_server.goose) owns a listener and fixed storage
for 16 peers, with 1..16 enabled logical connections. `create(Options)` binds
IPv4 loopback, accepts port 0 for an ephemeral port, and reports INVALID or
TRANSPORT without retaining failed resources. `poll(service, clock_ns())` invokes
a scoped callback with a generation ID, borrowed line, and CONNECTED/REQUEST kind:

```goose
lab_net_line_server::poll(server, clock_ns()) { id, line, kind =>
    lab_net_line_server::Reply {
        bytes: if kind == lab_net_line_server::CONNECTED {
            str("WELCOME\n")
        } else { str("ECHO ", line, "\n") }
    }
};
```

End the callback with its reply expression. A Goose block's `return` can exit its
enclosing function; do not bypass the owner's cleanup. Reply.action is KEEP,
CLOSE or STOP and precedes its resizable owned bytes. CLOSE stops reading that
peer and drains output. STOP closes the listener, discards unprocessed input and
drains all peers. `stop` initiates the same shutdown from the application. Poll
while `running`, then `destroy`; destroy also gives immediate error-path cleanup.

Each peer has 256 input bytes and 2048 output bytes. LF framing strips one optional
CR, consumes at most one request per peer per pass, and rotates the first peer.
Oversized/incomplete frames close only their peer. Before calling the handler,
the server reserves Options.response_bytes, reclaiming sent prefixes only when
their capacity is needed. Owned unsent output survives callbacks and would-block.
Oversized handler replies close the peer with an error; application side effects
are not rolled back, so handlers must honor their configured response bound.

Options include send_bytes (1..2048), an optional requested OS send_buffer,
idle_ms (0 disables idle closure), and drain_ms (1..60000). Supply monotonic
nanoseconds. Idle peers close; drain deadlines force release when peers never
resume reading. Counters distinguish blocked/partial writes, pauses, compactions,
peaks and drain timeouts. Pending data can be lost on a deadline/reset; graceful
delivery requires a reading peer. Close discards at most 256 additional unread
bytes; excessive pipelined input can still cause TCP reset.

Do not copy active Services/Clients: handles are aliases, not additional owners.
All TCP calls use one thread. The native registry holds at most 64 sockets and
rejects stale/double-close handles with generations preserved across runtime
reinitialization. Counted initialization lets one owner close while another
retains sockets; final shutdown refuses while sockets remain live. Registry
exhaustion currently reports TRANSPORT. Fixed 16-peer storage is reserved even
when fewer peers are enabled.

## Client

[`Client`](../../lib/lab/net/line_client.goose) performs a bounded loopback connect
(1..5000 ms) outside the frame loop. Subsequent poll calls never wait: they advance
one queued command and receive up to 256 bytes. `send` appends LF to a 1..255-byte
line and refuses embedded CR/LF or an occupied queue without changing it. A
2048-byte receive buffer holds complete lines; `line` exports one owned line and
preserves the remainder. EOF, transport errors and an unterminated full buffer
are explicit codes. Complete buffered lines remain readable after EOF.

The application correlates replies and supplies request deadlines. The arena
client permits one outstanding command and publishes snapshots only after END,
the declared count and all records validate. Transport knows no snapshot type.
Destroy both successful and failed owners.

## Verification

The [contract](../../tests/line_server_contract.goose) runs two independent Services
and clients in one process, checking queue refusal, stale connection/native IDs,
slot reuse, a pending-output drain timeout, and one owner closing while another
still echoes. The [TCP fixture](../../tests/server_experiment_fixture.py) checks
actual kernel would-block, another peer progressing, exact resumed response
bytes, fragmented/invalid/overflow frames, resets and socket count zero.

This loopback polling transport is validated on Windows/MSVC. Internet binding,
TLS, authentication and a multi-thread reactor are outside its current contract.
[Arena](../apps/arena.md) supplies a concrete application.
