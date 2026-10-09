namespace lab_ui_render_font;
import std;
import lab.text.line_break;
struct Font { id: u64 }
// Font is an owned family handle: one primary face, up to seven fallbacks,
// one common baseline and atlas. Copied handles are borrowed aliases.
struct Glyph { x: f32, y: f32, w: f32, h: f32, u0: f32, v0: f32, u1: f32, v1: f32, pen: f32, advance: f32, colored: bool, cluster: u32 }
struct Metrics { height: f32 = 0.0, ascent: f32 = 0.0, scale: f32 = 0.0 }
extern "glab_goose_text_create" fn create_raw(path: const u8[:], size: f32, scale: f32) -> u64;
fn create(path: const u8[:], size: f32 = 16.0, scale: f32 = 1.0) -> Font { Font { create_raw(path, size, scale) } }
extern "glab_goose_text_add_fallback" fn add_fallback_raw(font: u64, path: const u8[:], face_index: i32) -> bool;
// Configure before metrics, layout creation, measurement or shaping seals it.
fn add_fallback(font: Font, path: const u8[:], face_index: i32 = 0) -> bool { add_fallback_raw(font.id, path, face_index) }
extern "glab_goose_text_add_emoji" fn add_emoji_raw(font: u64, path: const u8[:], face_index: i32) -> bool;
fn add_emoji(font: Font, path: const u8[:], face_index: i32 = 0) -> bool { add_emoji_raw(font.id, path, face_index) }
fn create_family(primary: const u8[:], fallback: const u8[:], size: f32 = 16.0, scale: f32 = 1.0, face_index: i32 = 0) -> Font {
    let font = create(primary, size, scale);
    if font.id != 0 && fallback.len > 0 && !add_fallback(font, fallback, face_index) { destroy(font); return Font { 0 }; }
    font
}
extern "glab_text_has_glyph" fn has_glyph_raw(font: u64, codepoint: u32) -> bool;
fn has_glyph(font: Font, codepoint: u32) -> bool { has_glyph_raw(font.id, codepoint) }
extern "glab_goose_text_fit" fn fit_raw(font: u64, value: const u8[:], width: f32) -> i64;
// UTF-8 byte count. Does not rasterize. An indivisible cluster may be wider.
fn fit(font: Font, value: const u8[:], width: f32) -> i64 { fit_raw(font.id, value, width) }
extern "glab_goose_text_fit_at" fn fit_at_raw(font: u64, value: const u8[:], width: f32, breaks: const u32[:]) -> i64;
// Caller policy offsets intersect shaped clusters; the hard end is implicit.
fn fit_at(font: Font, value: const u8[:], width: f32, breaks: const u32[:]) -> i64 { fit_at_raw(font.id, value, width, breaks) }
fn fit_japanese(font: Font, value: const u8[:], width: f32) -> i64 {
    let breaks, ok = lab_text_line_break::japanese(value); if !ok { return -1; }
    fit_at(font, value, width, breaks)
}
extern "glab_text_destroy" fn destroy_raw(font: u64);
fn destroy(font: Font) { destroy_raw(font.id); }
extern "glab_text_metrics" fn metrics_raw(font: u64, height: f32&, ascent: f32&, scale: f32&) -> bool;
fn metrics(font: Font) -> Metrics { var m = Metrics {}; metrics_raw(font.id, m.height, m.ascent, m.scale); m }
// Primitive slice ABI avoids depending on generated struct names in the C adapter.
extern "glab_goose_text_shape" fn shape_raw(font: u64, text: const u8[:], positions: f32[:], clusters: u32[:], width: f32&) -> i64;
extern "glab_goose_text_geometry" fn geometry_raw(font: u64, text: const u8[:], positions: f32[:], clusters: u32[:], width: f32&) -> i64;
extern "glab_goose_text_window" fn window_raw(font: u64, text: const u8[:], left: f32, right: f32, positions: f32[:], clusters: u32[:], width: f32&) -> i64;
fn shaped(font: Font, text: const u8[:], geometry: bool, left: f32, right: f32) -> Glyph[>..], f32 {
    var glyphs: Glyph[>..] = []; var width: f32 = 0.0;
    var positions: f32[>..] = []; var clusters: u32[>..] = [];
    fn load() -> i64 {
        if geometry { geometry_raw(font.id, text, positions, clusters, width) }
        else if right >= left { window_raw(font.id, text, left, right, positions, clusters, width) }
        else { shape_raw(font.id, text, positions, clusters, width) }
    }
    let n = load(); assert(n >= 0);
    positions.resize(n * 11, 0.0); clusters.resize(n, 0);
    assert(load() == n);
    for i in n {
        let offset = i * 11;
        glyphs.push(Glyph { positions[offset], positions[offset + 1], positions[offset + 2], positions[offset + 3],
            positions[offset + 4], positions[offset + 5], positions[offset + 6], positions[offset + 7],
            positions[offset + 8], positions[offset + 9], positions[offset + 10] > 0.5, clusters[i] });
    }
    return glyphs, width;
}
fn shape(font: Font, text: const u8[:]) -> Glyph[>..], f32 { let glyphs, width = shaped(font, text, false, 0.0, -1.0); return glyphs, width; }
// Only pen/advance/cluster are populated. Does not alter the raster atlas.
fn geometry(font: Font, text: const u8[:]) -> Glyph[>..], f32 { let glyphs, width = shaped(font, text, true, 0.0, -1.0); return glyphs, width; }
fn window(font: Font, text: const u8[:], left: f32, right: f32) -> Glyph[>..], f32 { let glyphs, width = shaped(font, text, false, left, right); return glyphs, width; }
extern "glab_goose_text_width" fn width_raw(font: u64, text: const u8[:]) -> f32;
fn width(font: Font, text: const u8[:]) -> f32 { width_raw(font.id, text) }
extern "glab_text_revision" fn revision_raw(font: u64) -> u64;
fn revision(font: Font) -> u64 { revision_raw(font.id) }
extern "glab_goose_text_pixels" fn pixels_raw(font: u64, out: u8[:]) -> i64;
fn pixels(font: Font) -> u8[>..] {
    var out: u8[>..] = []; let n = pixels_raw(font.id, out); out.resize(n, 0); pixels_raw(font.id, out); out
}
extern "glab_goose_text_error" fn error_into(out: u8[>..]&);
fn error() -> u8[>..] { var out: u8[>..] = []; error_into(out); out }
extern "glab_goose_text_default_font" fn default_font_into(out: u8[>..]&);
fn default_font() -> u8[>..] { var out: u8[>..] = []; default_font_into(out); out }
extern "glab_goose_text_default_fallback" fn default_fallback_into(out: u8[>..]&);
fn default_fallback() -> u8[>..] { var out: u8[>..] = []; default_fallback_into(out); out }
extern "glab_goose_text_default_emoji" fn default_emoji_into(out: u8[>..]&);
fn default_emoji() -> u8[>..] { var out: u8[>..] = []; default_emoji_into(out); out }
extern "glab_goose_text_default_symbol" fn default_symbols_into(out: u8[>..]&);
fn default_symbols() -> u8[>..] { var out: u8[>..] = []; default_symbols_into(out); out }

extern "glab_goose_text_default_mono" fn default_mono_into(out: u8[>..]&);
fn default_mono() -> u8[>..] { var out: u8[>..] = []; default_mono_into(out); out }

// Live native allocation accounting, distinct from process/driver memory.
extern "glab_text_source_bytes" fn source_bytes() -> i64;
extern "glab_text_atlas_bytes" fn atlas_bytes() -> i64;
