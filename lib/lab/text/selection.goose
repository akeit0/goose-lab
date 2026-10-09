// Logical selection navigation, independent of rendered rows and platform key names.
namespace lab_text_selection;
import std;
import math;
enum Motion { None, Previous, Next, First, Last, PagePrevious, PageNext }
fn page_rows(viewport_height: f32, stride: f32) -> i64 {
    assert(stride > 0.0); max(1, floor(max(0.0, viewport_height) / stride) as i64)
}
fn navigate(current: i64, count: i64, motion: Motion, page: i64 = 1) -> i64 {
    assert(count >= 0 && page >= 1);
    if count == 0 { return -1; }
    if motion == Motion.None { return clamp(current, -1, count - 1); }
    if motion == Motion.First { return 0; }
    if motion == Motion.Last { return count - 1; }
    if current < 0 { return if motion == Motion.Previous || motion == Motion.PagePrevious { count - 1 } else { 0 }; }
    let position = min(current, count - 1); let step = min(page, count - 1);
    match motion {
        Previous => max(0, position - 1), Next => min(count - 1, position + 1),
        PagePrevious => max(0, position - step), PageNext => position + min(step, count - 1 - position),
        None => position, First => 0, Last => count - 1,
    }
}
