// Deliberately uses no text shaping: unused adapter types must still compile.
import std;
import gfx;
import vec;
import lab.ui.render.font;
import lab.ui.geometry;
import lab.ui.render.scene;
fn main() {
    assert(gfx::open_headless(64, 64));
    var canvas = lab_ui_render_scene::create(lab_ui_render_font::default_font());
    assert(canvas.fonts.len == 1 && gfx::frame());
    lab_ui_render_scene::begin(canvas, 64.0, 64.0);
    lab_ui_render_scene::fill(canvas, lab_ui_geometry::rect(8.0, 8.0, 32.0, 32.0), float4 { 1.0, 0.0, 0.0, 1.0 }, 4.0);
    lab_ui_render_scene::render(canvas, float4 { 0.0, 0.0, 0.0, 1.0 });
    let pixels = gfx::read_pixels(gfx::screen()); assert(pixels.len == 64 * 64 * 4);
    assert(pixels[(20 * 64 + 20) * 4] > 240 && pixels[0] == 0);
    assert(gfx::misuse_count() == 0);
    lab_ui_render_scene::destroy(canvas); gfx::close();
    print("Modern shape-only adapter contract passed");
}
