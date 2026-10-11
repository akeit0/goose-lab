// Atomic UTF-8 commits, ordered preedit, token lifetime and legacy scalar input.
import std;
import os;
import gfx;

fn main() {
    gfx::text_transactions(true);
    guard gfx::open_headless(32, 24) else { write_stderr(str("gfx: ", gfx::error(), "\n")); return; }
    assert(gfx::frame());
    assert(gfx::inject_editing("kana", 1, 2));
    assert(gfx::inject_text("日本語"));
    assert(gfx::frame());
    var seen: i64 = 0; var token: u64 = 0;
    for e in gfx::events() {
        if e.kind == gfx::EVENT_TEXT_EDITING || e.kind == gfx::EVENT_TEXT_COMMIT {
            var bytes: u8[32] = [0; 32];
            let n = gfx::text_event_into(e.text, bytes);
            if seen == 0 { assert(e.kind == gfx::EVENT_TEXT_EDITING && e.start == 1 && e.length == 2); assert(bytes[..n] == "kana"); }
            else { assert(seen == 1 && e.kind == gfx::EVENT_TEXT_COMMIT); assert(bytes[..n] == "日本語"); }
            token = e.text; seen++;
        }
    }
    assert(seen == 2 && token != 0);
    assert(gfx::frame());
    var empty: u8[0] = [];
    assert(gfx::text_event_into(token, empty) == -1);
    assert(gfx::inject_editing("", -1, -1));
    assert(gfx::frame());
    var cleared = false;
    for e in gfx::events() { if e.kind == gfx::EVENT_TEXT_EDITING { assert(gfx::text_event_into(e.text, empty) == 0); cleared = true; } }
    assert(cleared);
    gfx::text_transactions(false);
    assert(gfx::inject_text("ab") && gfx::frame());
    seen = 0;
    for e in gfx::events() { if e.kind == gfx::EVENT_TEXT { assert(e.codepoint == (if seen == 0 { 97 } else { 98 })); seen++; } }
    assert(seen == 2 && gfx::misuse_count() == 0);
    gfx::close();
    assert(gfx::text_event_into(token, empty) == -1);
    print("ordered preedit, atomic UTF-8, expired tokens and legacy text passed");
}
