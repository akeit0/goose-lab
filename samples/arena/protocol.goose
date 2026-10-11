// Versioned sample protocol, deliberately outside the transport library.
namespace app_arena_protocol;
import std;
import arena.game;
import arena.state;
import lab.net.line_server;
fn snapshot(g: const app_arena_game::Game&) -> u8[>..] {
    let s = app_arena_state::capture(g); var out: u8[>..] = [];
    format(out, "FRAME 2 ", if s.versus { 1 } else { 0 }, " ", s.ticks, " ", s.round, " ", s.winner.slot, " ", s.winner.generation,
        " ", s.remaining, " ", s.collected, " ", s.players.len, " ", s.gems.len, "\n");
    for p in s.players { format(out, "PLAYER ", p.id.slot, " ", p.id.generation, " ", p.peer.slot, " ", p.peer.generation,
        " ", p.x, " ", p.y, " ", p.score, " ", p.acknowledged, "\n"); }
    for gem in s.gems { format(out, "GEM ", gem.id.slot, " ", gem.id.generation, " ", gem.x, " ", gem.y, "\n"); }
    out.append("END\n"); assert(out.len <= 2048); out
}
fn route(g: app_arena_game::Game&, peer: app_arena_game::Peer, line: const u8[:], manual: bool) -> lab_net_line_server::Reply {
    if line == "PING" { return lab_net_line_server::Reply { bytes: str("PONG\n") }; }
    if line == "CLOSE" { return lab_net_line_server::Reply { action: lab_net_line_server::CLOSE, bytes: str("BYE\n") }; }
    if line == "SHUTDOWN" { return lab_net_line_server::Reply { action: lab_net_line_server::STOP, bytes: str("BYE\n") }; }
    let fields = split(line, ' ');
    if fields.len == 4 && fields[0] == "INPUT" {
        let sequence, seq_ok = parse_int(fields[1]); let dx, dx_ok = parse_int(fields[2]); let dy, dy_ok = parse_int(fields[3]);
        if seq_ok && dx_ok && dy_ok && app_arena_game::input(g, peer, app_arena_game::Input { sequence, dx, dy }) == 0 {
            return lab_net_line_server::Reply {};
        }
    }
    if manual && fields.len == 2 && fields[0] == "STEP" {
        let count, ok = parse_int(fields[1]); if ok && count >= 1 && count <= 32 {
            for i in count { app_arena_game::tick(g); } return lab_net_line_server::Reply { bytes: str("STEPPED\n") };
        }
    }
    lab_net_line_server::Reply { bytes: str("ERR input\n") }
}
