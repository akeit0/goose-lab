import std;
import arena.client;
import arena.state;
import lab.net.tcp;
fn gems(c: app_arena_client::Client&) {
    assert(app_arena_client::consume(c, "PLAYER 7 1 1 1 36 4 0 0"));
    for slot in 6 { let line = str("GEM ", slot, " 1 20 ", slot * 4); assert(app_arena_client::consume(c, line)); }
}
fn main() {
    var c = app_arena_client::Client {};
    assert(!app_arena_client::consume(c, "WELCOME 1 0 1"));
    assert(app_arena_client::consume(c, "WELCOME 2 0 18446744073709551615"));
    assert(app_arena_client::consume(c, "FRAME 2 1 0 1 -1 0 0 0 2 6"));
    assert(app_arena_client::consume(c, "PLAYER 6 1 0 18446744073709551615 4 4 0 0")); gems(c);
    assert(c.shown.players.len == 0 && app_arena_client::consume(c, "END"));
    c.sequence = 4; c.history = [app_arena_game::Input { 1, 1, 0 }, app_arena_game::Input { 2, 0, 1 }, app_arena_game::Input { 3, 1, 0 }, app_arena_game::Input { 4, 0, 1 }];
    c.predicted_x = 6; c.predicted_y = 6;
    assert(app_arena_client::consume(c, "FRAME 2 1 2 1 -1 0 0 0 2 6"));
    assert(app_arena_client::consume(c, "PLAYER 6 1 0 18446744073709551615 3 5 0 2")); gems(c);
    assert(app_arena_client::consume(c, "END"));
    assert(c.history.len == 2 && c.history[0].sequence == 3 && c.acknowledged == 2 && c.predicted_x == 4 && c.predicted_y == 6 && c.corrections == 1);
    assert(app_arena_client::consume(c, "FRAME 2 1 3 1 -1 0 0 0 2 6"));
    assert(app_arena_client::consume(c, "PLAYER 6 1 0 18446744073709551615 4 6 0 4")); gems(c);
    assert(app_arena_client::consume(c, "END") && c.history.len == 0);
    let image = to_bytes([c.shown]); c.phase = 1;
    assert(app_arena_client::consume(c, "FRAME 2 1 4 1 -1 0 0 0 2 6"));
    assert(app_arena_client::consume(c, "PLAYER 6 1 0 18446744073709551615 4 6 0 4"));
    assert(!app_arena_client::consume(c, "PLAYER 6 1 1 1 4 6 0 0"));
    assert(!app_arena_client::consume(c, "GEM 6 1 20 3"));
    assert(!app_arena_client::consume(c, "END") && to_bytes([c.shown]) == image);
    c.phase = 1; assert(!app_arena_client::consume(c, "FRAME 2 1 5 1 -1 0 0 0 9 6"));
    c.pending = c.shown; c.players = 2; c.gems = 6; c.pending.ticks = 2;
    assert(!app_arena_client::publish(c)); c.pending.ticks = 5;
    c.pending.players[0].acknowledged = 3; assert(!app_arena_client::publish(c));
    c.pending.players[0].acknowledged = 5; assert(!app_arena_client::publish(c));
    assert(to_bytes([c.shown]) == image && c.acknowledged == 4 && c.history.len == 0);
    let overflow, ok = app_arena_client::uint("18446744073709551616"); assert(!ok && overflow == 0);
    // Offline practice calls the pure simulation directly and never opens TCP.
    var solo = app_arena_client::solo(true); assert(solo.network.socket == 0 && !solo.network.initialized && lab_net_tcp::live() == 0);
    for i in 300 { assert(app_arena_client::issue(solo)); assert(solo.history.len == 0 && lab_net_tcp::live() == 0); }
    assert(solo.shown.collected >= 16 && solo.shown.round >= 2 && solo.shown.ticks == 300);
    app_arena_client::destroy(solo); assert(lab_net_tcp::live() == 0);
    print("Arena client contract passed: atomic frames, numbered-input reconciliation and socket-free offline rounds");
}
