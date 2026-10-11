# Local co-op arena

The Goose server owns a projectile World and advances it at 20 ticks per second.
Clients send FIRE and request snapshots; they never simulate a private world.
Clients share targets and score. Targets move right, shots move left, and five
missed targets end a round. RESET preserves generations. Graphics are optional.

## Library and sample boundary

| Location | Responsibility |
| --- | --- |
| `lib/lab/ecs/pool.goose`, `sparse.goose` | Identity, dense/sparse rows and generic values |
| `lib/lab/net/tcp.goose`, `line_server.goose`, `line_client.goose` | Owned sockets, bounded framing/progress and shutdown |
| `native/net/tcp` | Socket syscalls and generation-checked registry |
| `samples/arena/world.goose` | Position/Velocity/Health SoA schema, movement, TTL, damage and deferred deaths |
| `samples/arena/game.goose` | Waves, shots, misses, reset and wire commands |
| `samples/arena/client.goose` | Command correlation and atomic validated snapshots |
| `samples/arena/server.goose`, `cli.goose`, `graphics.goose` | Clock, entry points, controls and rendering |

Libraries import no samples/tools and know no game types. The game model can run
without sockets/graphics; experiments reuse it through the sample module root.
`tests/module_paths.py` checks this import boundary.

## Run locally

From a configured GUI-free build, run an automated game without a GPU:

```text
python tools/arena.py --build build-core --demo --ticks 80
```

The launcher builds the targets, starts its own server on an ephemeral loopback
port, runs the client, then shuts down and verifies socket cleanup. For graphics,
use a GUI-enabled build:

```text
python tools/arena.py --build build --graphics
python tools/arena.py --build build --graphics --headless --demo --frames 300 --screenshot local/arena.png
```

Mouse movement or Up/Down aims; Space/left-click fires. R resets the shared round
and Escape closes the client. Cyan is a shot, orange a target, green the player.
The layout is fixed at 960x720. `--demo` aims/fires automatically. Headless
graphics still require a GPU backend. Closing the launcher client shuts down
its server; interactive graphics have no process duration limit.

For multiple clients, own the server independently in one terminal:

```text
cmake --build build --config Release --target arena_server arena_game --parallel
python tools/run.py --build build arena_server --port 7777
python tools/run.py --build build arena_game 7777
```

Launch another arena_game for co-op. Closing one client keeps the server alive.
`--duration seconds` bounds server runtime; `--port 0` prints an ephemeral port.
`--manual` disables automatic ticking and enables STEP for fixtures. The default
server binds only 127.0.0.1.

## Protocol and validation

Peers receive HELLO with slot/generation. PING returns PONG. `FIRE y` accepts
-20..20 and returns FIRED or refusal. SNAPSHOT returns FRAME with
tick/score/misses/shots/count, ascending-slot ENTITY records, then END. RESET
returns RESET; CLOSE drains BYE; SHUTDOWN stops the server. Manual mode permits
STEP 1..32. RESET/SHUTDOWN are local application commands without authorization.
Eight peers share 16 entities. Invalid/capacity/game-over shots preserve state.

The [fixture](../../tests/arena_fixture.py) uses two real peers and an independent
Python dictionary model. It compares shared snapshots after 81 manual ticks,
checks fragmented FIRE, invalid input, reset generations, game over/frozen time
and one peer surviving another's close. The
[client contract](../../tests/arena_client_contract.goose) rejects duplicate,
incomplete and invalid snapshots without replacing the shown frame. The
[optional GPU fixture](../../tests/arena_graphics_fixture.py) runs a real server
and 300 GPU frames, checks scoring, player pixels, a 960x720 PNG and socket cleanup.
CLI demo also checks automatic server ticking.

The bounded World has quadratic collisions. Snapshots are polled rather than
predicted or delta-replicated. The server catches up at most four ticks per pass,
dropping excess clock debt. Firing is co-op and capacity-limited; player ownership,
rate quotas and reconnect resume remain future sample policies.
