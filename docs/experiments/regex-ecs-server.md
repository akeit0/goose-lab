# Regex, ECS game and TCP server experiments

Three opt-in targets exercise Goose outside document editing. They live under
[`tools/experiments/workloads`](../../tools/experiments/workloads); their models
and transport are experiment sources with no new public library or compiler API.

| Target | Workload | Goose question |
| --- | --- | --- |
| `regex_experiment` | Batch search, captures and replacement using upstream `regex` | Can one compiled variable-size plan serve many borrowed inputs while retained results own their bytes? |
| `ecs_game_experiment` | A deterministic projectile/target arena | Can independent entity identity coexist with dense component iteration and non-LIFO structural changes? |
| `server_experiment` | Real loopback TCP controlling that same game | Can bounded connection records coordinate framing, shared application state and partially sent responses? |

The server composes the first two ideas: one compiled regex parses commands, one
World owns game state, and fixed connection records hold independent input/output
progress. C performs nonblocking socket operations; Goose parses frames, routes
requests, applies game operations and decides when connections close.

## Regex: reuse the upstream engine

[`regex_probe.goose`](../../tools/experiments/workloads/regex_probe.goose) compiles
each batch's pattern once with `compile(pattern, err)`, then checks `find`,
`matches`, `count`, capture spans/group bytes and replacement over many texts.
Capture callback slots and text are borrowed. The probe copies its first matched
bytes into a bounded owned value and keeps them across later callbacks, input
mutation and other inputs. Malformed/unsupported patterns report errors without
terminating the process; a later valid batch succeeds.

The [upstream regex API](https://github.com/aardappel/goose/blob/4f23f22629a34d971adbd8c10017d203ab6bb2fa/docs/stdlib.md#regex)
works on bytes with ASCII classes/case folding. It is an unanchored,
leftmost-first engine; anchors and word boundaries are unsupported. The server
checks match start/end explicitly to require a whole command line. A compiled
Regex owns variable-size program and DFA tables; it is not an independently
resizable object hidden in every connection.

The [Python fixture](../../tests/regex_experiment_fixture.py) uses Python's
independent [bytes regex engine](https://docs.python.org/3/library/re.html),
adapting only the documented iteration rule that suppresses an empty match at
the preceding match's end. Its corpus checks ordered alternatives, greedy/lazy
repetition, optional/nested/repeated captures, ASCII flags/classes, binary bytes,
UTF-8 byte offsets, nullable patterns and invalid syntax/unsupported features.
This establishes agreement for the selected subset, not Python/Rust/PCRE API
equivalence or an exhaustive regex-engine qualification.

## ECS: dense components, stable logical IDs

[`world.goose`](../../tools/experiments/workloads/world.goose) has a bounded entity
table and Position, Velocity and Health stores. Each component uses dense
structure-of-arrays values plus a sparse slot-to-row map. Velocity is optional:
movement traverses its dense rows and locates Position through the sparse map.
No per-entity heap object or borrowed reference into a movable component row is
retained. References borrow the World/component owner for the current operation.

Removing a component swaps its last row into the hole and repairs the moved
entity's sparse entry. Entity IDs use slot/generation independently of row
placement. Reusing an interior entity slot preserves other entities and rejects
the old ID. Whole-World images verify unchanged capacity refusal and stale-ID
refusal. Logical capacity can be 3, 16 or 64, but fixed representation always
reserves all 64 entries and component capacities.

Each tick moves entities, decrements TTL and marks expired/out-of-bounds entities.
Bullets damage targets within one grid unit on each axis. Collision resolution
uses logical slot order, and structural deletion waits until all queries finish.
Killed targets increment the score. The guaranteed opening event moves a bullet
into a target and retires both, so the fixture exercises an actual game rule.
Collision scanning is bounded but quadratic; this experiment has no spatial
acceleration, rendering, floating-point physics or general archetype framework.

The [game fixture](../../tests/ecs_game_fixture.py) uses ordinary dictionaries and
optional velocity tuples. It deletes survivors from a snapshot rather than using
dense/sparse storage or the Goose destruction bitmap. It checks every live
entity's generation, position, velocity presence/value, health, TTL and team
after each of 2400 seeded frames at 3/16/64 capacity, along with score and work
counters. Full capacity, non-LIFO reuse, component removal and final empty
component stores are also checked.

## Server: bounded progress per connection

[`server.goose`](../../tools/experiments/workloads/server.goose) owns one World,
one compiled command Regex and three connection records. Each record has a
generation, 256-byte input buffer, 2048-byte output buffer and sent offset.
It processes at most one complete frame per connection per polling pass and
reserves room for the largest response before reading/consuming more input.
A blocked connection therefore does not prevent another connection's PING.
Responses stay in FIFO order on each connection; actions across connections
are serialized by the owner's polling order.

The native [transport](../../tools/experiments/workloads/server_transport.c)
binds IPv4 loopback on an ephemeral port and exposes init/listen/accept/receive/
send/close/shutdown. Would-block and partial progress return to Goose. It contains
no game state, request parser, framing buffer or response queue. A fourth peer
waits in the OS listen backlog until a Goose connection slot becomes available;
this does not promise an exact OS backlog capacity.

Commands are ASCII lines ending in LF, optionally CRLF:

| Command | Response / effect |
| --- | --- |
| `PING` | `PONG` |
| `SPAWN x y vx vy hp ttl team` | `ID slot generation`; team 1 is a bullet, 2 a target |
| `STATE slot generation` | `STATE` plus the complete entity record, or `STATE STALE` |
| `VELOCITY slot generation enabled vx vy` | `CODE` after attaching/updating/removing Velocity |
| `DESPAWN slot generation` | `CODE` after logical deletion |
| `STEP n` | Advance 1..32 ticks; return ticks, score and live count |
| `STATS` | Game counters and live count |
| `BURST n` | An owned response with 1..1024 test bytes, exercising bounded sending |
| `CLOSE` / `SHUTDOWN` | `BYE`, drain pending output and close; shutdown closes all peers |

New peers receive `HELLO slot generation`. The game has 16 logical slots, integer
coordinates in -32..32, velocities in -8..8, health 1..99 and TTL 1..128.
Malformed/out-of-range commands refuse without changing game state. Partial EOF
and an unterminated full input buffer close only that connection. Close discards
at most 256 additional unread bytes before releasing the socket, which preserves
the error response for the tested small overflow; arbitrary excessive input can
still cause TCP reset. Shutdown discards unprocessed input while draining already
queued output. A 60-second process deadline bounds this experiment's lifetime.

The [network fixture](../../tests/server_experiment_fixture.py) checks fragmented
commands, coalesced pipelines, CRLF, incomplete frames, overflow/invalid numbers,
full entity capacity, stale entity IDs and connection generation changes, half-close,
connection reset and shutdown with another peer holding an incomplete command.
The same independent dictionary World checks replies and entity states. A large
pipeline remains unread while another peer progresses. Send calls are deliberately
limited to 32 bytes to exercise partial-send bookkeeping; the test establishes
host-buffer backpressure, not saturation of the kernel send buffer. Native
socket accounting must return to zero. These are TCP experiments, not HTTP/TLS
or production-server validation.

## Build and recorded qualification

```text
cmake -S . -B build-core -DGOOSE_SOURCE_DIR=/path/to/goose -DGOOSE_LAB_GUI=OFF -DGOOSE_LAB_BUILD_TOOLS=ON
cmake --build build-core --config Release --target regex_experiment ecs_game_experiment server_experiment --parallel
ctest --test-dir build-core -C Release -R "^(regex_experiment|ecs_game_experiment|server_experiment)$" --output-on-failure
python tools/workload_qualification.py --build build-core --output local/workloads-run
```

The [qualification runner](../../tools/workload_qualification.py) snapshots
workload/model/runner sources, stdlib and transport C, and records compiler,
source, generated C and executable hashes. It uses one selected compatible
compiler at Goose O0/O1/O2, with native C O2. Existing output directories are
refused; incomplete records survive failure. `--targets`, `--levels` and
`--repeats` allow focused runs without duplicating every experiment.

The Windows/MSVC qualification on 2026-10-11 passed all nine target/level runs:

| Per run | Independently checked work |
| --- | --- |
| Regex | 41 patterns, 1646 inputs, 10220 captures and all replacement/retained bytes |
| ECS game | 2400 frames and 18872 complete live-entity rows |
| Server | 7 connection lifetimes, 103 requests, 112 checked replies, and zero remaining native sockets |

The full GUI-free build with tools enabled also passed all 23 CTest checks.

Across the three levels this is 4938 regex inputs, 30660 captures, 7200 game
frames, 56616 entity rows and 309 network requests. The fixed generated World is
7298 bytes; each Connection is 2334 bytes. These layout measurements exclude
compiled regex tables, temporary/owned outputs, native socket buffers and
runtime/OS allocations. They do not establish total process memory or throughput.
The compiler checkout was `71e848d732362a47ee7fe000a3e1601d0196259a`, clean;
the snapshot records the new working-tree sources. Raw records remain under
ignored `local/references/workloads/development-run/`.
