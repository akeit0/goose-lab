// Fractional wheel events retain their order and clear their aggregate each frame.
import std;
import os;
import gfx;

fn main() {
    guard gfx::open_headless(32, 24) else {
        write_stderr(str("gfx: ", gfx::error(), "\n")); return;
    }
    assert(gfx::frame());
    gfx::inject_mouse(7.0, 9.0, 0, false);
    assert(gfx::inject_wheel(1.25, -0.5));
    assert(gfx::inject_wheel(-2.0, 1.0));
    assert(gfx::mouse_wheel() == 0.0);
    assert(gfx::frame());
    var seen: i64 = 0;
    for event in gfx::events() {
        if event.kind == gfx::EVENT_MOUSE_WHEEL {
            if seen == 0 { assert(event.x == 1.25 && event.y == -0.5); }
            else { assert(seen == 1 && event.x == -2.0 && event.y == 1.0); }
            seen++;
        }
    }
    assert(seen == 2 && gfx::mouse_wheel() == 0.5);
    assert(gfx::mouse_pos().x == 7.0 && gfx::mouse_pos().y == 9.0);
    assert(gfx::frame() && gfx::mouse_wheel() == 0.0);
    for event in gfx::events() { assert(event.kind != gfx::EVENT_MOUSE_WHEEL); }
    assert(gfx::inject_focus(false)); assert(gfx::inject_wheel(0.0, -1.0));
    assert(gfx::inject_focus(true)); assert(gfx::frame());
    assert(gfx::mouse_wheel() == 0.0 && gfx::misuse_count() == 0);
    gfx::close(); print("wheel order, fractional deltas, aggregate, pointer and focus passed");
}
