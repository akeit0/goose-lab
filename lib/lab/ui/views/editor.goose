// Editable UTF-8 viewport over lab.document.model; source bytes stay in the piece tree.
namespace lab_ui_views_editor;
import std;
import math;
import vec;
import gfx;
import lab.document.model;
import lab.text.utf8;
import lab.collections.state_bank;
import lab.document.piece_tree;
import lab.ui.views.text;
import lab.ui.controls.field;
import lab.ui.render.font;
import lab.ui.render.text_layout;
import lab.ui.render.scene;
import lab.ui.view;
import lab.ui.layout.scroll;
import lab.ui.geometry;
import lab.ui.controls.components;
import lab.ui.input.composition;
let LAYOUT_LIMIT: i32 = 103;
struct Cached { row: i64, start: i64, end: i64, layout: lab_ui_render_text_layout::Layout }
struct State { preferred: f32 = -1.0, horizontal: lab_ui_layout_scroll::State = lab_ui_layout_scroll::State {}, width: f32 = 0.0,
    dragging: bool = false, bar_dragging: bool = false, grab: f32 = 0.0, code: i32 = 0, copy_failed: bool = false,
    revision: u64 = 0, font: u64 = 0, cache: Cached[..128] = [],
    preview: lab_ui_render_text_layout::Layout = lab_ui_render_text_layout::Layout {}, preview_serial: u64 = 0, composition: lab_ui_input_composition::State = lab_ui_input_composition::State {} }
struct Line { start: i64, end: i64, layout: lab_ui_render_text_layout::Layout }
fn clear(s: State&) { for i in s.cache.len { lab_ui_render_text_layout::close(s.cache[i].layout); } s.cache.resize(0); s.revision=0; s.font=0; lab_ui_render_text_layout::close(s.preview); s.preview_serial=0; }
fn cancel(s: State&) { lab_ui_input_composition::clear(s.composition); lab_ui_render_text_layout::close(s.preview); s.preview_serial=0; }
fn preview(s: State&, d: const lab_document_model::Document&, font: lab_ui_render_font::Font) -> lab_ui_render_text_layout::Layout {
    if s.preview_serial==s.composition.serial { return s.preview; }
    lab_ui_render_text_layout::close(s.preview); s.preview_serial=s.composition.serial;
    let first=lab_document_piece_tree::line_span(d.tree,lab_document_piece_tree::line_at(d.tree,s.composition.first));
    let last=lab_document_piece_tree::line_span(d.tree,lab_document_piece_tree::line_at(d.tree,s.composition.last));
    if s.composition.first-first.start+s.composition.text.len+last.end-s.composition.last>1048576 { s.code=LAYOUT_LIMIT; return s.preview; }
    var shown=lab_document_model::read(d,first.start,s.composition.first); shown.append(s.composition.text);
    let tail=lab_document_model::read(d,s.composition.last,last.end); shown.append(tail); s.preview=lab_ui_render_text_layout::create(font,shown);
    if s.preview.id==0 { s.code=LAYOUT_LIMIT; } s.preview
}
fn line(s: State&, d: const lab_document_model::Document&, row: i64, font: lab_ui_render_font::Font) -> Line {
    if s.revision != d.revision || s.font != font.id { clear(s); s.revision=d.revision; s.font=font.id; }
    for entry in s.cache { if entry.row == row { return Line { entry.start, entry.end, entry.layout }; } }
    if s.cache.len == 128 { lab_ui_render_text_layout::close(s.cache[0].layout); for i in 127 { s.cache[i]=s.cache[i+1]; } s.cache.resize(127); }
    let span = lab_document_piece_tree::line_span(d.tree, row); let raw = lab_document_model::read(d, span.start, span.end);
    let layout = lab_ui_render_text_layout::create(font, raw); if layout.id == 0 { s.code=LAYOUT_LIMIT; }
    s.cache.push(Cached { row, span.start, span.end, layout }); Line { span.start, span.end, layout }
}
fn reveal<A>(v: lab_ui_view::View<A>&, c: const lab_ui_render_scene::Canvas&, s: State&, d: const lab_document_model::Document&, area: lab_ui_geometry::Rect, cfg: lab_ui_views_text::Config<A>) {
    let row = lab_document_piece_tree::line_at(d.tree, d.selection.cursor); let r = lab_ui_views_text::inside(area, cfg); let l = line(s, d, row, c.fonts[cfg.font].font);
    let x = lab_ui_render_text_layout::position(l.layout, min(d.selection.cursor, l.end) - l.start); s.width = max(s.width, x + 2.0);
    lab_ui_layout_scroll::reveal(lab_ui_view::scroll_state(v, cfg.scroll_id), row * cfg.stride, (row + 1) * cfg.stride, r.h, lab_document_model::lines(d) * cfg.stride);
    lab_ui_layout_scroll::reveal(s.horizontal, x, x + 2.0, r.w, s.width + 2.0);
}
fn thumb<A>(s: const State&, area: lab_ui_geometry::Rect, cfg: lab_ui_views_text::Config<A>) -> lab_ui_geometry::Rect {
    let b = lab_ui_views_text::bar(area, cfg); if b.w <= 0.0 || s.width + 2.0 <= b.w { return lab_ui_geometry::Rect {}; }
    let w = min(b.w, max(24.0, b.w * b.w / (s.width + 2.0)));
    let x = b.x + clamp(s.horizontal.offset, 0.0, s.width + 2.0 - b.w) / (s.width + 2.0 - b.w) * (b.w - w);
    lab_ui_geometry::rect(x, b.y + 4.0, w, 6.0)
}
fn at_view<A>(v: lab_ui_view::View<A>&, c: const lab_ui_render_scene::Canvas&, s: State&, d: const lab_document_model::Document&, area: lab_ui_geometry::Rect, cfg: lab_ui_views_text::Config<A>, enabled: bool = true) {
    let b = lab_ui_views_text::body(area); let r = lab_ui_views_text::inside(area, cfg);
    let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(v, cfg.scroll_id), r.h, cfg.stride, lab_document_model::lines(d), 1);
    for row in range.first..range.end { let l = line(s, d, row, c.fonts[cfg.font].font); s.width = max(s.width, lab_ui_render_text_layout::width(l.layout)); }
    lab_ui_layout_scroll::constrain(s.horizontal, r.w, s.width + 2.0);
    if v.input.captured != cfg.id { s.dragging = false; } if v.input.captured != cfg.bar_id { s.bar_dragging = false; }
    lab_ui_view::at_custom(v, "editor-input", cfg.id, cfg.action, lab_ui_geometry::rect(b.x, b.y, max(0.0, b.w - 16.0), b.h), enabled, true, true, true);
    lab_ui_view::at_scroll_viewport(v, b, cfg.scroll_id, lab_document_model::lines(d) * cfg.stride) {};
    lab_ui_view::at_custom(v, "editor-horizontal", cfg.bar_id, cfg.action, lab_ui_views_text::bar(area, cfg), enabled && !lab_ui_geometry::empty(thumb(s, area, cfg)), false);
}
fn hit<A>(v: const lab_ui_view::View<A>&, c: const lab_ui_render_scene::Canvas&, s: State&, d: const lab_document_model::Document&, area: lab_ui_geometry::Rect, cfg: lab_ui_views_text::Config<A>, x: f32, y: f32) -> i64 {
    let r = lab_ui_views_text::inside(area, cfg); let field = lab_collections_state_bank::lookup(v.scrolls, cfg.scroll_id); let vertical: f32 = if field { field.offset } else { 0.0 };
    let row = clamp(floor((y - r.y + vertical) / cfg.stride) as i64, 0, lab_document_model::lines(d) - 1);
    let l = line(s, d, row, c.fonts[cfg.font].font); l.start + lab_ui_render_text_layout::hit(l.layout, x - r.x + s.horizontal.offset)
}
fn edit(d: lab_document_model::Document&, s: State&, text: const u8[:], typing: bool = false) -> bool {
    let code, changed = lab_document_model::insert(d, text, typing);
    if changed && !lab_document_model::grapheme_boundary(d,d.selection.cursor) {
        let at=lab_document_model::next(d,d.selection.cursor); d.selection=lab_document_model::Selection {at,at};
        // Keep the accepted post-edit caret in the undo entry without splitting typing.
        if d.at>0 { d.history[d.at-1].selection=d.selection; }
    } s.code = code; s.preferred = -1.0; changed
}
fn move(d: lab_document_model::Document&, at: i64, shift: bool) { assert(lab_document_model::select(d, at, if shift { d.selection.anchor } else { at })); }
fn input<A>(v: lab_ui_view::View<A>&, c: const lab_ui_render_scene::Canvas&, s: State&, d: lab_document_model::Document&, area: lab_ui_geometry::Rect, cfg: lab_ui_views_text::Config<A>, event: lab_ui_view::Event<A>) -> bool {
    let e = event.input; let r = lab_ui_views_text::inside(area, cfg); let font = c.fonts[cfg.font].font; s.copy_failed = false;
    if s.composition.pending && s.composition.revision!=d.revision { cancel(s); gfx::clear_composition(); }
    if e.kind == gfx::EVENT_FOCUS_LOST { cancel(s); s.dragging = false; s.bar_dragging = false; lab_document_model::break_group(d); return false; }
    if e.kind==gfx::EVENT_TEXT_EDITING {
        if !s.composition.pending { lab_document_model::break_group(d); }
        if !lab_ui_input_composition::update(s.composition,e,lab_document_model::first(d),lab_document_model::last(d),d.revision) { s.code=LAYOUT_LIMIT; v.input.composing=false; v.input.text_pending=false; }
        if lab_ui_input_composition::active(s.composition) {
            let row=lab_document_piece_tree::line_at(d.tree,s.composition.first);
            lab_ui_layout_scroll::reveal(lab_ui_view::scroll_state(v,cfg.scroll_id),row*cfg.stride,(row+1)*cfg.stride,r.h,lab_document_model::lines(d)*cfg.stride);
            let first=lab_document_piece_tree::line_span(d.tree,row); let last=lab_document_piece_tree::line_span(d.tree,lab_document_piece_tree::line_at(d.tree,s.composition.last));
            if s.composition.first-first.start+s.composition.text.len+last.end-s.composition.last>1048576 {
                cancel(s); gfx::clear_composition(); v.input.composing=false; v.input.text_pending=false; s.code=LAYOUT_LIMIT;
            }
        }
        return true;
    }
    if e.kind==gfx::EVENT_TEXT_COMMIT {
        let bytes,ok=lab_ui_input_composition::payload(e.text,65532); let composing=s.composition.pending;
        if composing { assert(lab_document_model::select(d,s.composition.last,s.composition.first)); }
        cancel(s); if ok { edit(d,s,bytes,!composing); } else { s.code=LAYOUT_LIMIT; }
        if composing { lab_document_model::break_group(d); } reveal(v,c,s,d,area,cfg); return true;
    }
    if s.composition.pending && !lab_ui_input_composition::active(s.composition) && e.kind==gfx::EVENT_KEY && e.down { cancel(s); }
    if e.kind==gfx::EVENT_KEY && e.down && lab_ui_input_composition::active(s.composition) {
        if e.scancode==gfx::scancode("Escape") { cancel(s); gfx::clear_composition(); } return true;
    }
    if e.kind==gfx::EVENT_MOUSE_BUTTON && e.down && s.composition.pending { cancel(s); gfx::clear_composition(); }
    if event.source == cfg.bar_id {
        let b = lab_ui_views_text::bar(area, cfg); let t = thumb(s, area, cfg); let x = e.x / c.scale;
        if e.kind == gfx::EVENT_MOUSE_BUTTON && e.button == gfx::MOUSE_LEFT {
            if e.down { v.input.focused = cfg.id; if x >= t.x && x <= t.x + t.w { s.bar_dragging = true; s.grab = (x - t.x) / t.w; } else { lab_ui_layout_scroll::consume(s.horizontal, if x < t.x { -b.w } else { b.w }, b.w, s.width + 2.0); } } else { s.bar_dragging = false; }
        }
        if s.bar_dragging && (e.kind == gfx::EVENT_MOUSE_MOTION || e.kind == gfx::EVENT_MOUSE_BUTTON) && b.w > t.w { s.horizontal.offset = clamp((x - b.x - s.grab * t.w) / (b.w - t.w), 0.0, 1.0) * lab_ui_layout_scroll::limit(b.w, s.width + 2.0); } return true;
    }
    if e.kind == gfx::EVENT_MOUSE_BUTTON && e.button == gfx::MOUSE_LEFT {
        if e.down { move(d, hit(v, c, s, d, area, cfg, e.x / c.scale, e.y / c.scale), (e.mods & gfx::MOD_SHIFT) != 0); s.dragging = true; s.preferred = -1.0; } else { s.dragging = false; } return true;
    }
    if e.kind == gfx::EVENT_MOUSE_MOTION && s.dragging {
        let y = e.y / c.scale; if y < r.y || y > r.y + r.h { lab_ui_layout_scroll::consume(lab_ui_view::scroll_state(v, cfg.scroll_id), y - clamp(y, r.y, r.y + r.h), r.h, lab_document_model::lines(d) * cfg.stride); }
        move(d, hit(v, c, s, d, area, cfg, e.x / c.scale, y), true); reveal(v, c, s, d, area, cfg); return true;
    }
    if e.kind == gfx::EVENT_MOUSE_WHEEL && e.x != 0.0 { lab_ui_layout_scroll::consume(s.horizontal, -e.x * 44.0, r.w, s.width + 2.0); return true; }
    if e.kind == gfx::EVENT_TEXT && e.codepoint >= 32 && e.codepoint != 127 && e.codepoint <= 0x10FFFF && !(e.codepoint >= 0xD800 && e.codepoint <= 0xDFFF) { var bytes: u8[>..] = []; push_utf8(bytes, e.codepoint); edit(d, s, bytes, true); reveal(v, c, s, d, area, cfg); return true; }
    if e.kind != gfx::EVENT_KEY || !e.down { return false; }
    let shift = (e.mods & gfx::MOD_SHIFT) != 0; let ctrl = (e.mods & gfx::MOD_CTRL) != 0;
    if ctrl && e.scancode == gfx::scancode("A") { move(d, lab_document_model::size(d), false); d.selection.anchor = 0; return true; }
    if ctrl && (e.scancode == gfx::scancode("C") || e.scancode == gfx::scancode("X")) {
        if lab_document_model::first(d) != lab_document_model::last(d) { let text = lab_document_model::read(d, lab_document_model::first(d), lab_document_model::last(d)); s.copy_failed = !gfx::set_clipboard(text); if !s.copy_failed && e.scancode == gfx::scancode("X") { edit(d, s, ""); reveal(v, c, s, d, area, cfg); } } return true;
    }
    if ctrl && e.scancode == gfx::scancode("V") { let text = gfx::clipboard(); edit(d, s, text); reveal(v, c, s, d, area, cfg); return true; }
    if ctrl && (e.scancode == gfx::scancode("Z") || e.scancode == gfx::scancode("Y")) { if shift || e.scancode == gfx::scancode("Y") { lab_document_model::redo(d); } else { lab_document_model::undo(d); } s.preferred = -1.0; reveal(v, c, s, d, area, cfg); return true; }
    if !ctrl && (e.scancode == gfx::scancode("Return") || e.scancode == gfx::scancode("Tab")) { edit(d, s, if e.scancode == gfx::scancode("Return") { d.newline[..] } else { "\t" }); reveal(v, c, s, d, area, cfg); return true; }
    if !ctrl && (e.scancode == gfx::scancode("Backspace") || e.scancode == gfx::scancode("Delete")) {
        var first = lab_document_model::first(d); var last = lab_document_model::last(d);
        if first == last { if e.scancode == gfx::scancode("Backspace") { first = lab_document_model::previous(d, d.selection.cursor); } else { last = lab_document_model::next(d, d.selection.cursor); } }
        let code, changed = lab_document_model::replace(d, first, last, ""); s.code = code; s.preferred = -1.0; reveal(v, c, s, d, area, cfg); return true;
    }
    let row = lab_document_piece_tree::line_at(d.tree, d.selection.cursor); let span = lab_document_piece_tree::line_span(d.tree, row);
    if e.scancode == gfx::scancode("Left") || e.scancode == gfx::scancode("Right") {
        let left = e.scancode == gfx::scancode("Left");
        let at = if !shift && lab_document_model::first(d) != lab_document_model::last(d) { if left { lab_document_model::first(d) } else { lab_document_model::last(d) } } else if left { lab_document_model::previous(d, d.selection.cursor) } else { lab_document_model::next(d, d.selection.cursor) };
        move(d, at, shift); s.preferred = -1.0;
    } else if e.scancode == gfx::scancode("Home") || e.scancode == gfx::scancode("End") {
        let home = e.scancode == gfx::scancode("Home"); move(d, if ctrl { if home { 0 } else { lab_document_model::size(d) } } else { if home { span.start } else { span.end } }, shift); s.preferred = -1.0;
    } else if e.scancode == gfx::scancode("Up") || e.scancode == gfx::scancode("Down") || e.scancode == gfx::scancode("PageUp") || e.scancode == gfx::scancode("PageDown") {
        let up = e.scancode == gfx::scancode("Up") || e.scancode == gfx::scancode("PageUp"); let page = e.scancode == gfx::scancode("PageUp") || e.scancode == gfx::scancode("PageDown");
        let step = if page { max(1, floor(r.h / cfg.stride) as i64) } else { 1 }; let target = clamp(row + (if up { -step } else { step }), 0, lab_document_model::lines(d) - 1);
        if s.preferred < 0.0 { let l = line(s, d, row, font); s.preferred = lab_ui_render_text_layout::position(l.layout, d.selection.cursor - l.start); }
        let l = line(s, d, target, font); move(d, l.start + lab_ui_render_text_layout::hit(l.layout, s.preferred), shift);
    } else { return false; }
    reveal(v, c, s, d, area, cfg); true
}
fn paint<A>(c: lab_ui_render_scene::Canvas&, s: State&, d: const lab_document_model::Document&, area: lab_ui_geometry::Rect, cfg: lab_ui_views_text::Config<A>, vertical: f32, focused: bool) {
    let theme = lab_ui_controls_components::Theme {}; let b = lab_ui_views_text::body(area); let r = lab_ui_views_text::inside(area, cfg); let font = c.fonts[cfg.font].font;
    if s.composition.pending && s.composition.revision!=d.revision { gfx::clear_composition(); cancel(s); }
    if !focused { cancel(s); }
    let composing=lab_ui_input_composition::active(s.composition);
    let compose_row=if composing { lab_document_piece_tree::line_at(d.tree,s.composition.first) } else { -1 };
    let compose_last=if composing { lab_document_piece_tree::line_at(d.tree,s.composition.last) } else { -1 };
    let scroll = lab_ui_layout_scroll::State { offset: vertical }; let range = lab_ui_layout_scroll::visible(scroll, r.h, cfg.stride, lab_document_model::lines(d), 0); lab_ui_render_scene::push_clip(c, b);
    for row in range.first..range.end {
        let l = line(s, d, row, font); let bounds = lab_ui_geometry::rect(b.x, b.y + row * cfg.stride - vertical, b.w - 16.0, cfg.stride);
        if composing && row>compose_row && row<=compose_last { continue; }
        let current = lab_document_piece_tree::line_at(d.tree, d.selection.cursor) == row;
        if current { lab_ui_render_scene::fill(c, bounds, float4 { 0.14, 0.14, 0.23, 1.0 }); }
        lab_ui_render_scene::label(c, cfg.font, lab_ui_geometry::rect(b.x + 4.0, bounds.y, cfg.gutter - 12.0, cfg.stride), str(row + 1), theme.muted, true);
        let y = bounds.y + (cfg.stride - lab_ui_render_font::metrics(font).height) / 2.0; let x = r.x - s.horizontal.offset; lab_ui_render_scene::push_clip(c, r);
        if composing && row==compose_row {
            let layout=preview(s,d,font); let offset=s.composition.first-l.start;
            let start=lab_ui_render_text_layout::position(layout,offset); let end=lab_ui_render_text_layout::position(layout,offset+s.composition.text.len);
            let caret=lab_ui_render_text_layout::position(layout,offset+s.composition.cursor); let selected=lab_ui_render_text_layout::position(layout,offset+s.composition.end);
            // Follow the virtual caret without changing committed selection or history.
            lab_ui_layout_scroll::reveal(s.horizontal,caret,caret+2.0,r.w,max(s.width,lab_ui_render_text_layout::width(layout))+2.0); let px=r.x-s.horizontal.offset;
            lab_ui_render_scene::fill(c,lab_ui_geometry::rect(px+caret,bounds.y,selected-caret,cfg.stride),float4 {0.25,0.23,0.48,1.0});
            let glyphs=lab_ui_render_text_layout::window(layout,c.clip.x-px,c.clip.x+c.clip.w-px); lab_ui_render_scene::draw_glyphs(c,cfg.font,px,y,glyphs,theme.text);
            lab_ui_render_scene::fill(c,lab_ui_geometry::rect(px+start,y+lab_ui_render_font::metrics(font).height-1.0/c.scale,end-start,1.0/c.scale),theme.accent);
            lab_ui_render_scene::fill(c,lab_ui_geometry::rect(round((px+caret)*c.scale)/c.scale,round(y*c.scale)/c.scale,1.0/c.scale,lab_ui_render_font::metrics(font).height),theme.text);
            gfx::text_input_area(clamp(px+caret,r.x,r.x+r.w)*c.scale,y*c.scale,1.0,lab_ui_render_font::metrics(font).height*c.scale,0.0);
            lab_ui_render_scene::pop_clip(c); continue;
        }
        let first = lab_document_model::first(d); let last = lab_document_model::last(d);
        if first != last && last > l.start && first <= l.end {
            let start = lab_ui_render_text_layout::position(l.layout, max(first, l.start) - l.start); let end = lab_ui_render_text_layout::position(l.layout, min(last, l.end) - l.start);
            lab_ui_render_scene::fill(c, lab_ui_geometry::rect(x + start, bounds.y, end - start + (if last > l.end { 6.0 } else { 0.0 }), cfg.stride), float4 { 0.25, 0.23, 0.48, 1.0 });
        }
        if l.layout.id != 0 { let glyphs = lab_ui_render_text_layout::window(l.layout, c.clip.x-x, c.clip.x+c.clip.w-x); lab_ui_render_scene::draw_glyphs(c, cfg.font, x, y, glyphs, theme.text); }
        else { lab_ui_render_scene::text(c, cfg.font, r.x, y, "Line shaping limit reached", theme.muted); }
        if focused && !composing && current { let caret = lab_ui_render_text_layout::position(l.layout, d.selection.cursor - l.start);
            if first==last { lab_ui_render_scene::fill(c, lab_ui_geometry::rect(round((x + caret) * c.scale) / c.scale, round(y * c.scale) / c.scale, 1.0 / c.scale, lab_ui_render_font::metrics(font).height), theme.text); }
            gfx::text_input_area(clamp(x+caret,r.x,r.x+r.w)*c.scale,y*c.scale,1.0,lab_ui_render_font::metrics(font).height*c.scale,0.0);
        }
        lab_ui_render_scene::pop_clip(c);
    }
    lab_ui_render_scene::pop_clip(c); let t = thumb(s, area, cfg); if !lab_ui_geometry::empty(t) { lab_ui_render_scene::fill(c, t, if s.bar_dragging { theme.accent } else { theme.border }, 3.0); }
}
