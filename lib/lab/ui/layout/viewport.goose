// Pure nested viewport geometry: clips and translations share one parent chain.
namespace lab_ui_layout_viewport;
import std;
import vec;
import lab.ui.geometry;
struct Region {
    bounds: lab_ui_geometry::Rect, parent: i64 = -1, offset: float2 = float2 { 0.0, 0.0 },
    translation: float2 = float2 { 0.0, 0.0 }, world: lab_ui_geometry::Rect = lab_ui_geometry::Rect {},
    clip: lab_ui_geometry::Rect = lab_ui_geometry::Rect {},
}
struct Tree { regions: Region[..128] = [], current: i64 = -1, screen: lab_ui_geometry::Rect = lab_ui_geometry::Rect {} }
fn begin(t: Tree&) { t.regions.resize(0); t.current = -1; }
fn push(t: Tree&, bounds: lab_ui_geometry::Rect, offset: float2 = float2 { 0.0, 0.0 }) -> i64 {
    let parent = t.current; t.regions.push(Region { bounds: bounds, parent: parent, offset: offset });
    t.current = t.regions.len - 1; t.current
}
fn pop(t: Tree&, region: i64) { assert(t.current == region); t.current = t.regions[region].parent; }
fn translation(t: const Tree&, region: i64) -> float2 {
    if region < 0 { float2 { 0.0, 0.0 } } else { t.regions[region].translation }
}
fn clip(t: const Tree&, region: i64) -> lab_ui_geometry::Rect {
    if region < 0 { t.screen } else { t.regions[region].clip }
}
fn resolve(t: Tree&, screen: lab_ui_geometry::Rect) {
    assert(t.current == -1); t.screen = screen;
    for i in t.regions.len {
        let parent = t.regions[i].parent; assert(parent >= -1 && parent < i);
        let inherited = translation(t, parent);
        t.regions[i].world = lab_ui_geometry::translated(t.regions[i].bounds, inherited);
        t.regions[i].translation = inherited + t.regions[i].offset;
        t.regions[i].clip = lab_ui_geometry::intersect(clip(t, parent), t.regions[i].world);
    }
}
fn place(t: const Tree&, region: i64, rect: lab_ui_geometry::Rect) -> lab_ui_geometry::Rect {
    lab_ui_geometry::translated(rect, translation(t, region))
}
// Latest visible region wins; parents precede children and later siblings cover earlier ones.
fn top(t: const Tree&, pointer: float2) -> i64 {
    var i = t.regions.len;
    while i > 0 { i--; if lab_ui_geometry::contains(t.regions[i].clip, pointer) { return i; } } -1
}
