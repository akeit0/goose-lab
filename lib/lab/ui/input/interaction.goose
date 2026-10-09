// Register current-frame hitboxes, resolve ordered input, then paint.
namespace lab_ui_input_interaction;
import std;
import vec;
import gfx;
import lab.ui.geometry;
struct Hit { id: u64, bounds: lab_ui_geometry::Rect, enabled: bool, focusable: bool, activate: bool, captures_tab: bool = false }
struct State {
    focused: u64 = 0, captured: u64 = 0, hovered: u64 = 0,
    pointer: float2 = float2 { 0.0, 0.0 }, has_focus: bool = true,
    hits: Hit[..1024] = [], events: gfx::Event[..4096] = [], clicks: u64[..256] = [],
    targets: u64[..4096] = [],
    phase: i32 = 0,
    composing: bool = false,
    text_pending: bool = false,
}
fn begin(s: State&) {
    s.hits.resize(0); s.events.resize(0); s.targets.resize(0); s.clicks.resize(0); s.hovered = 0; s.phase = 1;
}
fn register(s: State&, id: u64, bounds: lab_ui_geometry::Rect, enabled: bool = true, focusable: bool = true, activate: bool = true, captures_tab: bool = false) {
    assert(s.phase == 1 && id != 0);
    for hit in s.hits { assert(hit.id != id); }
    s.hits.push(Hit { id, bounds, enabled, focusable, activate, captures_tab });
}
fn top(s: const State&, p: float2) -> u64 {
    var i = s.hits.len;
    while i > 0 { i--; if lab_ui_geometry::contains(s.hits[i].bounds, p) { return if s.hits[i].enabled { s.hits[i].id } else { 0 }; } }
    0
}
fn valid(s: const State&, id: u64) -> bool {
    for hit in s.hits { if hit.id == id { return hit.enabled && hit.bounds.w > 0.0 && hit.bounds.h > 0.0; } } false
}
fn focusable(s: const State&, id: u64) -> bool {
    for hit in s.hits { if hit.id == id { return hit.enabled && hit.focusable && hit.bounds.w > 0.0 && hit.bounds.h > 0.0; } } false
}
fn resolve(s: State&, events: const gfx::Event[:], pointer: float2, has_focus: bool, scale: f32 = 1.0) {
    assert(s.phase == 1 && scale > 0.0);
    s.events.append(events); s.pointer = pointer / scale; s.has_focus = has_focus;
    if !valid(s, s.captured) { s.captured = 0; }
    if !focusable(s, s.focused) { s.focused = 0; }
    for e in events {
        if e.kind == gfx::EVENT_FOCUS_LOST { s.has_focus = false; s.captured = 0; s.focused = 0; s.composing=false; s.text_pending=false; }
        if e.kind == gfx::EVENT_FOCUS_GAINED { s.has_focus = true; }
        if !s.has_focus { s.targets.push(0); continue; }
        if e.kind == gfx::EVENT_MOUSE_MOTION || e.kind == gfx::EVENT_MOUSE_BUTTON { s.pointer = float2 { e.x / scale, e.y / scale }; }
        if e.kind == gfx::EVENT_MOUSE_BUTTON && e.button == gfx::MOUSE_LEFT {
            let target = top(s, s.pointer);
            if e.down { s.captured = target; s.focused = if focusable(s, target) { target } else { 0 }; }
            else { if s.captured != 0 && s.captured == target { s.clicks.push(target); } s.captured = 0; }
        }
        if e.kind==gfx::EVENT_TEXT_EDITING { var empty: u8[0]=[]; s.composing=gfx::text_event_into(e.text,empty)>0; s.text_pending=s.text_pending || s.composing; }
        if e.kind==gfx::EVENT_TEXT_COMMIT { s.composing=false; s.text_pending=false; }
        if e.kind==gfx::EVENT_KEY && e.down && !s.composing { s.text_pending=false; }
        if e.kind == gfx::EVENT_KEY && e.down && !e.repeat && !s.composing {
            var captures_tab = false; for hit in s.hits { if hit.id == s.focused && hit.captures_tab && e.mods == 0 { captures_tab = true; } }
            if e.scancode == gfx::scancode("Tab") && !captures_tab {
                var stops: u64[>..] = [];
                for hit in s.hits { if focusable(s, hit.id) { stops.push(hit.id); } }
                if stops.len > 0 {
                    var current: i64 = -1;
                    for i in stops.len { if stops[i] == s.focused { current = i; } }
                    let backwards = (e.mods & gfx::MOD_SHIFT) != 0;
                    let next = if current < 0 { if backwards { stops.len - 1 } else { 0 } }
                               else { (current + (if backwards { stops.len - 1 } else { 1 })) % stops.len };
                    s.focused = stops[next];
                }
            } else if e.scancode == gfx::scancode("Return") || e.scancode == gfx::scancode("Space") {
                for hit in s.hits { if hit.id == s.focused && hit.activate { s.clicks.push(s.focused); } }
            }
        }
        s.targets.push(s.focused);
    }
    if !s.has_focus { s.captured = 0; s.focused = 0; s.hovered = 0; }
    else { s.hovered = top(s, s.pointer); }
    s.phase = 2;
}
fn clicked(s: const State&, id: u64) -> bool { assert(s.phase == 2); for click in s.clicks { if click == id { return true; } } false }
