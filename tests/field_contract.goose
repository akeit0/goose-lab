import std;
import math;
import vec;
import gfx;
import lab.ui.input.shortcuts;
import lab.ui.render.font;
import lab.ui.geometry;
import lab.ui.render.scene;
import lab.ui.controls.field;
import lab.ui.input.composition;
import lab.ui.input.interaction;
import lab.ui.controls.components;
import lab.ui.views.text;
import lab.ui.view;
enum TextAction { Input }
fn text_view_contract(c: lab_ui_render_scene::Canvas&) {
    let font = c.fonts[0].font; let source: const u8[:] = "office\tcafé 日本語\r\n\nlast\n";
    let revision = lab_ui_render_font::revision(font); let d = lab_ui_views_text::build(source, font);
    assert(d.code == 0 && d.index.rows.len == 3 && lab_ui_render_font::revision(font) == revision);
    let l = lab_ui_views_text::line(d, source, 0, font);
    assert(l.text == "office    café 日本語" && lab_ui_render_font::revision(font) == revision);
    assert(l.points[7].byte == 7 && l.points[7].x > l.points[6].x);
    for p in l.points { assert(p.byte <= d.index.rows[0].end); }
    let invalid = lab_ui_views_text::build([0xFF], font); assert(invalid.code == lab_ui_views_text::ENCODING);
    var v = lab_ui_view::View<TextAction> {}; var s = lab_ui_views_text::State {};
    // A shorter replacement can cut through an old UTF-8 selection endpoint.
    s.cursor = 3; s.anchor = 100; s.horizontal.offset = 45.0; s.query = "語"; s.dragging = true; s.bar_dragging = true;
    lab_ui_views_text::rebase(s, "A日本語");
    assert(s.cursor == 1 && s.anchor == 10 && s.horizontal.offset == 45.0 && s.matches.len == 1 && s.query == "語");
    assert(!s.dragging && !s.bar_dragging); s = lab_ui_views_text::State {};
    let cfg = lab_ui_views_text::Config<TextAction> { id: 1, scroll_id: 2, bar_id: 3, action: TextAction.Input };
    let area = lab_ui_geometry::rect(12.37, 15.19, 300.0, 150.0);
    fn send(e: gfx::Event) { lab_ui_views_text::input(v, c, s, d, source, area, cfg, lab_ui_view::Event<TextAction> { kind: lab_ui_view::INPUT, action: TextAction.Input, source: 1, input: e }); }
    send(key("End")); assert(s.cursor == d.index.rows[0].end);
    send(key("Right")); assert(s.cursor == d.index.rows[1].start); send(key("Left")); assert(s.cursor == d.index.rows[0].end);
    s.anchor = 0; send(key("Right", gfx::MOD_SHIFT)); send(key("C", lab_ui_input_shortcuts::primary()));
    assert(gfx::clipboard() == source[..d.index.rows[1].start]); // Includes the original tab and CRLF.
    let before = s.cursor; send(typed('x')); send(key("Backspace")); assert(s.cursor == before);
    send(key("A", lab_ui_input_shortcuts::primary())); send(key("C", lab_ui_input_shortcuts::primary())); assert(gfx::clipboard() == source);
    send(key("Home", lab_ui_input_shortcuts::primary())); send(key("Right")); assert(s.cursor == 1);
    send(key("Down")); assert(s.cursor == d.index.rows[1].start);
    send(key("Down")); let target_line = lab_ui_views_text::line(d, source, 2, font);
    assert(s.preferred > 0.0 && s.cursor == d.index.rows[2].start + lab_ui_controls_field::hit(target_line.points, s.preferred)); // Preferred x survives an empty row.
    s.query = "aa"; lab_ui_views_text::find(s, "aaaa"); assert(s.matches.len == 3);
    lab_ui_views_text::choose_match(s, -1); assert(s.active == 2); lab_ui_views_text::choose_match(s, 1); assert(s.active == 0);
    s.query = "CAFÉ"; lab_ui_views_text::find(s, source); assert(s.matches.len == 0); // Non-ASCII stays exact.
    s.query = "CAFé"; lab_ui_views_text::find(s, source); assert(s.matches.len == 1);
    var repeated: u8[>..] = []; for i in 4097 { repeated.push('a'); }
    s.query = "a"; lab_ui_views_text::find(s, repeated); assert(s.limited && s.matches.len == 0);
    // Selection never reshapes or shifts glyphs; caret remains one physical pixel.
    lab_ui_views_text::reset(s, source); s.find_open = false;
    fn color(row: i64, r: lab_ui_geometry::Rect) -> float4 { lab_ui_controls_components::Theme {}.text }
    let theme = lab_ui_controls_components::Theme {};
    lab_ui_render_scene::begin(c, 500.0, 240.0); lab_ui_views_text::paint(c, s, d, source, area, cfg, 0.0, true, color);
    var positions: float2[>..] = []; var caret = false;
    for i in c.quads.len {
        let vertex = lab_ui_render_scene::vertex(c,i*6); if vertex.params.w < 0.5 && vertex.color == theme.text {
            assert(abs(vertex.params.x * c.scale - 1.0) < 0.001); caret = true;
        }
    }
    assert(caret); for vertex_index in c.quads.len * 6 { let vertex=lab_ui_render_scene::vertex(c,vertex_index); if vertex.params.w > 0.5 { positions.push(vertex.pos); } }
    s.anchor = 0; s.cursor = d.index.rows[0].end;
    lab_ui_render_scene::begin(c, 500.0, 240.0); lab_ui_views_text::paint(c, s, d, source, area, cfg, 0.0, true, color);
    var index = 0; for vertex_index in c.quads.len * 6 { let vertex=lab_ui_render_scene::vertex(c,vertex_index); if vertex.params.w > 0.5 { assert(vertex.pos == positions[index]); index++; } } assert(index == positions.len);
    // Window glyphs retain their full-line cluster/position, including ligatures.
    let full, width = lab_ui_render_font::shape(font, l.text); let window, window_width = lab_ui_render_font::window(font, l.text, 25.0, 90.0);
    assert(width == window_width && window.len > 0 && window.len < full.len);
    for glyph in window {
        var found = false; for original in full { if glyph.cluster == original.cluster && glyph.x == original.x && glyph.y == original.y && glyph.advance == original.advance { found = true; } } assert(found);
    }
}
fn key(name: const u8[:], mods: i32 = 0) -> gfx::Event {
    var e = default<gfx::Event>(); e.kind = gfx::EVENT_KEY; e.scancode = gfx::scancode(name) as i32; e.mods = mods; e.down = true; e
}
fn typed(cp: u32) -> gfx::Event { var e = default<gfx::Event>(); e.kind = gfx::EVENT_TEXT; e.codepoint = cp; e }
fn mouse(x: f32, down: bool) -> gfx::Event {
    var e = default<gfx::Event>(); e.kind = gfx::EVENT_MOUSE_BUTTON; e.button = gfx::MOUSE_LEFT; e.x = x; e.y = 20.0; e.down = down; e
}
fn route(s: lab_ui_input_interaction::State&, events: const gfx::Event[:]) {
    lab_ui_input_interaction::begin(s);
    lab_ui_input_interaction::register(s, 1, lab_ui_geometry::rect(0.0, 0.0, 240.0, 44.0), true, true, false);
    lab_ui_input_interaction::register(s, 2, lab_ui_geometry::rect(250.0, 0.0, 240.0, 44.0), true, true, false);
    lab_ui_input_interaction::resolve(s, events, float2 { 0.0, 0.0 }, true);
}
fn main() {
    assert(gfx::open_headless(500, 240)); var c = lab_ui_render_scene::create(lab_ui_render_font::default_font());
    let font = c.fonts[0].font; let a = lab_ui_geometry::rect(0.0, 0.0, 240.0, 44.0); let b = lab_ui_geometry::rect(250.0, 0.0, 240.0, 44.0);
    var input = lab_ui_input_interaction::State {}; var first = lab_ui_controls_field::State {}; var second = lab_ui_controls_field::State {};
    route(input, [mouse(20.0, true), mouse(20.0, false), typed('c'), typed('a'), typed('f'), mouse(270.0, true), mouse(270.0, false), typed(0xE9)]);
    lab_ui_controls_field::update(first, input, 1, a, font); lab_ui_controls_field::update(second, input, 2, b, font);
    assert(first.text == "caf" && second.text == "é" && input.focused == 2);
    route(input, [key("Backspace")]); lab_ui_controls_field::update(second, input, 2, b, font); assert(second.text.len == 0);
    lab_ui_controls_field::set(second, "café"); route(input, [key("Home"), key("Right", gfx::MOD_SHIFT), typed('C')]);
    lab_ui_controls_field::update(second, input, 2, b, font); assert(second.text == "Café");
    assert(gfx::set_clipboard("Goose café")); route(input, [key("A", lab_ui_input_shortcuts::primary()), key("V", lab_ui_input_shortcuts::primary())]);
    lab_ui_controls_field::update(second, input, 2, b, font); assert(second.text == "Goose café");
    let before = second.text; route(input, [typed(0x1F600)]); lab_ui_controls_field::update(second, input, 2, b, font, 1.0, second.text.len + 3);
    assert(second.rejected && second.text == before);
    assert(gfx::set_clipboard("bad\nline")); route(input, [key("V", lab_ui_input_shortcuts::primary())]);
    lab_ui_controls_field::update(second, input, 2, b, font); assert(second.rejected && second.text == before);
    route(input, [key("Return")]); let result = lab_ui_controls_field::update(second, input, 2, b, font); assert(result.submitted && !lab_ui_input_interaction::clicked(input, 2));
    lab_ui_controls_field::set(second, ""); route(input, [typed('A'), key("Return"), typed('B'), key("Return"), typed('C')]);
    let queued = lab_ui_controls_field::update(second, input, 2, b, font, 1.0, 240, true);
    assert(queued.submissions.len == 2 && queued.submissions[0].text == "A" && queued.submissions[1].text == "B" && second.text == "C");
    lab_ui_controls_field::set(second,"́"); route(input,[key("Home"),typed('e')]); lab_ui_controls_field::update(second,input,2,b,font); assert(second.text=="é" && second.cursor==3);
    lab_ui_controls_field::set(second,"é👍🏽👨‍👩‍👧‍👦🇯🇵");
    route(input,[key("Left")]); lab_ui_controls_field::update(second,input,2,b,font); assert(second.cursor==36);
    route(input,[key("Left",gfx::MOD_SHIFT)]); lab_ui_controls_field::update(second,input,2,b,font); assert(second.cursor==11 && second.anchor==36);
    route(input,[key("Backspace")]); lab_ui_controls_field::update(second,input,2,b,font); assert(second.text=="é👍🏽🇯🇵");
    route(input,[key("Backspace")]); lab_ui_controls_field::update(second,input,2,b,font); assert(second.text=="é🇯🇵");
    route(input,[key("Home"),key("Delete")]); lab_ui_controls_field::update(second,input,2,b,font); assert(second.text=="🇯🇵");
    // Native frame payloads retain event order without embedding strings in Event.
    gfx::text_transactions(true); lab_ui_controls_field::set(second,"abc"); second.anchor=1; second.cursor=2; input.focused=2;
    assert(gfx::inject_editing("にほん",1,1) && gfx::frame()); let preedit=gfx::events(); assert(preedit.len==1);
    route(input,preedit); lab_ui_controls_field::update(second,input,2,b,font);
    assert(second.text=="abc" && second.cursor==2 && second.composition.text=="にほん" && second.composition.cursor==3 && second.composition.end==6);
    route(input,[key("Return"),key("Tab"),key("V",gfx::MOD_CTRL)]); let held=lab_ui_controls_field::update(second,input,2,b,font);
    assert(!held.submitted && second.text=="abc" && input.focused==2);
    assert(gfx::inject_editing("日本",0,2) && gfx::inject_text("日本") && gfx::frame()); let committed=gfx::events();
    assert(committed.len==2 && committed[0].kind==gfx::EVENT_TEXT_EDITING && committed[1].kind==gfx::EVENT_TEXT_COMMIT);
    let old_token=committed[0].text; route(input,committed); lab_ui_controls_field::update(second,input,2,b,font);
    assert(second.text=="a日本c" && !lab_ui_input_composition::active(second.composition));
    assert(gfx::frame()); var empty: u8[0]=[]; assert(gfx::text_event_into(old_token,empty)==-1);
    assert(gfx::inject_editing("取消",-1,-1) && gfx::frame()); route(input,gfx::events()); lab_ui_controls_field::update(second,input,2,b,font);
    assert(second.composition.cursor==6 && second.composition.end==6); route(input,[key("Escape")]); lab_ui_controls_field::update(second,input,2,b,font);
    assert(second.text=="a日本c" && !second.composition.pending);
    assert(gfx::inject_text("too large") && gfx::frame()); route(input,gfx::events()); lab_ui_controls_field::update(second,input,2,b,font,1.0,second.text.len);
    assert(second.rejected && second.text=="a日本c");
    assert(gfx::inject_editing("\xFF",0,1) && gfx::frame()); route(input,gfx::events()); lab_ui_controls_field::update(second,input,2,b,font);
    assert(second.rejected && !second.composition.pending && second.text=="a日本c");
    var oversized: u8[>..]=[]; oversized.resize(65533,'a');
    assert(gfx::inject_text(oversized) && gfx::frame()); let overflow=gfx::events(); assert(overflow.len==1 && overflow[0].text==0);
    route(input,overflow); lab_ui_controls_field::update(second,input,2,b,font); assert(second.rejected && second.text=="a日本c");
    assert(gfx::inject_editing("仮",0,1) && gfx::inject_editing("",0,0) && gfx::frame()); route(input,gfx::events()); lab_ui_controls_field::update(second,input,2,b,font);
    assert(second.composition.pending && !lab_ui_input_composition::active(second.composition)); route(input,[mouse(270.0,true),mouse(270.0,false)]); lab_ui_controls_field::update(second,input,2,b,font);
    assert(!second.composition.pending && second.text=="a日本c");
    for scale in [1.0, 1.25, 1.5, 2.0] {
        var scaled = lab_ui_render_scene::create(lab_ui_render_font::default_font(), scale as f32); var field = lab_ui_controls_field::State {}; lab_ui_controls_field::set(field, "office café 日本語 が");
        let points = lab_ui_controls_field::stops(scaled.fonts[0].font, field.text);
        assert(abs(points[points.len - 1].x - lab_ui_render_font::width(scaled.fonts[0].font, field.text)) < 0.001);
        for point in points { if point.caret { assert(lab_ui_controls_field::hit(points, point.x) == point.byte); } else { assert(lab_ui_controls_field::hit(points, point.x) != point.byte); } }
        let rect = lab_ui_geometry::rect(12.37, 15.19, 240.0, 44.0); input.focused = 1;
        field.cursor = 0; field.anchor = 0; lab_ui_render_scene::begin(scaled, 400.0, 240.0);
        lab_ui_controls_field::paint(scaled, field, input, 1, rect, "");
        var positions: float2[>..] = []; var caret_found = false; let theme = lab_ui_controls_components::Theme {};
        for i in scaled.quads.len {
            let vertex = lab_ui_render_scene::vertex(scaled,i*6);
            if vertex.params.w < 0.5 && vertex.color == theme.text {
                assert(abs(vertex.params.x * scaled.scale - 1.0) < 0.001); caret_found = true;
            }
        }
        assert(caret_found);
        for vertex_index in scaled.quads.len * 6 { let vertex=lab_ui_render_scene::vertex(scaled,vertex_index); if vertex.params.w > 0.5 { positions.push(vertex.pos); } }
        field.cursor = field.text.len; field.anchor = 0; lab_ui_render_scene::begin(scaled, 400.0, 240.0); lab_ui_controls_field::paint(scaled, field, input, 1, rect, "");
        var index = 0;
        for vertex_index in scaled.quads.len * 6 { let vertex=lab_ui_render_scene::vertex(scaled,vertex_index); if vertex.params.w > 0.5 { assert(vertex.pos == positions[index]); index++; } }
        assert(index == positions.len);
        assert(gfx::inject_editing("日本語",1,1) && gfx::frame()); input.focused=1;
        input.events=gfx::events(); input.targets.resize(0); input.targets.resize(input.events.len,1);
        lab_ui_controls_field::update(field,input,1,rect,scaled.fonts[0].font,scaled.scale);
        assert(field.text=="office café 日本語 が" && field.composition.cursor==3 && field.composition.end==6);
        lab_ui_render_scene::begin(scaled,400.0,240.0); lab_ui_controls_field::paint(scaled,field,input,1,rect,""); lab_ui_render_scene::render(scaled,theme.background);
        let submits=gfx::submit_count(); for i in 4 { assert(gfx::frame()); lab_ui_render_scene::begin(scaled,400.0,240.0); lab_ui_controls_field::paint(scaled,field,input,1,rect,""); lab_ui_render_scene::render(scaled,theme.background); }
        assert(scaled.skipped>=4 && gfx::submit_count()<=submits+1);
        text_view_contract(scaled); emoji_field_contract(scaled); lab_ui_render_scene::destroy(scaled);
    }
    lab_ui_render_scene::destroy(c); gfx::close(); print("Field UTF-8, routed focus, clipboard, submit and stable selection contract passed");
}

fn emoji_field_contract(c: lab_ui_render_scene::Canvas&) {
    let font=c.fonts[0].font; var input=lab_ui_input_interaction::State {}; var field=lab_ui_controls_field::State {};
    let value="A👍🏽👨‍👩‍👧‍👦🇯🇵B"; let rect=lab_ui_geometry::rect(12.37,15.19,240.0,44.0);
    lab_ui_controls_field::set(field,value); input.focused=2;
    route(input,[key("Left"),key("Left",gfx::MOD_SHIFT)]); lab_ui_controls_field::update(field,input,2,rect,font,c.scale);
    assert(field.cursor==value.len-9 && field.anchor==value.len-1);
    assert(gfx::set_clipboard("😀")); route(input,[key("V",lab_ui_input_shortcuts::primary())]); lab_ui_controls_field::update(field,input,2,rect,font,c.scale);
    assert(field.text=="A👍🏽👨‍👩‍👧‍👦😀B"); route(input,[key("Backspace")]); lab_ui_controls_field::update(field,input,2,rect,font,c.scale);
    assert(field.text=="A👍🏽👨‍👩‍👧‍👦B"); route(input,[key("Backspace")]); lab_ui_controls_field::update(field,input,2,rect,font,c.scale);
    assert(field.text=="A👍🏽B");
    lab_ui_controls_field::set(field,"x👍🏽y"); field.cursor=9; field.anchor=1;
    assert(gfx::inject_editing("👨‍👩‍👧‍👦",7,0) && gfx::frame()); route(input,gfx::events()); lab_ui_controls_field::update(field,input,2,rect,font,c.scale);
    assert(field.text=="x👍🏽y" && field.composition.cursor==25);
    lab_ui_render_scene::begin(c,400.0,240.0); lab_ui_controls_field::paint(c,field,input,2,rect,""); lab_ui_render_scene::render(c,float4 {0.04,0.05,0.065,1.0});
    assert(gfx::inject_editing("",0,0) && gfx::inject_text("🇯🇵") && gfx::frame()); route(input,gfx::events()); lab_ui_controls_field::update(field,input,2,rect,font,c.scale);
    assert(field.text=="x🇯🇵y" && field.cursor==9 && !field.composition.pending);
    lab_ui_controls_field::set(field,"A👍🏽👨‍👩‍👧‍👦🇯🇵B"); field.cursor=0; field.anchor=0;
    lab_ui_render_scene::begin(c,400.0,240.0); lab_ui_controls_field::paint(c,field,input,2,rect,""); let before=c.quads;
    field.cursor=field.text.len; field.anchor=0;
    lab_ui_render_scene::begin(c,400.0,240.0); lab_ui_controls_field::paint(c,field,input,2,rect,"");
    var index=0; for q in c.quads { if q.params.w>0.5 {
        while index<before.len && before[index].params.w<=0.5 { index++; } assert(index<before.len && q.origin==before[index].origin && q.uv==before[index].uv); index++;
    } }
    lab_ui_render_scene::render(c,float4 {0.04,0.05,0.065,1.0}); assert(gfx::screenshot(str("emoji-field-",c.scale,".png")));
}
