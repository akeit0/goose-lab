namespace lab_ui_layout_scroll;
import std;
import vec;
import math;
import lab.ui.geometry;
struct State { offset: f32 = 0.0 }
fn limit(viewport_height: f32, content_height: f32) -> f32 { max(0.0, content_height - max(0.0, viewport_height)) }
fn constrain(s: State&, viewport_height: f32, content_height: f32) { s.offset = clamp(s.offset, 0.0, limit(viewport_height, content_height)); }
// Positive delta moves down. Return movement that could not be consumed at a boundary.
fn consume(s: State&, delta: f32, viewport_height: f32, content_height: f32) -> f32 {
    constrain(s, viewport_height, content_height); let before = s.offset;
    s.offset = clamp(before + delta, 0.0, limit(viewport_height, content_height));
    delta - (s.offset - before)
}
fn reveal(s: State&, top: f32, bottom: f32, viewport_height: f32, content_height: f32) {
    assert(bottom >= top && viewport_height >= 0.0);
    if bottom - top > viewport_height || top < s.offset { s.offset = top; }
    else if bottom > s.offset + viewport_height { s.offset = bottom - viewport_height; }
    constrain(s, viewport_height, content_height);
}
struct Range { first: i64 = 0, end: i64 = 0 }
// Half-open index range for uniform-height rows. Offscreen rows need no descriptions.
fn visible(s: const State&, viewport_height: f32, stride: f32, count: i64, overscan: i64 = 1) -> Range {
    assert(stride > 0.0 && count >= 0 && overscan >= 0);
    if viewport_height <= 0.0 || count == 0 { return Range {}; }
    let offset = max(0.0, s.offset);
    Range { clamp((floor(offset / stride) as i64) - overscan, 0, count),
            clamp((ceil((offset + viewport_height) / stride) as i64) + overscan, 0, count) }
}
fn update(s: State&, viewport: lab_ui_geometry::Rect, content_height: f32, pointer: float2, wheel: f32) {
    if lab_ui_geometry::contains(viewport, pointer) { s.offset -= wheel * 44.0; }
    constrain(s, viewport.h, content_height);
}
fn thumb(s: const State&, viewport: lab_ui_geometry::Rect, content_height: f32) -> lab_ui_geometry::Rect {
    if viewport.w <= 0.0 || viewport.h <= 0.0 || content_height <= viewport.h { return lab_ui_geometry::rect(0.0, 0.0, 0.0, 0.0); }
    let h = min(viewport.h, max(24.0, viewport.h * viewport.h / content_height));
    lab_ui_geometry::rect(viewport.x + viewport.w - 8.0, viewport.y + clamp(s.offset, 0.0, content_height - viewport.h) / (content_height - viewport.h) * (viewport.h - h), 6.0, h)
}
// Wider pointer target than the drawn thumb; both stay inside the viewport.
fn track(viewport: lab_ui_geometry::Rect) -> lab_ui_geometry::Rect {
    let w = min(14.0, max(0.0, viewport.w));
    lab_ui_geometry::rect(viewport.x + viewport.w - w, viewport.y, w, max(0.0, viewport.h))
}
// grab is the fraction of thumb height where dragging started, preserved on resize.
fn drag(s: State&, pointer_y: f32, grab: f32, viewport: lab_ui_geometry::Rect, content_height: f32) {
    let t = thumb(s, viewport, content_height); let travel = viewport.h - t.h;
    if lab_ui_geometry::empty(t) || travel <= 0.0 { constrain(s, viewport.h, content_height); return; }
    s.offset = clamp((pointer_y - viewport.y - clamp(grab, 0.0, 1.0) * t.h) / travel, 0.0, 1.0) * limit(viewport.h, content_height);
}
