import std;
import arena.client;
fn main() {
    var c = app_arena_client::Client { phase: 3 };
    assert(app_arena_client::consume(c, "FRAME 12 2 0 4 1"));
    assert(app_arena_client::consume(c, "ENTITY 0,18446744073709551615,1,2,1,5,2,1,1,0"));
    assert(c.shown.entities.len == 0 && c.snapshots == 0);
    assert(app_arena_client::consume(c, "END") && c.shown.entities.len == 1 && c.shown.ticks == 12);
    let image = to_bytes([c.shown]); c.phase = 3;
    assert(app_arena_client::consume(c, "FRAME 13 3 0 4 2"));
    assert(app_arena_client::consume(c, "ENTITY 0,2,1,2,1,5,2,1,1,0"));
    assert(!app_arena_client::consume(c, "ENTITY 0,2,1,2,1,5,2,1,1,0"));
    assert(!app_arena_client::consume(c, "END") && to_bytes([c.shown]) == image);
    c.phase = 3; assert(!app_arena_client::consume(c, "FRAME 1 2 0 4 17"));
    let overflow, ok = app_arena_client::uint("18446744073709551616"); assert(!ok && overflow == 0);
    print("Arena snapshot publication contract passed");
}
