// Native close can be deferred; explicit quit and default close still end frame.
import std;
import os;
import gfx;

fn main() {
    guard gfx::open_headless(32, 24) else { write_stderr(str("gfx: ", gfx::error(), "\n")); return; }
    assert(gfx::frame()); gfx::defer_close(true);
    assert(gfx::inject_text("a")); assert(gfx::inject_close()); assert(gfx::frame());
    var text = false; var close = false;
    for e in gfx::events() {
        if e.kind == gfx::EVENT_TEXT { assert(!close); text = true; }
        if e.kind == gfx::EVENT_CLOSE_REQUESTED { assert(text); close = true; }
    }
    assert(close && gfx::frame());
    gfx::quit(); assert(!gfx::frame()); gfx::close();
    assert(gfx::open_headless(32, 24)); assert(gfx::frame());
    assert(gfx::inject_close()); assert(!gfx::frame());
    assert(gfx::misuse_count() == 0); gfx::close();
    print("ordered close requests, deferred exit and default close passed");
}
