import std;
import os;
import math;
import vec;
import gfx;
import lab.ui.geometry;
import lab.ui.render.font;
import lab.ui.render.text_layout;
import lab.ui.controls.field;
import lab.ui.views.text;
import lab.ui.layout.engine;
import lab.ui.render.scene;
import lab.ui.input.interaction;
import lab.ui.controls.components;
import lab.text.utf8;
import lab.text.grapheme;
import lab.text.line_break;
fn key(name: const u8[:]) -> gfx::Event { var e = default<gfx::Event>(); e.kind = gfx::EVENT_KEY; e.scancode = gfx::scancode(name) as i32; e.down = true; e }
fn mouse(x: f32, down: bool) -> gfx::Event { var e = default<gfx::Event>(); e.kind = gfx::EVENT_MOUSE_BUTTON; e.button = gfx::MOUSE_LEFT; e.x = x; e.y = 30.0; e.down = down; e }
fn register(s: lab_ui_input_interaction::State&) {
    lab_ui_input_interaction::begin(s);
    lab_ui_input_interaction::register(s, 1, lab_ui_geometry::rect(10.0, 10.0, 80.0, 40.0));
    lab_ui_input_interaction::register(s, 2, lab_ui_geometry::rect(100.0, 10.0, 80.0, 40.0), false);
    lab_ui_input_interaction::register(s, 3, lab_ui_geometry::rect(200.0, 10.0, 80.0, 40.0));
}
fn main() {
    native_grapheme_contract();
    assert(gfx::open_headless(800, 480)); // Enough physical pixels for the 200% emoji scene.
    assert(lab_ui_render_font::create("missing-font.ttf").id == 0);
    var c = lab_ui_render_scene::create(lab_ui_render_font::default_font()); assert(c.fonts.len == 1 && c.pipeline.id != 0);
    scene_idle_contract(c);
    emoji_contract();
    let font = c.fonts[0].font;
    let fallback_path = lab_ui_render_font::default_fallback();
    if fallback_path.len > 0 {
        let primary = lab_ui_render_font::create(lab_ui_render_font::default_font());
        assert(lab_ui_render_font::has_glyph(font, 0x65E5));
        assert(abs(lab_ui_render_font::width(primary, "office café") - lab_ui_render_font::width(font, "office café")) < 0.001);
        let fallback = lab_ui_render_font::create(fallback_path);
        assert(abs(lab_ui_render_font::width(fallback, "日本語が") - lab_ui_render_font::width(font, "日本語が")) < 0.001);
        let jp, jp_width = lab_ui_render_font::shape(font, "日本語が");
        assert(jp.len == 4 && jp[3].cluster == 9 && jp_width > 30.0);
        assert(!lab_ui_render_font::add_fallback(font, fallback_path)); // Sealed family.
        let fresh = lab_ui_render_font::create(lab_ui_render_font::default_font());
        assert(!lab_ui_render_font::add_fallback(fresh, "missing-fallback.ttf"));
        assert(!lab_ui_render_font::add_fallback(fresh, fallback_path, 999));
        assert(lab_ui_render_font::add_fallback(fresh, fallback_path)); // Failed additions leave the primary intact.
        assert(lab_ui_render_font::metrics(fresh).ascent >= lab_ui_render_font::metrics(fallback).ascent);
        lab_ui_render_font::destroy(fresh); lab_ui_render_font::destroy(fallback); lab_ui_render_font::destroy(primary);
    }
    retained_layout_contract(font);
    let revision = lab_ui_render_font::revision(font);
    assert(lab_ui_render_font::fit(font, "éX", 0.0) == 3); // Whole combining cluster, even at zero width.
    assert(lab_ui_render_font::fit(font, "office", 0.0) == 1);
    assert(lab_ui_render_font::revision(font) == revision); // Fitting/measurement never rasterize.
    let office, office_width = lab_ui_render_font::shape(font, "office");
    let prefix = lab_ui_render_font::fit(font, "office", lab_ui_render_font::width(font, "of"));
    var boundary = prefix == "office".len;
    for glyph in office { if glyph.cluster == prefix { boundary = true; } }
    assert(boundary); // Do not assume every configured font supplies an ffi ligature.
    let glyphs, width = lab_ui_render_font::shape(font, "office café Ελληνικά");
    assert(glyphs.len > 10 && width > 100.0);
    assert(abs(width - lab_ui_render_font::width(font, "office café Ελληνικά")) < 0.001);
    for g in glyphs { assert(g.cluster < "office café Ελληνικά".len); assert(abs(g.x - round(g.x)) < 0.001); }
    for scale in [1.0, 1.25, 1.5, 2.0] {
        var scaled = lab_ui_render_scene::create(lab_ui_render_font::default_font(), scale as f32);
        assert(scaled.fonts.len == 1);
        lab_ui_render_scene::begin(scaled, 200.0, 100.0);
        lab_ui_render_scene::text(scaled, 0, 12.37, 15.19, "office café", float4 { 1.0, 1.0, 1.0, 1.0 });
        // Inspect final geometry after fractional placement, not just native glyph offsets.
        for vertex_index in scaled.quads.len * 6 { let vertex=lab_ui_render_scene::vertex(scaled,vertex_index);
            assert(abs(vertex.pos.x * scaled.scale - round(vertex.pos.x * scaled.scale)) < 0.001);
            assert(abs(vertex.pos.y * scaled.scale - round(vertex.pos.y * scaled.scale)) < 0.001);
        }
        let shaped, advance = lab_ui_render_font::shape(scaled.fonts[0].font, "سلام");
        assert(shaped.len > 0 && advance > 0.0 && shaped[0].cluster > shaped[shaped.len - 1].cluster);
        let old = scaled.fonts[0].font; lab_ui_render_scene::destroy(scaled);
        let replacement = lab_ui_render_font::create(lab_ui_render_font::default_font(), 16.0, scale as f32);
        assert(replacement.id != 0 && old.id != replacement.id && lab_ui_render_font::revision(old) == 0);
        lab_ui_render_font::destroy(old); assert(lab_ui_render_font::metrics(replacement).height > 0.0); lab_ui_render_font::destroy(replacement);
    }
    let layout = lab_ui_layout_engine::create(font); assert(layout.id != 0);
    assert(lab_ui_layout_engine::begin(layout, 150.0, 200.0));
    lab_ui_layout_engine::box(layout, "wrap", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit() }) { lab_ui_layout_engine::text(layout, "A paragraph that wraps using the same shaped text metrics as painting."); };
    assert(lab_ui_layout_engine::finish(layout) && lab_ui_layout_engine::line_count(layout) >= 3);
    for i in lab_ui_layout_engine::line_count(layout) { let line = lab_ui_layout_engine::line(layout, i); assert(abs(line.bounds.w - lab_ui_render_font::width(font, line.text)) < 0.05); }
    // Responsive emergency wrapping preserves bytes and only divides clusters.
    let long = "https://example.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz日本語がéoffice";
    for available in [90.0, 150.0, 300.0] {
        assert(lab_ui_layout_engine::begin(layout, available as f32, 10000.0));
        lab_ui_layout_engine::box(layout, "long", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit() }) {
            assert(lab_ui_layout_engine::text(layout, long, lab_ui_layout_engine::WRAP_OVERFLOW));
        };
        assert(lab_ui_layout_engine::finish(layout)); var joined: u8[>..] = [];
        assert(lab_ui_layout_engine::line_count(layout) > 1);
        for i in lab_ui_layout_engine::line_count(layout) {
            let line = lab_ui_layout_engine::line(layout, i); assert(lab_text_utf8::valid(line.text));
            assert(line.bounds.w <= available as f32 + 0.05 && abs(line.bounds.w - lab_ui_render_font::width(font, line.text)) < 0.001);
            joined.append(line.text);
        }
        assert(joined == long);
        let r, found = lab_ui_layout_engine::bounds(layout, "long"); assert(found);
        assert(abs(r.h - lab_ui_layout_engine::line_count(layout) * lab_ui_render_font::metrics(font).height) < 0.05);
    }
    assert(lab_ui_layout_engine::begin(layout, lab_ui_render_font::width(font, "Alpha beta ") + 1.0, 500.0));
    lab_ui_layout_engine::box(layout, "words", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit() }) {
        lab_ui_layout_engine::text(layout, "Alpha beta gamma delta", lab_ui_layout_engine::WRAP_OVERFLOW);
    };
    assert(lab_ui_layout_engine::finish(layout) && lab_ui_layout_engine::line(layout, 0).text == "Alpha beta"); // Preserve ordinary word breaks.
    // Policy offsets intersect shaping clusters; forbidden punctuation moves
    // with its neighbor even when the unbreakable group exceeds a tiny width.
    assert(lab_ui_render_font::fit_japanese(font, "あ「いう", lab_ui_render_font::width(font, "あ「")) == 3);
    assert(lab_ui_render_font::fit_japanese(font, "あい、う", lab_ui_render_font::width(font, "あい")) == 3);
    assert(lab_ui_render_font::fit_japanese(font, "「あ」い", 1.0) == 9);
    assert(lab_ui_render_font::fit_at(font, "éX", 1.0, [1, 3, 4]) == 3); // Illegal mark split is discarded.
    assert(lab_ui_render_font::fit_at(font, "abc", 1.0, [2, 1]) == -1);
    let prose = "日本語の「括弧」、句読点。小さな『きゃ』と長音ーを自然に折り返します。";
    for width in [64.0, 96.0, 144.0] {
        assert(lab_ui_layout_engine::begin(layout, width as f32, 10000.0));
        lab_ui_layout_engine::box(layout, "japanese", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit() }) {
            assert(lab_ui_layout_engine::tagged_text(layout, prose, 42, lab_ui_layout_engine::WRAP_JAPANESE));
        };
        assert(lab_ui_layout_engine::finish(layout)); var joined: u8[>..] = [];
        for i in lab_ui_layout_engine::line_count(layout) {
            let line = lab_ui_layout_engine::line(layout, i); assert(line.text.len > 0 && lab_text_utf8::valid(line.text));
            let cp, next, valid = lab_text_utf8::decode(line.text, 0); assert(valid && lab_text_line_break::can_start(cp));
            var at = 0; var last: i64 = 0;
            while at < line.text.len { let cp, next, ok = lab_text_utf8::decode(line.text, at); assert(ok); last = cp; at = next; }
            assert(lab_text_line_break::can_end(last) && line.bounds.w <= width as f32 + 0.05);
            assert(lab_ui_layout_engine::line_tag(layout, i) == 42); joined.append(line.text);
        }
        assert(joined == prose);
    }
    // The native frame owns both text and policy arrays before caller mutation.
    assert(lab_ui_layout_engine::begin(layout, 30.0, 1000.0));
    lab_ui_layout_engine::box(layout, "custom", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit() }) {
        var text: u8[>..] = str("abcdefghi"); var breaks: u32[>..] = [3, 6, 9];
        assert(lab_ui_layout_engine::text_at(layout, text, breaks, 71)); text.resize(0); breaks.resize(0);
    };
    assert(lab_ui_layout_engine::finish(layout) && lab_ui_layout_engine::line_count(layout) == 3);
    assert(lab_ui_layout_engine::line(layout, 0).text == "abc" && lab_ui_layout_engine::line_tag(layout, 0) == 71);
    assert(lab_ui_layout_engine::begin(layout, 100.0, 100.0)); assert(lab_ui_layout_engine::open(layout, "invalid-breaks"));
    assert(!lab_ui_layout_engine::text_at(layout, "abc", [2, 1]) && !lab_ui_layout_engine::finish(layout));
    assert(lab_ui_layout_engine::begin(layout, 100.0, 100.0)); lab_ui_layout_engine::leaf(layout, "recovered"); assert(lab_ui_layout_engine::finish(layout));
    var s = lab_ui_input_interaction::State {}; register(s);
    let down = [mouse(30.0, true)]; lab_ui_input_interaction::resolve(s, down, float2 { 30.0, 30.0 }, true);
    assert(s.captured == 1 && s.focused == 1 && !lab_ui_input_interaction::clicked(s, 1));
    register(s); let up = [mouse(30.0, false)]; lab_ui_input_interaction::resolve(s, up, float2 { 30.0, 30.0 }, true);
    assert(lab_ui_input_interaction::clicked(s, 1) && s.captured == 0);
    register(s); let drag = [mouse(30.0, true), mouse(230.0, false)]; lab_ui_input_interaction::resolve(s, drag, float2 { 230.0, 30.0 }, true);
    assert(!lab_ui_input_interaction::clicked(s, 1) && !lab_ui_input_interaction::clicked(s, 3));
    register(s); let disabled = [mouse(130.0, true), mouse(130.0, false)]; lab_ui_input_interaction::resolve(s, disabled, float2 { 130.0, 30.0 }, true);
    assert(s.focused == 0 && !lab_ui_input_interaction::clicked(s, 2));
    register(s); let tab = [key("Tab")]; lab_ui_input_interaction::resolve(s, tab, float2 { 0.0, 0.0 }, true); assert(s.focused == 1);
    register(s); lab_ui_input_interaction::resolve(s, tab, float2 { 0.0, 0.0 }, true); assert(s.focused == 3);
    register(s); var previous = key("Tab"); previous.mods = gfx::MOD_SHIFT;
    lab_ui_input_interaction::resolve(s, [previous], float2 { 0.0, 0.0 }, true); assert(s.focused == 1);
    register(s); lab_ui_input_interaction::resolve(s, tab, float2 { 0.0, 0.0 }, true); assert(s.focused == 3);
    register(s); let enter = [key("Return")]; lab_ui_input_interaction::resolve(s, enter, float2 { 0.0, 0.0 }, true); assert(lab_ui_input_interaction::clicked(s, 3));
    register(s); lab_ui_input_interaction::resolve(s, [], float2 { 0.0, 0.0 }, false); assert(s.focused == 0 && s.captured == 0);
    register(s); lab_ui_input_interaction::register(s, 9, lab_ui_geometry::rect(10.0, 10.0, 80.0, 40.0), false);
    lab_ui_input_interaction::resolve(s, [mouse(30.0, true), mouse(30.0, false)], float2 { 30.0, 30.0 }, true);
    assert(!lab_ui_input_interaction::clicked(s, 1)); // Disabled top layer blocks click-through.
    lab_ui_input_interaction::begin(s); lab_ui_input_interaction::register(s, 8, lab_ui_geometry::rect(0.0, 0.0, 0.0, 0.0));
    lab_ui_input_interaction::resolve(s, tab, float2 { 0.0, 0.0 }, true); assert(s.focused == 0);
    gfx::inject_mouse(30.0, 30.0, gfx::MOUSE_LEFT, true);
    gfx::inject_mouse(30.0, 30.0, gfx::MOUSE_LEFT, false);
    assert(gfx::frame()); register(s);
    lab_ui_input_interaction::resolve(s, gfx::events(), gfx::mouse_pos(), gfx::focused());
    assert(lab_ui_input_interaction::clicked(s, 1)); // Full platform-event -> input bridge.
    // Focus and hover paint must preserve label geometry.
    lab_ui_render_scene::begin(c, 400.0, 240.0);
    lab_ui_controls_components::button(c, s, 1, lab_ui_geometry::rect(12.37, 12.19, 160.0, 44.0), "Stable label");
    var label: float2[>..] = [];
    for vertex_index in c.quads.len * 6 { let vertex=lab_ui_render_scene::vertex(c,vertex_index); if vertex.params.w > 0.5 { label.push(vertex.pos); } }
    s.focused = 0; s.hovered = 0; s.clicks.resize(0);
    lab_ui_render_scene::begin(c, 400.0, 240.0);
    lab_ui_controls_components::button(c, s, 1, lab_ui_geometry::rect(12.37, 12.19, 160.0, 44.0), "Stable label");
    var label_index = 0;
    for vertex_index in c.quads.len * 6 { let vertex=lab_ui_render_scene::vertex(c,vertex_index); if vertex.params.w > 0.5 { assert(vertex.pos == label[label_index]); label_index++; } }
    assert(label_index == label.len && label_index > 0);
    lab_ui_render_scene::begin(c, 400.0, 240.0);
    lab_ui_render_scene::push_clip(c, lab_ui_geometry::rect(40.0, 40.0, 40.0, 40.0));
    lab_ui_render_scene::fill(c, lab_ui_geometry::rect(0.0, 0.0, 100.0, 100.0), float4 { 0.0, 1.0, 0.0, 1.0 });
    lab_ui_render_scene::pop_clip(c); lab_ui_render_scene::text(c, 0, 120.0, 40.0, "Pixel aligned text", float4 { 1.0, 1.0, 1.0, 1.0 });
    assert(c.batches.len == 2); lab_ui_render_scene::render(c, float4 { 0.0, 0.0, 0.0, 1.0 });
    let pixels = gfx::read_pixels(gfx::screen()); let screen=gfx::screen_size(); let stride=screen.x as i64;
    assert(pixels.len == stride * (screen.y as i64) * 4);
    assert(pixels[(50 * stride + 50) * 4 + 1] > 240);
    assert(pixels[(20 * stride + 20) * 4 + 1] < 5);
    // A small exported visual makes the policy difference reviewable.
    assert(lab_ui_layout_engine::begin(layout, 260.0, 1000.0));
    lab_ui_layout_engine::box(layout, "comparison", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fit(), gap: 100 }) {
        lab_ui_layout_engine::box(layout, "before", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(80.0), height: lab_ui_layout_engine::fit() }) {
            lab_ui_layout_engine::tagged_text(layout, "日本語の「括弧」、句読点。", 1, lab_ui_layout_engine::WRAP_OVERFLOW);
        };
        lab_ui_layout_engine::box(layout, "after", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(80.0), height: lab_ui_layout_engine::fit() }) {
            lab_ui_layout_engine::tagged_text(layout, "日本語の「括弧」、句読点。", 2, lab_ui_layout_engine::WRAP_JAPANESE);
        };
    };
    assert(lab_ui_layout_engine::finish(layout)); lab_ui_render_scene::begin(c, 400.0, 240.0);
    assert(lab_ui_layout_engine::line(layout, 0).text == "日本語の「");
    var saw_after = false;
    for i in lab_ui_layout_engine::line_count(layout) {
        if !saw_after && lab_ui_layout_engine::line_tag(layout, i) == 2 {
            assert(lab_ui_layout_engine::line(layout, i).text == "日本語の"); saw_after = true;
        }
    }
    assert(saw_after); // Same source bytes do not share mutable measurement tapes.
    lab_ui_render_scene::text(c, 0, 20.0, 12.0, "Before", float4 { 0.6, 0.65, 0.72, 1.0 });
    lab_ui_render_scene::text(c, 0, 200.0, 12.0, "Kinsoku", float4 { 0.6, 0.65, 0.72, 1.0 });
    for i in lab_ui_layout_engine::line_count(layout) {
        let line = lab_ui_layout_engine::line(layout, i);
        lab_ui_render_scene::text(c, 0, 20.0 + line.bounds.x, 54.0 + line.bounds.y, line.text, float4 { 0.9, 0.92, 0.95, 1.0 });
    }
    lab_ui_render_scene::render(c, float4 { 0.04, 0.05, 0.065, 1.0 }); assert(gfx::screenshot("japanese-kinsoku.png"));
    assert(gfx::misuse_count() == 0);
    lab_ui_layout_engine::destroy(layout); lab_ui_render_scene::destroy(c);
    assert(lab_ui_render_font::revision(font) == 0);
    assert(lab_ui_render_font::source_bytes()==0 && lab_ui_render_font::atlas_bytes()==0 && lab_ui_render_text_layout::live_bytes()==0);
    // Deferred requests are ordered, remain cancellable, and never override explicit quit.
    gfx::defer_close(true); assert(gfx::inject_close() && gfx::frame()); let requests=gfx::events();
    assert(requests.len==1 && requests[0].kind==gfx::EVENT_CLOSE_REQUESTED && gfx::frame());
    gfx::quit(); assert(!gfx::frame()); gfx::close();
    assert(gfx::open_headless(64,64) && gfx::inject_close() && !gfx::frame()); gfx::close();
    print("Modern scene, text, and interaction contract passed");
}

fn retained_layout_contract(font: lab_ui_render_font::Font) {
    let before = lab_ui_render_text_layout::live_bytes();
    for raw in ["", "office café", "日本語がé", "a\tb\x01c", "   "] {
        let shown = lab_ui_views_text::display(raw); let points = lab_ui_controls_field::stops(font, shown);
        var layout = lab_ui_render_text_layout::create(font, raw); assert(layout.id != 0);
        assert(abs(lab_ui_render_text_layout::width(layout)-lab_ui_render_font::width(font, shown))<0.001);
        var at=0; var offset=0;
        loop {
            let x=lab_ui_controls_field::position(points,offset); assert(abs(lab_ui_render_text_layout::position(layout,at)-x)<0.001);
            let hit=lab_ui_render_text_layout::hit(layout,x); assert(hit>=0 && hit<=raw.len && (hit==raw.len || (raw[hit] & 0xC0)!=0x80));
            if at==raw.len { break; }
            let cp,next,ok=lab_text_utf8::decode(raw,at); assert(ok);
            offset += if cp==9 { 4 } else if cp<32 || (cp>=127 && cp<=159) || cp==0x2028 || cp==0x2029 { 1 } else { next-at }; at=next;
        }
        let expected, width=lab_ui_render_font::window(font, shown, 1.0, 75.0); let actual=lab_ui_render_text_layout::window(layout,1.0,75.0);
        assert(expected.len==actual.len); for i in actual.len { assert(abs(expected[i].x-actual[i].x)<0.001 && abs(expected[i].y-actual[i].y)<0.001 && expected[i].u0==actual[i].u0 && expected[i].cluster==actual[i].cluster); }
        let stale=layout; lab_ui_render_text_layout::close(layout); assert(layout.id==0 && lab_ui_render_text_layout::bytes(stale)==0);
    }
    for raw in ["é", "👍🏽", "👨‍👩‍👧‍👦", "🇯🇵", "क्‍ष"] {
        var clusters=lab_ui_render_text_layout::create(font,raw); assert(clusters.id!=0);
        let stops,ok=lab_text_grapheme::offsets(raw); assert(ok);
        for i in 101 { let byte=lab_ui_render_text_layout::hit(clusters,lab_ui_render_text_layout::width(clusters)*i/100); var found=false; for stop in stops { if stop==byte { found=true; } } assert(found); }
        lab_ui_render_text_layout::close(clusters);
    }
    assert(lab_ui_render_text_layout::live_bytes()==before);
    assert(lab_ui_render_text_layout::create(font, "\xFF").id==0);
    var excessive: u8[>..]=[]; excessive.resize(1048576,'\t'); assert(lab_ui_render_text_layout::create(font,excessive).id==0 && lab_ui_render_text_layout::live_bytes()==before);
    var long: u8[>..]=[]; long.resize(262144,'a'); var layout=lab_ui_render_text_layout::create(font,long); assert(layout.id!=0);
    assert(lab_ui_render_text_layout::bytes(layout)<16*1024*1024);
    let end=lab_ui_render_text_layout::position(layout,long.len); assert(end>100000.0 && lab_ui_render_text_layout::hit(layout,end)==long.len);
    let visible=lab_ui_render_text_layout::window(layout,end-100.0,end); assert(visible.len>0 && visible.len<100);
    lab_ui_render_text_layout::close(layout); assert(lab_ui_render_text_layout::live_bytes()==before);
    print("Retained text layout: UTF-8/tab/ligature caret parity, viewport glyph parity, long-line bounds and explicit cleanup passed");
}

fn emoji_contract() {
    let argv=args(); let path: u8[>..]=if argv.len>2 { argv[2] } else { lab_ui_render_font::default_emoji() }; if path.len==0 { print("Emoji font not configured; color checks skipped"); return; }
    let sources=lab_ui_render_font::source_bytes(); let atlases=lab_ui_render_font::atlas_bytes();
    for scale in [1.0,1.25,1.5,2.0] {
        var canvas=lab_ui_render_scene::create(lab_ui_render_font::default_font(),scale as f32,lab_ui_render_font::default_fallback(),path); assert(canvas.fonts.len==1);
        let font=canvas.fonts[0].font; let loaded=lab_ui_render_font::source_bytes(); assert(loaded>=sources && lab_ui_render_font::atlas_bytes()==atlases+4194304);
        assert(!lab_ui_render_font::add_emoji(font,"missing-emoji.ttf")); // Failed addition leaves the family usable.
        let ordinary, width=lab_ui_render_font::shape(font,"123 office 日本語"); for glyph in ordinary { assert(!glyph.colored); }
        let text, tw=lab_ui_render_font::shape(font,"❤︎"); assert(text.len>0 && text[0].w>0.0); for glyph in text { assert(!glyph.colored); }
        let heart, hw=lab_ui_render_font::shape(font,"❤️"); assert(heart.len==1 && heart[0].colored && hw>0.0);
        for value in ["😀","👍🏽","👨‍👩‍👧‍👦","🇯🇵","1️⃣"] {
            let glyphs, width=lab_ui_render_font::shape(font,value); assert(glyphs.len>0 && width>0.0);
            assert(lab_ui_render_font::fit(font,str(value,"x"),0.0)==value.len);
            // Unsupported flag ligatures may remain multiple glyphs in system fonts.
            if argv.len>3 && argv[3]=="--joined" { assert(glyphs.len==1 && glyphs[0].colored); } // Pinned full-sequence reference font.
            for glyph in glyphs { if glyph.w>0.0 && glyph.h>0.0 && value!="🇯🇵" { assert(glyph.colored); } }
            let geometry, measured=lab_ui_render_font::geometry(font,value); assert(abs(measured-width)<0.001 && geometry.len==glyphs.len);
            var line=lab_ui_render_text_layout::create(font,value); assert(line.id!=0 && abs(lab_ui_render_text_layout::width(line)-width)<0.001);
            let retained=lab_ui_render_text_layout::window(line,0.0,width); assert(retained.len==glyphs.len);
            for i in retained.len { assert(retained[i].colored==glyphs[i].colored && retained[i].x==glyphs[i].x); }
            for i in 101 { let byte=lab_ui_render_text_layout::hit(line,width*i/100); assert(byte==0 || byte==value.len); }
            lab_ui_render_text_layout::close(line);
            let revision=lab_ui_render_font::revision(font); for i in 8 { let repeated,w=lab_ui_render_font::shape(font,value); assert(w==width && lab_ui_render_font::revision(font)==revision); }
        }
        let pixels=lab_ui_render_font::pixels(font); var chromatic=false;
        for i in pixels.len/4 { let j=i*4; assert(pixels[j]<=pixels[j+3] || pixels[j]==255); if pixels[j+3]>0 && pixels[j]!=pixels[j+1] { chromatic=true; } }
        assert(chromatic && lab_ui_render_font::atlas_bytes()==atlases+4194304);
        lab_ui_render_scene::begin(canvas,400.0,240.0);
        lab_ui_render_scene::text(canvas,0,18.0,18.0,"Text / 日本語 / 😀 👍🏽",float4 {1.0,0.2,0.2,1.0});
        lab_ui_render_scene::text(canvas,0,18.0,60.0,"Family 👨‍👩‍👧‍👦   Flag 🇯🇵",float4 {0.2,0.8,1.0,1.0});
        lab_ui_render_scene::text(canvas,0,18.0,102.0,"Text ❤︎  Emoji ❤️  Keycap 1️⃣",float4 {0.9,0.9,0.9,1.0});
        lab_ui_render_scene::text(canvas,0,18.0,144.0,"Opacity 😀 👍🏽",float4 {0.9,0.9,0.9,0.5});
        lab_ui_render_scene::render(canvas,float4 {0.04,0.05,0.065,1.0});
        assert(gfx::screenshot(str("emoji-",scale,".png")));
        let revision=lab_ui_render_font::revision(font); let renders=canvas.renders;
        for i in 8 { assert(gfx::frame()); assert(!lab_ui_render_scene::render(canvas,float4 {0.04,0.05,0.065,1.0})); }
        assert(canvas.renders==renders && lab_ui_render_font::revision(font)==revision);
        assert(lab_ui_render_font::source_bytes()==loaded); // Rasterization never copies source fonts.
        lab_ui_render_scene::destroy(canvas); assert(lab_ui_render_font::atlas_bytes()==atlases && lab_ui_render_font::source_bytes()==sources);
    }
    print("Color emoji: presentation, retained layout/carets, bounded shared memory and idle rendering passed");
}

extern "glab_test_text_boundary" fn native_boundary(cp: u32, reset: bool) -> bool;
fn native_grapheme_contract() {
    let argv=args(); if argv.len<2 { return; }
    var corpus: u8[>..]=[]; assert(read_file(argv[1],corpus)); var cases=0;
    for line in split(corpus,'\n') {
        let body=split(line,'#')[0]; var source: u8[>..]=[]; var expected: i64[>..]=[];
        for token in split(body,' ') { let item=trim(token); if item.len==0 || item=="×" { continue; }
            if item=="÷" { expected.push(source.len); } else { let cp,ok=parse_int(item,16); assert(ok); push_utf8(source,cp); }
        }
        if expected.len==0 { continue; } var state=lab_text_grapheme::State {}; var at=0;
        while at<source.len { let cp,end,ok=lab_text_utf8::decode(source,at); assert(ok); var boundary=false;
            for byte in expected { if byte==at { boundary=true; } }
            assert(native_boundary(cp as u32,at==0)==boundary && lab_text_grapheme::feed(state,cp)==boundary); at=end;
        } cases++;
    }
    assert(cases>700); print("Native font-run segmentation / Goose: official Unicode 17 cases ",cases);
}

fn scene_idle_contract(c: lab_ui_render_scene::Canvas&) {
    let sources=lab_ui_render_font::source_bytes(); let atlas=lab_ui_render_font::atlas_bytes();
    let borrowed=lab_ui_render_font::create_family(lab_ui_render_font::default_font(),lab_ui_render_font::default_fallback(),22.0);
    assert(borrowed.id!=0 && lab_ui_render_font::source_bytes()==sources && lab_ui_render_font::atlas_bytes()==atlas+4194304);
    lab_ui_render_font::destroy(borrowed); assert(lab_ui_render_font::source_bytes()==sources && lab_ui_render_font::atlas_bytes()==atlas);
    fn draw(color: float4, clip: lab_ui_geometry::Rect) {
        lab_ui_render_scene::begin(c,400.0,240.0); lab_ui_render_scene::push_clip(c,clip);
        lab_ui_render_scene::fill(c,lab_ui_geometry::rect(20.0,20.0,100.0,40.0),color);
        lab_ui_render_scene::text(c,0,24.0,24.0,"idle",float4 {1.0,1.0,1.0,1.0}); lab_ui_render_scene::pop_clip(c);
    }
    let background=float4 {0.04,0.05,0.065,1.0}; let clip=lab_ui_geometry::rect(0.0,0.0,400.0,240.0); var color=float4 {0.2,0.3,0.4,1.0};
    assert(gfx::frame()); draw(color,clip); assert(lab_ui_render_scene::render(c,background)); assert(gfx::frame());
    let submits=gfx::submit_count(); let presents=gfx::present_count(); let rendered=c.renders;
    for i in 120 { draw(color,clip); assert(!lab_ui_render_scene::render(c,background)); assert(gfx::frame()); }
    assert(c.renders==rendered && gfx::submit_count()==submits && gfx::present_count()==presents);
    color.x+=0.000001; draw(color,clip); assert(lab_ui_render_scene::render(c,background)); assert(gfx::frame()); assert(gfx::submit_count()>submits);
    draw(color,lab_ui_geometry::rect(1.0,0.0,399.0,240.0)); assert(lab_ui_render_scene::render(c,background)); assert(gfx::frame());
    var other=lab_ui_render_scene::create(lab_ui_render_font::default_font()); lab_ui_render_scene::begin(other,400.0,240.0);
    lab_ui_render_scene::fill(other,clip,color); assert(lab_ui_render_scene::render(other,background)); assert(gfx::frame());
    draw(color,lab_ui_geometry::rect(1.0,0.0,399.0,240.0)); assert(lab_ui_render_scene::render(c,background)); assert(gfx::frame());
    lab_ui_render_scene::destroy(other);
    assert(gfx::begin_screen(background)); gfx::end_pass(); assert(gfx::frame());
    draw(color,lab_ui_geometry::rect(1.0,0.0,399.0,240.0)); assert(lab_ui_render_scene::render(c,background)); assert(gfx::frame());
    draw(color,lab_ui_geometry::rect(1.0,0.0,399.0,240.0)); assert(!lab_ui_render_scene::render(c,background));
    assert(lab_ui_render_scene::live_bytes()>0);
    print("Exact scene comparison: 120 idle frames, zero GPU submissions/presentations; color/clip invalidation and shared font bytes passed");
}
