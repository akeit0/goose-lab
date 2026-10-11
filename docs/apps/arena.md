# Star Race: offline practice and multiplayer versus

Move with WASD or the arrow keys and walk into yellow stars. Collect eight to
finish a round; a new round starts after three seconds. There is no aiming,
firing, health or missed-target penalty. Offline practice has one player and no
network calls. Versus has separate players and scores on one authoritative field.
It waits for at least two players, supports up to eight, and limits each player
to one movement step per simulation tick. Contested pickups rotate peer priority.

## Run the executables directly

Python is not required to run either mode. On Windows, from the repository root
with an existing Release build, start offline practice with one command:

```powershell
.\build\Release\arena_game.exe --solo
```

No arguments also select offline practice. Escape closes the window. For versus,
keep this server running in a terminal:

```powershell
.\build\Release\arena_server.exe --port 7777
```

From a second terminal, start a player:

```powershell
.\build\Release\arena_game.exe 7777
```

Run that client command again for a second player window. Both connect to
127.0.0.1; the server prints the selected port and each window identifies its
own player. Closing one client removes only its player. Stop the server with
Ctrl+C when finished, or give it `--duration 60` for a bounded run.
The layout is fixed at 960x720; a white outline identifies the controlled player.
Keyboard controls apply to the focused window. On one PC, give the second
client `--demo` to play against its automatic controller:

```powershell
.\build\Release\arena_game.exe 7777 --demo
```

If the targets have not been built, an already configured build only needs:

```text
cmake --build build --config Release --target arena_game arena_server --parallel
```

For a fresh application-only build without Python, disable contract tests:

```text
cmake -S . -B build-game -DGOOSE_SOURCE_DIR=/path/to/compatible/goose -DGOOSE_LAB_BUILD_TESTS=OFF
cmake --build build-game --config Release --target arena_game arena_server --parallel
```

Then substitute `build-game` for `build` in the executable paths above. This
requires the [normal native/toolchain dependencies](../../README.md#build),
including this repository's SDL submodule. Single-configuration generators put
executables directly in the build directory, with the platform's usual suffix.

Without graphics, `arena_client --solo --demo --ticks 80` runs the same offline
simulation. Two `arena_client 7777 --demo --ticks 100` processes test versus
against the server. These CLI targets also build with `GOOSE_LAB_GUI=OFF`.
`--demo` controls movement automatically; it is optional in graphical play.

## Optional Python convenience

The launcher builds the selected targets. Its default starts offline practice;
`--versus` owns an ephemeral-port server and starts two independent clients:

```text
python tools/arena.py --build build --graphics
python tools/arena.py --build build --graphics --versus
python tools/arena.py --build build-core --versus --demo --ticks 100
python tools/arena.py --build build --graphics --versus --headless --demo --frames 400
```

`--players 2..8` selects the number of launched versus clients. `--join 7777`
joins a separately owned server. The launcher shuts its server down after all
its clients exit and checks native socket cleanup. Interactive graphics have
no duration limit. Headless graphics still require a working GPU backend.
`--screenshot path.png` exports the final frame; versus exports `path-p1.png`,
`path-p2.png`, etc. Python remains a convenience for orchestration and fixtures.

## Library and sample boundary

| Location | Responsibility |
| --- | --- |
| `lib/lab/ecs/pool.goose`, `sparse.goose` | Generation identity, dense/sparse rows and generic component values |
| `lib/lab/net/tcp.goose`, `line_server.goose`, `line_client.goose` | Socket ownership, bounded framing/FIFO progress, push admission and shutdown |
| `native/net/tcp` | Socket syscalls and generation-checked registry |
| `samples/arena/game.goose` | Player/Body components, queued inputs, movement, pickups, winner and round restart |
| `samples/arena/state.goose`, `protocol.goose` | Owned view schema, capture and versioned wire commands |
| `samples/arena/client.goose` | Offline simulation or network parsing, numbered input history and prediction reconciliation |
| `samples/arena/server.goose`, `cli.goose`, `graphics.goose` | Clock, publication cadence, entry points, controls and rendering |
| `samples/arena/world.goose` | Separate projectile SoA workload retained for the opt-in ECS/TCP experiments |

Game and view capture are pure Goose. Practice calls them directly, so it does
not encode/decode a protocol or open a socket. Versus uses the same rules and
owned view types. Generic libraries import no sample/tool modules; the module
boundary contract checks this. Game networking policies remain in the sample.

## Communication

The server simulates at 20Hz and pushes complete state at up to 10Hz. Clients
send `INPUT sequence dx dy` movement steps at 20Hz, independently of incoming
state. Sequence numbers start at one; dx/dy are -1..1. A peer controls only its
own player: there is no command field for another player's identity. Duplicates
are ignored; gaps, invalid values and more than eight pending steps refuse
unchanged. At most one step per player is consumed each server tick, even if a
peer sends a burst. Input stops moving the player as soon as its queue is empty.

`WELCOME 2 slot generation` establishes the connection identity. Each pushed
packet is `FRAME 2 mode tick round winner_slot winner_generation remaining collected player_count gem_count`,
followed by PLAYER/GEM lines and END. PLAYER carries entity ID, peer ID, position,
score and the last consumed input sequence. GEM carries entity ID and position.
All numeric values, identities and counts validate before the client publishes
the whole frame. There is no SNAPSHOT request/response chain or per-input reply.

The controlled player is predicted locally. A new frame drops acknowledged
inputs and replays the remaining owned inputs over the authoritative position.
Remote players interpolate between complete frames; round changes and reused
entity generations do not interpolate across unrelated identities. Prediction
history is bounded to 32 steps. Missing state for three seconds, invalid protocol
or exhausted history ends the client connection rather than growing a queue.

The sample keeps at most one state packet in its transport output queue per
peer. When output is still pending, publication skips that peer; after it drains,
the next publication uses current state. This bounds the sample's queue of stale
states and lets other peers progress. Bytes already sent to TCP remain ordered;
they cannot be replaced. TCP loss can delay newer state, and this is a loopback
experiment rather than UDP/Internet game qualification.

PING/PONG, CLOSE/BYE and SHUTDOWN/BYE are local control commands. Only a server
started with `--manual` accepts STEP 1..32, for deterministic fixtures. Production
authentication, input-time synchronization and session resumption are not supplied.
The server catches up at most four ticks per pass and drops excessive clock debt.

## Verification

- [Game contract](../../tests/arena_game_contract.goose): waiting, contested pickup,
  unchanged input refusal, per-peer ownership and stale generation reuse.
- [Dictionary fixture](../../tests/arena_fixture.py): every pushed two-player state
  across 252 ticks, scoring, wins/restarts, fragmented commands, duplicates,
  bounded/retried input, invalid commands and disconnect/rejoin.
- [Client contract](../../tests/arena_client_contract.goose): partial/duplicate frame
  refusal, authoritative correction with unacknowledged replay, old/future ACK
  refusal and 300 socket-free offline steps including round restart.
- [Runtime fixture](../../tests/arena_runtime_fixture.py): two actual CLI clients,
  automatic ticking and 350ms delayed/23-byte fragmented state delivery.
- [GPU fixture](../../tests/arena_graphics_fixture.py): offline practice followed by
  two simultaneous network clients, 400 frames each, visible stars/own player,
  distinct peer IDs, 960x720 PNGs and zero remaining native sockets.

Validation is Windows/MSVC. The original projectile experiment retains its
independent dictionary/regex/backpressure checks; its rules are not the playable
Star Race rules. See [ECS](../ecs.md) and [line transport](../io/line-server.md).
The game/client contracts also passed standalone generated-C execution at Goose
O0/O1/O2 with native C O2 on the same selected compiler. Source/compiler/binary
hashes and raw records stay under ignored `local/references/star-race/controls-run`.
