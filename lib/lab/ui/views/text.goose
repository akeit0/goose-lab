// Read-only, unwrapped LTR text. Metadata/state own no source references.
namespace lab_ui_views_text;
import std;
import math;
import vec;
import gfx;
import lab.ui.input.shortcuts;
import lab.text.utf8;
import lab.text.grapheme;
import lab.text.strings;
import lab.text.literal_search;
import lab.text.line_index;
import lab.ui.controls.field;
import lab.ui.render.font;
import lab.ui.render.scene;
import lab.ui.layout.scroll;
import lab.ui.geometry;
import lab.ui.view;
import lab.ui.layout.engine;
import lab.ui.controls.components;
let OK: i32 = 0; let LIMIT: i32 = 1; let ENCODING: i32 = 2;
struct Index { bytes: i64 = 0, rows: lab_text_line_index::Span[..32768] = [] }
struct Document { code: i32 = OK, index: Index = Index {}, width: f32 = 0.0, font: u64 = 0 }
struct State {
    cursor: i64 = 0, anchor: i64 = 0, preferred: f32 = -1.0,
    horizontal: lab_ui_layout_scroll::State = lab_ui_layout_scroll::State {}, dragging: bool = false,
    bar_dragging: bool = false, grab: f32 = 0.0, copy_failed: bool = false,
    find_open: bool = false, query: u8[..512] = [], active: i64 = -1,
    limited: bool = false, matches: lab_text_line_index::Span[..4096] = [],
}
enum Command { Input, Find, Query, Previous, Next, Close }
struct Config<A> {
    id: u64, scroll_id: u64, bar_id: u64, action: A,
    font: i64 = 0, stride: f32 = 24.0, gutter: f32 = 0.0,
}
struct FindConfig<A> { field_id: u64, previous_id: u64, next_id: u64, close_id: u64, query: A, previous: A, next: A, close: A }
struct Line { text: u8[] = [], points: lab_ui_controls_field::Stop[] = [] }
// Tab expansion changes presentation only; source selection/copy stays exact.
fn display(source: const u8[:]) -> u8[>..] {
    var out: u8[>..] = []; var at = 0;
    while at < source.len {
        let cp, next, ok = lab_text_utf8::decode(source, at); assert(ok);
        if cp == 9 { out.append("    "); }
        else if cp < 32 || (cp >= 127 && cp <= 159) || cp == 0x2028 || cp == 0x2029 { out.push('.'); }
        else { out.append(source[at..next]); } at = next;
    } out
}
fn build(source: const u8[:], font: lab_ui_render_font::Font) -> Document {
    if source.len > 2097152 { return Document { code: LIMIT }; }
    if !lab_text_utf8::valid(source) { return Document { code: ENCODING }; }
    let index, ok = lab_text_line_index::build(source); if !ok { return Document { code: LIMIT }; }
    var width: f32 = 0.0;
    for i in index.rows.len {
        let shown = display(lab_text_line_index::line(index, source, i));
        width = max(width, lab_ui_render_font::width(font, shown));
    }
    Document { index: Index { bytes: index.bytes, rows: index.rows }, width: width, font: font.id }
}
fn first(s: const State&) -> i64 { min(s.cursor, s.anchor) }
fn last(s: const State&) -> i64 { max(s.cursor, s.anchor) }
fn selected(s: const State&, source: const u8[:]) -> const u8[:] { source[first(s)..last(s)] }
fn row_at(d: const Document&, byte: i64) -> i64 {
    if d.index.rows.len == 0 { return -1; }
    let at = clamp(byte, 0, max(0, d.index.bytes - 1)); var first = 0; var end = d.index.rows.len;
    while first < end { let mid = first + (end - first) / 2; if d.index.rows[mid].start <= at { first = mid + 1; } else { end = mid; } } first - 1
}
fn line(d: const Document&, source: const u8[:], row: i64, font: lab_ui_render_font::Font) -> Line {
    assert(font.id == d.font);
    assert(source.len == d.index.bytes); let span = d.index.rows[row]; let raw = source[span.start..span.end]; let shown = display(raw);
    let stops = lab_ui_controls_field::stops(font, shown); var points: lab_ui_controls_field::Stop[>..] = [];
    points.push(lab_ui_controls_field::Stop { 0, 0.0 }); var at = 0; var offset = 0; var stop = 0;
    let carets,ok=lab_text_grapheme::offsets(raw); assert(ok); var caret=1;
    while at < raw.len {
        let cp, next, ok = lab_text_utf8::decode(raw, at); assert(ok);
        offset += if cp == 9 { 4 } else if cp < 32 || (cp >= 127 && cp <= 159) || cp == 0x2028 || cp == 0x2029 { 1 } else { next - at };
        while stop + 1 < stops.len && stops[stop].byte < offset { stop++; }
        while caret<carets.len && carets[caret]<next { caret++; }
        points.push(lab_ui_controls_field::Stop { next, stops[stop].x, caret<carets.len && carets[caret]==next }); at = next;
    } Line { text: shown, points: points }
}
fn body(area: lab_ui_geometry::Rect) -> lab_ui_geometry::Rect { lab_ui_geometry::rect(area.x, area.y, area.w, max(0.0, area.h - 14.0)) }
fn inside<A>(area: lab_ui_geometry::Rect, cfg: Config<A>) -> lab_ui_geometry::Rect {
    let b = body(area); lab_ui_geometry::rect(b.x + cfg.gutter, b.y, max(0.0, b.w - cfg.gutter - 16.0), b.h)
}
fn bar<A>(area: lab_ui_geometry::Rect, cfg: Config<A>) -> lab_ui_geometry::Rect {
    let r = inside(area, cfg); lab_ui_geometry::rect(r.x, area.y + area.h - 14.0, r.w, 14.0)
}
fn thumb<A>(s: const State&, d: const Document&, area: lab_ui_geometry::Rect, cfg: Config<A>) -> lab_ui_geometry::Rect {
    let b = bar(area, cfg);
    if b.w <= 0.0 || d.width + 2.0 <= b.w { return lab_ui_geometry::Rect {}; }
    let w = min(b.w, max(24.0, b.w * b.w / (d.width + 2.0)));
    let x = b.x + clamp(s.horizontal.offset, 0.0, d.width + 2.0 - b.w) / (d.width + 2.0 - b.w) * (b.w - w);
    lab_ui_geometry::rect(x, b.y + 4.0, w, 6.0)
}
fn find(s: State&, source: const u8[:]) {
    s.matches.resize(0); s.active = -1; s.limited = false;
    if s.query.len == 0 { return; }
    let pattern = lab_text_literal_search::compile(s.query, true); assert(pattern.valid);
    var cursor = lab_text_literal_search::Cursor {};
    loop {
        let batch = lab_text_literal_search::scan(pattern, source, cursor);
        for span in batch.matches {
            if s.matches.len == 4096 { s.matches.resize(0); s.limited = true; return; }
            s.matches.push(span);
        }
        if batch.done { break; }
    }
}
fn reset(s: State&, source: const u8[:]) {
    s.cursor = 0; s.anchor = 0; s.preferred = -1.0; s.horizontal.offset = 0.0;
    s.dragging = false; s.bar_dragging = false; s.copy_failed = false; find(s, source);
}
// Replacing the same document keeps its viewport and bounded byte selection.
// This preserves position, not semantic correspondence after inserted text.
fn rebase(s: State&, source: const u8[:]) {
    s.cursor = min(s.cursor, source.len); s.anchor = min(s.anchor, source.len);
    while s.cursor > 0 && s.cursor < source.len && (source[s.cursor] & 0xC0) == 0x80 { s.cursor--; }
    while s.anchor > 0 && s.anchor < source.len && (source[s.anchor] & 0xC0) == 0x80 { s.anchor--; }
    s.dragging = false; s.bar_dragging = false; s.preferred = -1.0; find(s, source);
}
fn move(s: State&, byte: i64, shift: bool) { s.cursor = byte; if !shift { s.anchor = byte; } }
fn choose_match(s: State&, direction: i64) -> bool {
    if s.matches.len == 0 { return false; }
    s.active = if s.active < 0 { if direction < 0 { s.matches.len - 1 } else { 0 } }
        else { (s.active + direction + s.matches.len) % s.matches.len };
    let found = s.matches[s.active]; s.anchor = found.start; s.cursor = found.end; s.preferred = -1.0; true
}
fn reveal<A>(v: lab_ui_view::View<A>&, c: const lab_ui_render_scene::Canvas&, s: State&, d: const Document&, source: const u8[:], area: lab_ui_geometry::Rect, cfg: Config<A>) {
    let row = row_at(d, s.cursor); if row < 0 { return; }
    let r = inside(area, cfg); let l = line(d, source, row, c.fonts[cfg.font].font);
    let x = lab_ui_controls_field::position(l.points, min(s.cursor, d.index.rows[row].end) - d.index.rows[row].start);
    lab_ui_layout_scroll::reveal(lab_ui_view::scroll_state(v, cfg.scroll_id), row * cfg.stride, (row + 1) * cfg.stride, r.h, d.index.rows.len * cfg.stride);
    lab_ui_layout_scroll::reveal(s.horizontal, x, x + 2.0, r.w, d.width + 2.0);
}
fn hit<A>(d: const Document&, source: const u8[:], font: lab_ui_render_font::Font, area: lab_ui_geometry::Rect, cfg: Config<A>, vertical: f32, horizontal: f32, x: f32, y: f32) -> i64 {
    if d.index.rows.len == 0 { return 0; }
    let r = inside(area, cfg);
    let row = clamp(floor((y - r.y + vertical) / cfg.stride) as i64, 0, d.index.rows.len - 1);
    let l = line(d, source, row, font);
    d.index.rows[row].start + lab_ui_controls_field::hit(l.points, x - r.x + horizontal)
}
fn at_view<A>(v: lab_ui_view::View<A>&, area: lab_ui_geometry::Rect, cfg: Config<A>, s: State&, d: const Document&) {
    assert(cfg.stride > 0.0 && cfg.gutter >= 0.0);
    let b = body(area); let r = inside(area, cfg);
    if v.input.captured != cfg.id { s.dragging = false; }
    if v.input.captured != cfg.bar_id { s.bar_dragging = false; }
    lab_ui_layout_scroll::constrain(s.horizontal, r.w, d.width + 2.0);
    lab_ui_view::at_custom(v, str("text-view-", cfg.id), cfg.id, cfg.action, lab_ui_geometry::rect(b.x, b.y, max(0.0, b.w - 16.0), b.h), d.code == OK);
    lab_ui_view::at_scroll_viewport(v, b, cfg.scroll_id, d.index.rows.len * cfg.stride) {};
    lab_ui_view::at_custom(v, str("text-bar-", cfg.bar_id), cfg.bar_id, cfg.action, bar(area, cfg), !lab_ui_geometry::empty(thumb(s, d, area, cfg)), false);
}
fn find_bar<A>(v: lab_ui_view::View<A>&, s: const State&, name: const u8[:], cfg: FindConfig<A>) {
    if !s.find_open { return; }
    let result: u8[>..] = if s.limited { "Too many · Refine" } else { str(if s.active >= 0 { s.active + 1 } else { 0 }, "/", s.matches.len) };
    lab_ui_view::box(v, name, lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 6 }) {
        lab_ui_view::field(v, str(name, "-query"), cfg.field_id, cfg.query, "Find in text…", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
        lab_ui_view::label(v, str(name, "-count"), result, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(if s.limited { 112.0 } else { 56.0 }), height: lab_ui_layout_engine::grow() }, 2, lab_ui_controls_components::Theme {}.muted);
        lab_ui_view::button(v, str(name, "-previous"), cfg.previous_id, cfg.previous, "↑", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(32.0), height: lab_ui_layout_engine::grow() }, false, s.matches.len > 0);
        lab_ui_view::button(v, str(name, "-next"), cfg.next_id, cfg.next, "↓", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(32.0), height: lab_ui_layout_engine::grow() }, false, s.matches.len > 0);
        lab_ui_view::button(v, str(name, "-close"), cfg.close_id, cfg.close, "×", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(32.0), height: lab_ui_layout_engine::grow() });
    };
}
fn input<A>(v: lab_ui_view::View<A>&, c: const lab_ui_render_scene::Canvas&, s: State&, d: const Document&, source: const u8[:], area: lab_ui_geometry::Rect, cfg: Config<A>, event: lab_ui_view::Event<A>) -> bool {
    let e = event.input; let font = c.fonts[cfg.font].font; let r = inside(area, cfg);
    if e.kind == gfx::EVENT_FOCUS_LOST { s.dragging = false; s.bar_dragging = false; return false; }
    if event.source == cfg.bar_id {
        let b = bar(area, cfg); let t = thumb(s, d, area, cfg); let x = e.x / c.scale;
        if e.kind == gfx::EVENT_MOUSE_BUTTON && e.button == gfx::MOUSE_LEFT {
            if e.down {
                v.input.focused = cfg.id;
                if x >= t.x && x <= t.x + t.w { s.bar_dragging = true; s.grab = (x - t.x) / t.w; }
                else { lab_ui_layout_scroll::consume(s.horizontal, if x < t.x { -b.w } else { b.w }, b.w, d.width + 2.0); }
            } else { s.bar_dragging = false; }
        }
        if s.bar_dragging && (e.kind == gfx::EVENT_MOUSE_MOTION || e.kind == gfx::EVENT_MOUSE_BUTTON) && b.w > t.w {
            s.horizontal.offset = clamp((x - b.x - s.grab * t.w) / (b.w - t.w), 0.0, 1.0) * lab_ui_layout_scroll::limit(b.w, d.width + 2.0);
        } return true;
    }
    if e.kind == gfx::EVENT_MOUSE_BUTTON && e.button == gfx::MOUSE_LEFT {
        if e.down {
            move(s, hit(d, source, font, area, cfg, lab_ui_view::scroll_state(v, cfg.scroll_id).offset, s.horizontal.offset, e.x / c.scale, e.y / c.scale), (e.mods & gfx::MOD_SHIFT) != 0);
            s.dragging = true; s.preferred = -1.0;
        } else { s.dragging = false; } return true;
    }
    if e.kind == gfx::EVENT_MOUSE_MOTION && s.dragging {
        let y = e.y / c.scale;
        if y < r.y || y > r.y + r.h { lab_ui_layout_scroll::consume(lab_ui_view::scroll_state(v, cfg.scroll_id), y - clamp(y, r.y, r.y + r.h), r.h, d.index.rows.len * cfg.stride); }
        move(s, hit(d, source, font, area, cfg, lab_ui_view::scroll_state(v, cfg.scroll_id).offset, s.horizontal.offset, e.x / c.scale, y), true);
        reveal(v, c, s, d, source, area, cfg); return true;
    }
    if e.kind == gfx::EVENT_MOUSE_WHEEL && e.x != 0.0 {
        lab_ui_layout_scroll::consume(s.horizontal, -e.x * 44.0, r.w, d.width + 2.0); return true;
    }
    if e.kind != gfx::EVENT_KEY || !e.down { return false; }
    let shift = (e.mods & gfx::MOD_SHIFT) != 0; let ctrl = lab_ui_input_shortcuts::command(e.mods);
    if ctrl && e.scancode == gfx::scancode("C") { if first(s) != last(s) { s.copy_failed = !gfx::set_clipboard(selected(s, source)); } return true; }
    if ctrl && e.scancode == gfx::scancode("A") { s.anchor = 0; s.cursor = source.len; return true; }
    let row = row_at(d, s.cursor); if row < 0 { return false; }
    let span = d.index.rows[row];
    if ctrl && lab_ui_input_shortcuts::macos() {
        var at: i64 = -1;
        if e.scancode == gfx::scancode("Left") { at = span.start; }
        else if e.scancode == gfx::scancode("Right") { at = span.end; }
        else if e.scancode == gfx::scancode("Up") { at = 0; }
        else if e.scancode == gfx::scancode("Down") { at = source.len; }
        if at >= 0 { move(s, at, shift); s.preferred = -1.0; reveal(v, c, s, d, source, area, cfg); return true; }
    }
    if e.scancode == gfx::scancode("Left") || e.scancode == gfx::scancode("Right") {
        let left = e.scancode == gfx::scancode("Left");
        let byte = if !shift && first(s) != last(s) { if left { first(s) } else { last(s) } }
            else if left { if s.cursor <= span.start && row > 0 { d.index.rows[row - 1].end } else if s.cursor > span.end { span.end } else { lab_text_grapheme::previous(source, s.cursor) } }
            else { if s.cursor >= span.end { if row + 1 < d.index.rows.len { d.index.rows[row + 1].start } else { source.len } } else { lab_text_grapheme::next(source, s.cursor) } };
        move(s, byte, shift); s.preferred = -1.0;
    } else if e.scancode == gfx::scancode("Home") || e.scancode == gfx::scancode("End") {
        let home = e.scancode == gfx::scancode("Home");
        move(s, if ctrl { if home { 0 } else { source.len } } else { if home { span.start } else { span.end } }, shift); s.preferred = -1.0;
    } else if e.scancode == gfx::scancode("Up") || e.scancode == gfx::scancode("Down") || e.scancode == gfx::scancode("PageUp") || e.scancode == gfx::scancode("PageDown") {
        let up = e.scancode == gfx::scancode("Up") || e.scancode == gfx::scancode("PageUp");
        let page = e.scancode == gfx::scancode("PageUp") || e.scancode == gfx::scancode("PageDown");
        let step = if page { max(1, floor(r.h / cfg.stride) as i64) } else { 1 };
        let target = clamp(row + (if up { -step } else { step }), 0, d.index.rows.len - 1);
        if s.preferred < 0.0 { let l = line(d, source, row, font); s.preferred = lab_ui_controls_field::position(l.points, min(s.cursor, span.end) - span.start); }
        let l = line(d, source, target, font); move(s, d.index.rows[target].start + lab_ui_controls_field::hit(l.points, s.preferred), shift);
    } else { return false; }
    reveal(v, c, s, d, source, area, cfg); true
}
fn handle<A>(v: lab_ui_view::View<A>&, c: const lab_ui_render_scene::Canvas&, s: State&, d: const Document&, source: const u8[:], area: lab_ui_geometry::Rect, cfg: Config<A>, search: FindConfig<A>, command: Command, event: lab_ui_view::Event<A>) -> bool {
    if command == Command.Input {
        let e = event.input;
        if e.kind == gfx::EVENT_KEY && e.down && lab_ui_input_shortcuts::command(e.mods) && e.scancode == gfx::scancode("F") {
            s.find_open = true; v.input.focused = search.field_id; return true;
        }
        if e.kind == gfx::EVENT_KEY && e.down && e.scancode == gfx::scancode("F3") {
            if choose_match(s, if (e.mods & gfx::MOD_SHIFT) != 0 { -1 } else { 1 }) { reveal(v, c, s, d, source, area, cfg); } return true;
        }
        return input(v, c, s, d, source, area, cfg, event);
    }
    if command == Command.Query && event.kind == lab_ui_view::CHANGE {
        s.query = lab_ui_view::field_state(v, search.field_id).text; find(s, source);
        if choose_match(s, 1) { reveal(v, c, s, d, source, area, cfg); } return true;
    }
    if event.kind != lab_ui_view::ACTIVATE && event.kind != lab_ui_view::SUBMIT { return false; }
    match command {
        Find => { s.find_open = true; v.input.focused = search.field_id; },
        Close => { s.find_open = false; v.input.focused = cfg.id; },
        Previous => { if choose_match(s, -1) { reveal(v, c, s, d, source, area, cfg); } },
        Next => { if choose_match(s, 1) { reveal(v, c, s, d, source, area, cfg); } },
        Query => { if choose_match(s, 1) { reveal(v, c, s, d, source, area, cfg); } }, Input => {},
    } true
}
// Row callback paints application backgrounds/gutters and returns the text color.
fn paint<A,F>(c: lab_ui_render_scene::Canvas&, s: const State&, d: const Document&, source: const u8[:], area: lab_ui_geometry::Rect, cfg: Config<A>, vertical: f32, focused: bool) {
    if d.code != OK { lab_ui_render_scene::label(c, cfg.font, area, if d.code == LIMIT { "Text exceeds the size or line limit" } else { "Text is not UTF-8" }, lab_ui_controls_components::Theme {}.muted); return; }
    let b = body(area); let r = inside(area, cfg); let font = c.fonts[cfg.font].font;
    let scroll = lab_ui_layout_scroll::State { offset: vertical };
    let range = lab_ui_layout_scroll::visible(scroll, r.h, cfg.stride, d.index.rows.len, 0);
    lab_ui_render_scene::push_clip(c, b);
    for i in range.end - range.first {
        let row = range.first + i; let span = d.index.rows[row]; let l = line(d, source, row, font);
        let bounds = lab_ui_geometry::rect(b.x, b.y + row * cfg.stride - vertical, b.w - 16.0, cfg.stride);
        let color: float4 = F(row, bounds);
        let y = bounds.y + (cfg.stride - lab_ui_render_font::metrics(font).height) / 2.0;
        let x = r.x - s.horizontal.offset;
        lab_ui_render_scene::push_clip(c, r);
        if s.find_open {
            for found in s.matches {
                if found.start > span.end { break; }
                if found.end <= span.start { continue; }
                let start = lab_ui_controls_field::position(l.points, max(found.start, span.start) - span.start);
                let end = lab_ui_controls_field::position(l.points, min(found.end, span.end) - span.start);
                lab_ui_render_scene::fill(c, lab_ui_geometry::rect(x + start, bounds.y, end - start, cfg.stride), float4 { 0.36, 0.28, 0.06, 1.0 });
            }
        }
        if first(s) != last(s) && last(s) > span.start && first(s) <= span.end {
            let start = lab_ui_controls_field::position(l.points, max(first(s), span.start) - span.start);
            let end = lab_ui_controls_field::position(l.points, min(last(s), span.end) - span.start);
            let newline: f32 = if last(s) > span.end { 6.0 } else { 0.0 };
            lab_ui_render_scene::fill(c, lab_ui_geometry::rect(x + start, bounds.y, end - start + newline, cfg.stride), float4 { 0.25, 0.23, 0.48, 1.0 });
        }
        lab_ui_render_scene::text_window(c, cfg.font, x, y, l.text, color);
        if focused && first(s) == last(s) && row_at(d, s.cursor) == row {
            let caret = lab_ui_controls_field::position(l.points, min(s.cursor, span.end) - span.start);
            lab_ui_render_scene::fill(c, lab_ui_geometry::rect(round((x + caret) * c.scale) / c.scale, round(y * c.scale) / c.scale, 1.0 / c.scale, lab_ui_render_font::metrics(font).height), color);
        }
        lab_ui_render_scene::pop_clip(c);
    }
    lab_ui_render_scene::pop_clip(c);
    let t = thumb(s, d, area, cfg);
    if !lab_ui_geometry::empty(t) { lab_ui_render_scene::fill(c, t, if s.bar_dragging { lab_ui_controls_components::Theme {}.accent } else { lab_ui_controls_components::Theme {}.border }, 3.0); }
}
