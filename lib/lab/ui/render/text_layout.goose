// Owned shaped line, borrowed font. Close before the owning font is destroyed.
namespace lab_ui_render_text_layout;
import std;
import lab.ui.render.font;
import lab.text.grapheme;
struct Layout { id: u64 = 0 }
extern "glab_goose_text_layout_create" fn create_raw(font: u64, source: const u8[:], carets: const u32[:]) -> u64;
extern "glab_text_layout_destroy" fn destroy_raw(id: u64);
extern "glab_text_layout_width" fn width_raw(id: u64) -> f32;
extern "glab_text_layout_bytes" fn bytes_raw(id: u64) -> i64;
extern "glab_text_layout_position" fn position_raw(id: u64, byte: i64) -> f32;
extern "glab_text_layout_hit" fn hit_raw(id: u64, x: f32) -> i64;
extern "glab_text_layout_live_bytes" fn live_bytes() -> i64;
extern "glab_goose_text_layout_window" fn window_raw(id: u64, left: f32, right: f32, positions: f32[:], clusters: u32[:]) -> i64;
fn create(font: lab_ui_render_font::Font, source: const u8[:]) -> Layout { let carets,ok=lab_text_grapheme::offsets(source); if !ok { return Layout {}; } Layout { create_raw(font.id, source, carets) } }
fn close(l: Layout&) { destroy_raw(l.id); l.id = 0; }
fn width(l: Layout) -> f32 { width_raw(l.id) }
fn bytes(l: Layout) -> i64 { bytes_raw(l.id) }
fn position(l: Layout, byte: i64) -> f32 { position_raw(l.id, byte) }
fn hit(l: Layout, x: f32) -> i64 { hit_raw(l.id, x) }
fn window(l: Layout, left: f32, right: f32) -> lab_ui_render_font::Glyph[>..] {
    var positions: f32[>..] = []; var clusters: u32[>..] = []; let n = window_raw(l.id, left, right, positions, clusters); var glyphs: lab_ui_render_font::Glyph[>..] = []; if n < 0 { return glyphs; }
    positions.resize(n * 11, 0.0); clusters.resize(n, 0);
    if window_raw(l.id, left, right, positions, clusters) != n { return glyphs; }
    for i in n { let j = i*11; glyphs.push(lab_ui_render_font::Glyph { positions[j], positions[j+1], positions[j+2], positions[j+3], positions[j+4], positions[j+5], positions[j+6], positions[j+7], positions[j+8], positions[j+9], positions[j+10]>0.5, clusters[i] }); } glyphs
}
