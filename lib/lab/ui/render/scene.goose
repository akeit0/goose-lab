// Goose-owned GPU painting and retained draw batches.
namespace lab_ui_render_scene;
import std;
import math;
import vec;
import gfx;
import lab.ui.geometry;
import lab.ui.render.font;

struct Vertex { pos: float2, uv: float2, color: float4, params: float4 }
// One instance per rectangle/glyph, including rotated strokes. 72 bytes instead
// of six 48-byte vertices; same 10,922-quad limit as the former vertex array.
struct Quad { origin: float2, dx: float2, dy: float2, uv: float4, color: float4, params: float4 }
struct Asset { font: lab_ui_render_font::Font, texture: gfx::Texture, revision: u64 }
struct Batch { first: i64, count: i64, font: i64, clip: lab_ui_geometry::Rect }
struct Canvas {
    pipeline: gfx::Pipeline, sampler: gfx::Sampler, buffer: gfx::Buffer, corners: gfx::Buffer,
    capacity: i64, scale: f32, stamp: u64 = 0, renders: u64 = 0, skipped: u64 = 0, seen_screen: i64 = -1,
    fonts: Asset[..16] = [], quads: Quad[..10922] = [], batches: Batch[..2048] = [],
    clip: lab_ui_geometry::Rect, clips: lab_ui_geometry::Rect[..32] = [],
}
extern "glab_scene_create" fn stamp_create() -> u64;
extern "glab_scene_destroy" fn stamp_destroy(id: u64);
extern "glab_goose_scene_changed" fn changed(id: u64, vertices: const u8[:], batches: const u8[:], key: const u8[:], force: bool) -> i32;
extern "glab_scene_live_bytes" fn live_bytes() -> i64;
fn add_font(c: Canvas&, path: const u8[:], size: f32, fallback: const u8[:] = lab_ui_render_font::default_fallback(), emoji: const u8[:] = lab_ui_render_font::default_emoji(), symbols: const u8[:] = lab_ui_render_font::default_symbols()) -> i64 {
    assert(c.fonts.len < 16);
    let font = lab_ui_render_font::create_family(path, fallback, size, c.scale);
    if font.id == 0 { return -1; }
    if symbols.len>0 && !lab_ui_render_font::add_fallback(font,symbols) { lab_ui_render_font::destroy(font); return -1; }
    if emoji.len>0 && !lab_ui_render_font::add_emoji(font,emoji) { lab_ui_render_font::destroy(font); return -1; }
    let texture = gfx::texture2d(1024, 1024);
    if texture.id == 0 { lab_ui_render_font::destroy(font); return -1; }
    c.fonts.push(Asset { font, texture, 0 });
    c.fonts.len - 1
}
fn create(path: const u8[:], scale: f32 = 1.0, fallback: const u8[:] = lab_ui_render_font::default_fallback(), emoji: const u8[:] = lab_ui_render_font::default_emoji(), symbols: const u8[:] = lab_ui_render_font::default_symbols()) -> Canvas {
    var c = default<Canvas>(); c.scale = scale;
    if add_font(c, path, 16.0, fallback, emoji, symbols) < 0 { return c; }
    let vs = embed_shader("vert", """
        layout(location=0) in vec2 a_corner;
        layout(location=1) in vec2 a_origin;
        layout(location=2) in vec2 a_dx;
        layout(location=3) in vec2 a_dy;
        layout(location=4) in vec4 a_uv;
        layout(location=5) in vec4 a_color;
        layout(location=6) in vec4 a_params;
        layout(location=0) out vec2 v_uv;
        layout(location=1) out vec4 v_color;
        layout(location=2) out vec4 v_params;
        layout(set=1,binding=0) uniform Screen { vec4 size; };
        void main() {
            vec2 corner=a_corner;
            v_uv=mix(a_uv.xy,a_uv.zw,corner); v_color=a_color; v_params=a_params;
            vec2 p=(a_origin+a_dx*corner.x+a_dy*corner.y)/size.xy;
            gl_Position=vec4(p.x*2.0-1.0,1.0-p.y*2.0,0.0,1.0);
        }
        """);
    let fs = embed_shader("frag", """
        layout(set=2,binding=0) uniform sampler2D atlas;
        layout(location=0) in vec2 v_uv;
        layout(location=1) in vec4 v_color;
        layout(location=2) in vec4 v_params;
        layout(location=0) out vec4 result;
        void main() {
            float alpha;
            if(v_params.w>1.5) {
                vec4 glyph=texture(atlas,v_uv);
                result=vec4(glyph.rgb/max(glyph.a,0.00001),glyph.a*v_color.a);
                return;
            }
            if(v_params.w>0.5) { alpha=texture(atlas,v_uv).a; }
            else {
                vec2 q=abs((v_uv-0.5)*v_params.xy)-(v_params.xy*0.5-v_params.z);
                float d=length(max(q,0.0))+min(max(q.x,q.y),0.0)-v_params.z;
                float aa=max(fwidth(d),0.0001);
                alpha=1.0-smoothstep(-aa*0.5,aa*0.5,d);
            }
            result=vec4(v_color.rgb,v_color.a*alpha);
        }
        """);
    var desc = gfx::PipelineDesc { blend: gfx::BLEND_ALPHA, instance_location: 1 };
    desc.formats[0] = gfx::VERTEX_FLOAT2; desc.formats[1] = gfx::VERTEX_FLOAT2; desc.formats[2] = gfx::VERTEX_FLOAT2;
    desc.formats[3] = gfx::VERTEX_FLOAT2; desc.formats[4] = gfx::VERTEX_FLOAT4; desc.formats[5] = gfx::VERTEX_FLOAT4; desc.formats[6] = gfx::VERTEX_FLOAT4;
    c.pipeline = gfx::pipeline(vs, fs, desc);
    c.sampler = gfx::sampler(gfx::LINEAR, gfx::CLAMP);
    let corners: f32[12] = [0.0,0.0,1.0,0.0,1.0,1.0,0.0,0.0,1.0,1.0,0.0,1.0];
    c.corners = gfx::buffer(gfx::BUFFER_VERTEX,48,bytes_of(corners)); assert(c.corners.id != 0);
    c.stamp = stamp_create(); assert(c.stamp != 0); gfx::present_on_demand(true);
    c
}
fn destroy(c: Canvas&) {
    stamp_destroy(c.stamp); c.stamp = 0;
    for asset in c.fonts { gfx::release(asset.texture); lab_ui_render_font::destroy(asset.font); }
    if c.buffer.id != 0 { gfx::release(c.buffer); }
    if c.corners.id != 0 { gfx::release(c.corners); }
    c.corners = gfx::Buffer {0};
    if c.pipeline.id != 0 { gfx::release(c.pipeline); }
    if c.sampler.id != 0 { gfx::release(c.sampler); }
    c.fonts.resize(0); c.quads.resize(0); c.batches.resize(0);
    c.buffer = gfx::Buffer { 0 }; c.pipeline = gfx::Pipeline { 0 }; c.sampler = gfx::Sampler { 0 }; c.capacity = 0;
}
fn begin(c: Canvas&, width: f32, height: f32) {
    assert(width > 0.0 && height > 0.0);
    c.quads.resize(0); c.batches.resize(0); c.clips.resize(0);
    c.clip = lab_ui_geometry::rect(0.0, 0.0, width, height);
}
fn push_clip(c: Canvas&, r: lab_ui_geometry::Rect) { c.clips.push(c.clip); c.clip = lab_ui_geometry::intersect(c.clip, r); }
fn pop_clip(c: Canvas&) { assert(c.clips.len > 0); c.clip = c.clips[c.clips.len - 1]; c.clips.resize(c.clips.len - 1); }
fn quad(c: Canvas&, r: lab_ui_geometry::Rect, uv: float4, color: float4, params: float4, font: i64 = 0) {
    if r.w <= 0.0 || r.h <= 0.0 || c.clip.w <= 0.0 || c.clip.h <= 0.0 { return; }
    let first = c.quads.len;
    c.quads.push(Quad { float2 { r.x,r.y }, float2 { r.w,0.0 }, float2 { 0.0,r.h }, uv,color,params });
    let n = c.batches.len;
    if n > 0 && c.batches[n - 1].font == font && c.batches[n - 1].clip == c.clip { c.batches[n - 1].count += 1; }
    else { c.batches.push(Batch { first, 1, font, c.clip }); }
}
fn fill(c: Canvas&, r: lab_ui_geometry::Rect, color: float4, radius: f32 = 0.0) {
    quad(c, r, float4 { 0.0, 0.0, 1.0, 1.0 }, color,
        float4 { r.w, r.h, min(max(0.0, radius), min(r.w, r.h) / 2.0), 0.0 });
}
fn border(c: Canvas&, r: lab_ui_geometry::Rect, background: float4, stroke: float4, radius: f32 = 8.0, width: f32 = 1.0) {
    fill(c, r, stroke, radius);
    fill(c, lab_ui_geometry::rect(r.x + width, r.y + width, r.w - 2.0 * width, r.h - 2.0 * width), background, max(0.0, radius - width));
}
fn stroke(c: Canvas&, a: float2, b: float2, color: float4, width: f32 = 2.0) {
    let dx = b.x - a.x; let dy = b.y - a.y; let distance = sqrt(dx * dx + dy * dy);
    if distance <= 0.0 || width <= 0.0 { return; }
    let start = c.quads.len;
    quad(c, lab_ui_geometry::rect(0.0, 0.0, distance, width), float4 { 0.0, 0.0, 1.0, 1.0 }, color,
        float4 { distance, width, min(distance, width) / 2.0, 0.0 });
    if c.quads.len == start { return; }
    let q .= c.quads[start];
    q.origin = float2 { a.x + width*dy/(2.0*distance), a.y - width*dx/(2.0*distance) };
    q.dx = float2 { dx,dy }; q.dy = float2 { -width*dy/distance,width*dx/distance };
}
fn draw_glyphs(c: Canvas&, font: i64, x: f32, y: f32, glyphs: const lab_ui_render_font::Glyph[:], color: float4) {
    for g in glyphs {
        let px: f32 = round((x + g.x) * c.scale) / c.scale;
        let py: f32 = round((y + g.y) * c.scale) / c.scale;
        quad(c, lab_ui_geometry::rect(px, py, g.w, g.h), float4 { g.u0, g.v0, g.u1, g.v1 },
            color, float4 { 0.0, 0.0, 0.0, if g.colored { 2.0 } else { 1.0 } }, font);
    }
}
fn text(c: Canvas&, font: i64, x: f32, y: f32, value: const u8[:], color: float4) -> f32 {
    assert(font >= 0 && font < c.fonts.len);
    let glyphs, width = lab_ui_render_font::shape(c.fonts[font].font, value);
    draw_glyphs(c, font, x, y, glyphs, color);
    width
}
fn label(c: Canvas&, font: i64, bounds: lab_ui_geometry::Rect, value: const u8[:], color: float4, centered: bool = false) {
    let f = c.fonts[font].font;
    let width = lab_ui_render_font::width(f, value);
    let height = lab_ui_render_font::metrics(f).height;
    push_clip(c, bounds);
    text(c, font, bounds.x + (if centered { (bounds.w - width) / 2.0 } else { 0.0 }),
        bounds.y + (bounds.h - height) / 2.0, value, color);
    pop_clip(c);
}
// Keep full-line shaping and its origin stable as the window/selection moves.
fn text_window(c: Canvas&, font: i64, x: f32, y: f32, value: const u8[:], color: float4) {
    let glyphs, width = lab_ui_render_font::window(c.fonts[font].font, value, c.clip.x - x, c.clip.x + c.clip.w - x);
    draw_glyphs(c, font, x, y, glyphs, color);
}
// Every visual input participates in exact comparison. Poll/reducers remain active.
// No GPU uploads, screen pass or presentation is generated for an identical scene.
fn render(c: Canvas&, background: float4) -> bool {
    assert(c.clips.len == 0 && c.pipeline.id != 0);
    var key: u64[..80] = [gfx::open_count() as u64, gfx::screen_revision() as u64, c.pipeline.id, c.sampler.id, c.corners.id];
    let screen_key = gfx::screen_size(); key.push(screen_key.x as u64); key.push(screen_key.y as u64);
    var colors: f32[5] = [background.x, background.y, background.z, background.w, c.scale];
    let color_bytes = bytes_of(colors); for byte in color_bytes { key.push(byte); }
    for asset in c.fonts { key.push(asset.font.id); key.push(asset.texture.id); key.push(lab_ui_render_font::revision(asset.font)); }
    let update = changed(c.stamp, bytes_of(c.quads), bytes_of(c.batches), bytes_of(key), c.seen_screen != gfx::screen_content_revision()); assert(update >= 0);
    if update == 0 { c.skipped++; return false; }
    for i in c.fonts.len {
        let revision = lab_ui_render_font::revision(c.fonts[i].font);
        if revision != c.fonts[i].revision {
            let pixels = lab_ui_render_font::pixels(c.fonts[i].font);
            assert(gfx::update_texture(c.fonts[i].texture, pixels));
            c.fonts[i].revision = revision;
        }
    }
    if c.quads.len > 0 {
        let bytes = bytes_of(c.quads);
        if bytes.len > c.capacity {
            if c.buffer.id != 0 { gfx::release(c.buffer); }
            c.capacity = next_pow2(max(bytes.len, 4096));
            c.buffer = gfx::buffer(gfx::BUFFER_VERTEX, c.capacity, "");
        }
        assert(gfx::update_buffer(c.buffer, bytes));
    }
    assert(gfx::begin_screen(background));
    if c.quads.len > 0 {
        gfx::bind(c.pipeline); gfx::bind_vertex_buffer(c.corners); gfx::bind_vertex_buffer(1, c.buffer, 0);
        let screen = gfx::screen_size();
        gfx::uniforms(gfx::VERTEX, 0, float4 { screen.x / c.scale, screen.y / c.scale, 0.0, 0.0 });
        for batch in c.batches {
            let r = batch.clip;
            let x: i64 = floor(r.x * c.scale) as i64; let y: i64 = floor(r.y * c.scale) as i64;
            let w: i64 = min(screen.x as i64, ceil((r.x + r.w) * c.scale) as i64) - x;
            let h: i64 = min(screen.y as i64, ceil((r.y + r.h) * c.scale) as i64) - y;
            if w > 0 && h > 0 {
                gfx::scissor(x, y, w, h);
                gfx::bind_texture(gfx::FRAGMENT, 0, c.fonts[batch.font].texture, c.sampler);
                gfx::draw(6, batch.count, 0, batch.first);
            }
        }
    }
    gfx::end_pass(); c.seen_screen = gfx::screen_content_revision(); c.renders++; return true;
}

fn vertex(c: const Canvas&, at: i64) -> Vertex {
    let q=c.quads[at/6]; let i=at%6;
    let x: f32 = if i==1 || i==2 || i==4 { 1.0 } else { 0.0 };
    let y: f32 = if i==2 || i==4 || i==5 { 1.0 } else { 0.0 };
    Vertex { q.origin+q.dx*x+q.dy*y, float2 { if x==0.0 { q.uv.x } else { q.uv.z }, if y==0.0 { q.uv.y } else { q.uv.w } }, q.color,q.params }
}
