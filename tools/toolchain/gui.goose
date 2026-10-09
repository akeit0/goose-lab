// Compile-only probe for the shared UI's platform boundary and slice adapters.
import std;
import gfx;
extern "toolchain_adapter" fn adapter(positions: const f32[:], clusters: const u32[:]) -> i64;
fn main() {
    var positions: f32[0] = []; var clusters: u32[0] = [];
    print(adapter(positions, clusters));
    gfx::present_on_demand(true); gfx::request_present();
    print(gfx::screen_revision(), gfx::screen_content_revision());
    gfx::text_transactions(true); gfx::defer_close(true);
    var bytes: u8[0] = [];
    print(gfx::text_event_into(0, bytes));
    gfx::clear_composition(); gfx::text_input_area(0.0, 0.0, 1.0, 1.0, 0.0);
    for event in gfx::events() { print(event.text, event.start, event.length); }
    print(gfx::EVENT_TEXT_COMMIT, gfx::EVENT_TEXT_EDITING, gfx::EVENT_CLOSE_REQUESTED);
}
