namespace lab_ui_geometry;
import vec;
struct Rect { x: f32 = 0.0, y: f32 = 0.0, w: f32 = 0.0, h: f32 = 0.0 }
fn rect(x: f32, y: f32, w: f32, h: f32) -> Rect { Rect { x, y, w, h } }
fn contains(r: Rect, p: float2) -> bool { p.x >= r.x && p.y >= r.y && p.x < r.x + r.w && p.y < r.y + r.h }
fn intersect(a: Rect, b: Rect) -> Rect {
    let x: f32 = max(a.x, b.x); let y: f32 = max(a.y, b.y);
    Rect { x, y, max(0.0, min(a.x + a.w, b.x + b.w) - x), max(0.0, min(a.y + a.h, b.y + b.h) - y) }
}

fn translated(r: Rect, offset: float2) -> Rect { Rect { r.x + offset.x, r.y + offset.y, r.w, r.h } }
fn empty(r: Rect) -> bool { r.w <= 0.0 || r.h <= 0.0 }
