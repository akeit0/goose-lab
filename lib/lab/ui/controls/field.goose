// Small single-line editor. Extended grapheme boundaries; LTR caret geometry.
namespace lab_ui_controls_field;
import std;
import math;
import vec;
import gfx;
import lab.ui.input.shortcuts;
import lab.text.strings;
import lab.text.grapheme;
import lab.ui.render.font;
import lab.ui.geometry;
import lab.ui.render.scene;
import lab.ui.input.interaction;
import lab.ui.controls.components;
import lab.ui.input.composition;
struct State {
    text: u8[..512] = [], cursor: i64 = 0, anchor: i64 = 0,
    scroll: f32 = 0.0, dragging: bool = false, rejected: bool = false,
    composition: lab_ui_input_composition::State = lab_ui_input_composition::State {},
}
struct Submission { text: u8[..512] = [] }
struct Result { changed: bool = false, submitted: bool = false, submissions: Submission[..16] = [] }
struct Stop { byte: i64, x: f32, caret: bool = true }
fn set(s: State&, value: const u8[:]) {
    assert(value.len <= 512 && lab_text_strings::single_line(value));
    lab_ui_input_composition::clear(s.composition);
    s.text.resize(0); s.text.append(value); s.cursor = s.text.len; s.anchor = s.cursor; s.scroll = 0.0; s.dragging = false;
}
fn first(s: const State&) -> i64 { min(s.cursor, s.anchor) }
fn last(s: const State&) -> i64 { max(s.cursor, s.anchor) }
fn replace(s: State&, value: const u8[:], limit: i64) -> bool {
    let begin = first(s); let end = last(s);
    if s.text.len - (end - begin) + value.len > limit || !lab_text_strings::single_line(value) { s.rejected = true; return false; }
    var joined: u8[..512] = []; joined.append(s.text[..begin]); joined.append(value); joined.append(s.text[end..]);
    if joined == s.text { return false; }
    s.text = joined; s.cursor = begin + value.len; if !lab_text_grapheme::boundary(s.text,s.cursor) { s.cursor=lab_text_grapheme::next(s.text,s.cursor); } s.anchor = s.cursor; true
}
// Keep shaping of the whole string independent of cursor/selection. Within a
// ligature cluster, scalar stops interpolate its advance (no GDEF carets yet).
fn stops(font: lab_ui_render_font::Font, value: const u8[:]) -> Stop[>..] {
    var out: Stop[>..] = []; out.push(Stop { 0, 0.0 });
    let glyphs, width = lab_ui_render_font::geometry(font, value);
    var i = 0;
    while i < glyphs.len {
        let byte = glyphs[i].cluster as i64; let start = glyphs[i].pen; var end = start;
        var j = i;
        while j < glyphs.len && glyphs[j].cluster == glyphs[i].cluster { end = glyphs[j].pen + glyphs[j].advance; j++; }
        let next = if j < glyphs.len { glyphs[j].cluster as i64 } else { value.len };
        if next > byte {
            var count = 0; var at = byte; while at < next { at = lab_text_strings::next(value, at); count++; }
            at = byte; var k = 0;
            while at < next { at = lab_text_strings::next(value, at); k++; out.push(Stop { at, start + (end - start) * k / count }); }
        }
        i = j;
    }
    if out[out.len - 1].byte != value.len { out.push(Stop { value.len, width }); }
    let boundaries,ok=lab_text_grapheme::offsets(value); assert(ok); var boundary=0;
    for i in out.len { while boundary<boundaries.len && boundaries[boundary]<out[i].byte { boundary++; } out[i].caret=boundary<boundaries.len && boundaries[boundary]==out[i].byte; }
    out
}
fn position(points: const Stop[:], byte: i64) -> f32 { for point in points { if point.byte == byte { return point.x; } } 0.0 }
fn hit(points: const Stop[:], x: f32) -> i64 {
    var byte: i64 = 0; var distance: f32 = 1000000.0;
    for point in points { if !point.caret { continue; } let d = abs(point.x - x); if d < distance { distance = d; byte = point.byte; } } byte
}
fn update(s: State&, input: const lab_ui_input_interaction::State&, id: u64, bounds: lab_ui_geometry::Rect,
    font: lab_ui_render_font::Font, scale: f32 = 1.0, limit: i64 = 240, clear_on_submit: bool = false) -> Result {
    assert(limit >= 0 && limit <= 512 && scale > 0.0 && input.events.len == input.targets.len);
    var result = Result {}; s.rejected = false;
    for i in input.events.len {
        let e = input.events[i]; if input.targets[i] != id { continue; }
        if e.kind == gfx::EVENT_TEXT_EDITING {
            s.rejected=!lab_ui_input_composition::update(s.composition,e,first(s),last(s),0,512); continue;
        }
        if e.kind == gfx::EVENT_TEXT_COMMIT {
            let bytes,ok=lab_ui_input_composition::payload(e.text,512);
            if s.composition.pending { s.anchor=s.composition.first; s.cursor=s.composition.last; }
            lab_ui_input_composition::clear(s.composition);
            if ok { result.changed=replace(s,bytes,limit)||result.changed; } else { s.rejected=true; }
            continue;
        }
        if s.composition.pending && !lab_ui_input_composition::active(s.composition) && e.kind==gfx::EVENT_KEY && e.down { lab_ui_input_composition::clear(s.composition); }
        if e.kind == gfx::EVENT_KEY && e.down && lab_ui_input_composition::active(s.composition) {
            if e.scancode==gfx::scancode("Escape") { lab_ui_input_composition::clear(s.composition); gfx::clear_composition(); }
            continue;
        }
        if e.kind==gfx::EVENT_MOUSE_BUTTON && e.down && s.composition.pending { lab_ui_input_composition::clear(s.composition); gfx::clear_composition(); }
        if e.kind == gfx::EVENT_MOUSE_BUTTON && e.button == gfx::MOUSE_LEFT {
            if e.down {
                let points = stops(font, s.text); s.cursor = hit(points, e.x / scale - bounds.x - 12.0 + s.scroll);
                if (e.mods & gfx::MOD_SHIFT) == 0 { s.anchor = s.cursor; } s.dragging = true;
            } else { s.dragging = false; }
        }
        if e.kind == gfx::EVENT_MOUSE_MOTION && s.dragging {
            let points = stops(font, s.text); s.cursor = hit(points, e.x / scale - bounds.x - 12.0 + s.scroll);
        }
        if e.kind == gfx::EVENT_TEXT && e.codepoint >= 32 && e.codepoint != 127 && e.codepoint <= 0x10FFFF && !(e.codepoint >= 0xD800 && e.codepoint <= 0xDFFF) {
            var bytes: u8[>..] = []; push_utf8(bytes, e.codepoint); result.changed = replace(s, bytes, limit) || result.changed;
        }
        if e.kind != gfx::EVENT_KEY || !e.down { continue; }
        let shift = (e.mods & gfx::MOD_SHIFT) != 0; let ctrl = lab_ui_input_shortcuts::command(e.mods);
        if ctrl && e.scancode == gfx::scancode("A") { s.anchor = 0; s.cursor = s.text.len; }
        else if ctrl && (e.scancode == gfx::scancode("C") || e.scancode == gfx::scancode("X")) {
            if first(s) != last(s) { gfx::set_clipboard(s.text[first(s)..last(s)]); }
            if e.scancode == gfx::scancode("X") { result.changed = replace(s, "", limit) || result.changed; }
        } else if ctrl && e.scancode == gfx::scancode("V") {
            var bytes: u8[512] = [0; 512]; let count = gfx::clipboard_into(bytes);
            if count > 512 || count < 0 { s.rejected = true; }
            else { result.changed = replace(s, bytes[..count], limit) || result.changed; }
        } else if e.scancode == gfx::scancode("Backspace") {
            if first(s) == last(s) { s.anchor = lab_text_grapheme::previous(s.text, s.cursor); }
            result.changed = replace(s, "", limit) || result.changed;
        } else if e.scancode == gfx::scancode("Delete") {
            if first(s) == last(s) { s.anchor = lab_text_grapheme::next(s.text, s.cursor); }
            result.changed = replace(s, "", limit) || result.changed;
        } else if e.scancode == gfx::scancode("Left") || e.scancode == gfx::scancode("Right") {
            let left = e.scancode == gfx::scancode("Left");
            s.cursor = if ctrl && lab_ui_input_shortcuts::macos() { if left { 0 } else { s.text.len } } else if !shift && first(s) != last(s) { if left { first(s) } else { last(s) } }
                       else { if left { lab_text_grapheme::previous(s.text, s.cursor) } else { lab_text_grapheme::next(s.text, s.cursor) } };
            if !shift { s.anchor = s.cursor; }
        } else if e.scancode == gfx::scancode("Home") || e.scancode == gfx::scancode("End") {
            s.cursor = if e.scancode == gfx::scancode("Home") { 0 } else { s.text.len }; if !shift { s.anchor = s.cursor; }
        } else if e.scancode == gfx::scancode("Return") && !e.repeat {
            result.submitted = true; result.submissions.push(Submission { text: s.text });
            if clear_on_submit { set(s, ""); result.changed = true; }
        }
    }
    if input.captured != id { s.dragging = false; }
    if input.focused != id { lab_ui_input_composition::clear(s.composition); }
    result
}
fn paint(c: lab_ui_render_scene::Canvas&, s: State&, input: const lab_ui_input_interaction::State&, id: u64,
    bounds: lab_ui_geometry::Rect, placeholder: const u8[:], enabled: bool = true) {
    let theme = lab_ui_controls_components::Theme {}; let focused = input.focused == id && enabled;
    if !focused { lab_ui_input_composition::clear(s.composition); }
    lab_ui_render_scene::border(c, bounds, theme.surface, if focused { theme.accent } else { theme.border }, 8.0);
    let inside = lab_ui_geometry::rect(bounds.x + 12.0, bounds.y + 4.0, max(0.0, bounds.w - 24.0), bounds.h - 8.0);
    let font = c.fonts[0].font; let height = lab_ui_render_font::metrics(font).height; let y = bounds.y + (bounds.h - height) / 2.0;
    let composing=lab_ui_input_composition::active(s.composition); var shown: u8[>..]=[];
    if composing { shown.append(s.text[..s.composition.first]); shown.append(s.composition.text); shown.append(s.text[s.composition.last..]); } else { shown.append(s.text); }
    let points = stops(font, shown); let caret_byte=if composing { s.composition.first+s.composition.cursor } else { s.cursor }; let caret = position(points, caret_byte);
    if focused {
        if caret - s.scroll > inside.w - 2.0 { s.scroll = max(0.0, caret - inside.w + 2.0); }
        if caret < s.scroll { s.scroll = caret; }
    }
    s.scroll = clamp(s.scroll, 0.0, max(0.0, lab_ui_render_font::width(font, shown) - inside.w + 2.0));
    lab_ui_render_scene::push_clip(c, inside);
    if focused && (composing || first(s) != last(s)) {
        let start = position(points, if composing { s.composition.first+s.composition.cursor } else { first(s) }); let end = position(points, if composing { s.composition.first+s.composition.end } else { last(s) });
        lab_ui_render_scene::fill(c, lab_ui_geometry::rect(inside.x + start - s.scroll, y, end - start, height), float4 { 0.25, 0.23, 0.48, 1.0 });
    }
    lab_ui_render_scene::text(c, 0, inside.x - s.scroll, y, if shown.len == 0 { placeholder } else { shown[..] }, if shown.len == 0 || !enabled { theme.muted } else { theme.text });
    if composing { let start=position(points,s.composition.first); let end=position(points,s.composition.first+s.composition.text.len);
        lab_ui_render_scene::fill(c,lab_ui_geometry::rect(inside.x+start-s.scroll,y+height-1.0/c.scale,end-start,1.0/c.scale),theme.accent); }
    if focused && (composing || first(s) == last(s)) {
        let x: f32 = round((inside.x + caret - s.scroll) * c.scale) / c.scale;
        lab_ui_render_scene::fill(c, lab_ui_geometry::rect(x, round(y * c.scale) / c.scale, 1.0 / c.scale, height), theme.text);
    }
    if focused { let x=clamp(inside.x+caret-s.scroll,inside.x,inside.x+inside.w); gfx::text_input_area(x*c.scale,y*c.scale,1.0,height*c.scale,0.0); }
    lab_ui_render_scene::pop_clip(c);
}
