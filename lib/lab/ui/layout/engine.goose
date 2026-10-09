// Experimental Clay layout. Main-thread only; destroy before its text provider.
// Build a hierarchy, finish, then draw widgets at the computed bounds.
namespace lab_ui_layout_engine;
import std;
import lab.ui.geometry;
import lab.ui.render.font;
import lab.text.line_break;

struct Context { id: u64 }
let OK: i32 = 0;
let INVALID: i32 = 1;
let STATE: i32 = 2;
let CAPACITY: i32 = 3;
let DUPLICATE: i32 = 4;
let BALANCE: i32 = 5;
let NATIVE: i32 = 6;
let ROW: i32 = 0;
let COLUMN: i32 = 1;
let START: i32 = 0;
let END: i32 = 1;
let CENTER: i32 = 2;
let WRAP_WORDS: i32 = 0;
let WRAP_NEWLINES: i32 = 1;
let WRAP_NONE: i32 = 2;
// Words first; break an oversized word at shaped cluster boundaries.
// Requires the lab.ui.render.font backend. A single cluster may exceed the width.
let WRAP_OVERFLOW: i32 = 3;
// Overflow wrapping with basic Japanese punctuation/kana prohibitions.
let WRAP_JAPANESE: i32 = 4;
struct Sizing { kind: i32 = 0, value: f32 = 0.0, max: f32 = 0.0 }
fn fit(min: f32 = 0.0, max: f32 = 0.0) -> Sizing { Sizing { 0, min, max } }
fn grow(min: f32 = 0.0, max: f32 = 0.0) -> Sizing { Sizing { 1, min, max } }
fn percent(fraction: f32) -> Sizing { Sizing { 2, fraction, 0.0 } }
fn fixed(size: f32) -> Sizing { Sizing { 3, size, size } }
struct Padding { left: u16 = 0, right: u16 = 0, top: u16 = 0, bottom: u16 = 0 }
fn padding(value: u16) -> Padding { Padding { value, value, value, value } }
struct Config {
    direction: i32 = COLUMN,
    width: Sizing = Sizing {}, height: Sizing = Sizing {},
    padding: Padding = Padding {}, gap: u16 = 0,
    align_x: i32 = START, align_y: i32 = START,
}
extern "glab_layout_create_font" fn create_raw(font: u64) -> u64;
fn create(font: lab_ui_render_font::Font) -> Context { Context { create_raw(font.id) } }
extern "glab_layout_destroy" fn destroy_raw(c: u64);
fn destroy(c: Context) { destroy_raw(c.id); }
extern "glab_layout_begin" fn begin_raw(c: u64, width: f32, height: f32) -> i32;
fn begin(c: Context, width: f32, height: f32) -> bool { begin_raw(c.id, width, height) == OK }
extern "glab_goose_layout_open" fn open_raw(c: u64, id: const u8[:], direction: i32,
    wk: i32, wmin: f32, wmax: f32, hk: i32, hmin: f32, hmax: f32,
    left: u16, right: u16, top: u16, bottom: u16, gap: u16, ax: i32, ay: i32) -> i32;
fn open(c: Context, id: const u8[:], config: Config = Config {}) -> bool {
    open_raw(c.id, id, config.direction, config.width.kind, config.width.value, config.width.max,
        config.height.kind, config.height.value, config.height.max,
        config.padding.left, config.padding.right, config.padding.top, config.padding.bottom,
        config.gap, config.align_x, config.align_y) == OK
}
extern "glab_layout_close" fn close_raw(c: u64) -> i32;
fn close(c: Context) -> bool { close_raw(c.id) == OK }
// Scoped blocks must complete normally: nonlocal return skips close.
fn box<F>(c: Context, id: const u8[:], config: Config = Config {}) {
    if open(c, id, config) { F(); close(c); }
}
fn leaf(c: Context, id: const u8[:], config: Config = Config {}) {
    if open(c, id, config) { close(c); }
}
extern "glab_goose_layout_text" fn text_raw(c: u64, text: const u8[:], wrap: i32) -> i32;
// Text is copied immediately into the native frame arena. Its measurement
// uses the ui context's current font/scale; borrowed text may expire now.
fn text(c: Context, value: const u8[:], wrap: i32 = WRAP_WORDS) -> bool {
    tagged_text(c, value, 0, wrap)
}
extern "glab_layout_finish" fn finish_raw(c: u64) -> i32;
fn finish(c: Context) -> bool { finish_raw(c.id) == OK }
extern "glab_goose_layout_bounds" fn bounds_raw(c: u64, id: const u8[:],
    x: f32&, y: f32&, w: f32&, h: f32&) -> bool;
// Missing IDs (including ones removed this frame) return a zero rect/false.
fn bounds(c: Context, id: const u8[:]) -> lab_ui_geometry::Rect, bool {
    var r = lab_ui_geometry::Rect {};
    let found = bounds_raw(c.id, id, r.x, r.y, r.w, r.h);
    return r, found;
}
extern "glab_layout_line_count" fn line_count_raw(c: u64) -> i64;
fn line_count(c: Context) -> i64 { line_count_raw(c.id) }
extern "glab_goose_layout_line" fn line_raw(c: u64, index: i64,
    x: f32&, y: f32&, w: f32&, h: f32&, text: u8[>..]&) -> bool;
struct Line { bounds: lab_ui_geometry::Rect, text: u8[], found: bool }
// Owned copy of a wrapped text render command. Remains valid after begin.
fn line(c: Context, index: i64) -> Line {
    var r = lab_ui_geometry::Rect {};
    var text: u8[>..] = [];
    let found = line_raw(c.id, index, r.x, r.y, r.w, r.h, text);
    Line { bounds: r, text: text, found: found }
}
extern "glab_layout_status" fn status_raw(c: u64) -> i32;
fn status(c: Context) -> i32 { status_raw(c.id) }
extern "glab_goose_layout_error" fn error_into(c: u64, out: u8[>..]&);
fn error(c: Context) -> u8[>..] {
    var out: u8[>..] = []; error_into(c.id, out); out
}

// Numeric owner tags let a composition layer associate wrapped lines with a paragraph.
// No caller pointer is retained by the native bridge.
extern "glab_goose_layout_tagged_text" fn tagged_text_raw(c: u64, text: const u8[:], wrap: i32, tag: u32) -> i32;
extern "glab_goose_layout_text_at" fn text_at_raw(c: u64, value: const u8[:], breaks: const u32[:], tag: u32) -> i32;
// Both slices are copied now; the caller retains no frame-lifetime obligation.
fn text_at(c: Context, value: const u8[:], breaks: const u32[:], tag: u32 = 0) -> bool { text_at_raw(c.id, value, breaks, tag) == OK }
fn tagged_text(c: Context, value: const u8[:], tag: u32, wrap: i32 = WRAP_WORDS) -> bool {
    if wrap == WRAP_JAPANESE {
        let breaks, ok = lab_text_line_break::japanese(value); if !ok { return false; }
        return text_at(c, value, breaks, tag);
    }
    tagged_text_raw(c.id, value, wrap, tag) == OK
}
extern "glab_layout_line_tag" fn line_tag_raw(c: u64, index: i64) -> u32;
fn line_tag(c: Context, index: i64) -> u32 { line_tag_raw(c.id, index) }

// Live Clay arena plus frame text/policy storage; excludes process/runtime memory.
extern "glab_layout_live_bytes" fn live_bytes() -> i64;
