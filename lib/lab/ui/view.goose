// Shared modern UI composition. Descriptions own text; no callbacks or borrowed data escape.
namespace lab_ui_view;
import std;
import vec;
import gfx;
import lab.ui.geometry;
import lab.ui.layout.engine;
import lab.ui.render.scene;
import lab.ui.input.interaction;
import lab.ui.controls.components;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.ui.layout.viewport;
import lab.collections.state_bank;
import lab.text.selection;
import lab.ui.input.composition;
let BUTTON: i32 = 1;
let TOGGLE: i32 = 2;
let CHECKBOX: i32 = 3;
let FIELD: i32 = 4;
let LABEL: i32 = 5;
let CARD: i32 = 6;
let FILL: i32 = 7;
let PARAGRAPH: i32 = 8;
let SCROLLBAR: i32 = 9;
let LIST: i32 = 10;
let LIST_ITEM: i32 = 11;
let CHEVRON: i32 = 12;
let CUSTOM: i32 = 13;
let ACTIVATE: i32 = 1;
let CHANGE: i32 = 2;
let SUBMIT: i32 = 3;
let REJECTED: i32 = 4;
let SELECT: i32 = 5;
let EXPAND: i32 = 6;
let COLLAPSE: i32 = 7;
let INPUT: i32 = 8;
let CLOSE_REQUESTED: i32 = 9;
struct Event<A> { kind: i32, action: A, source: u64, text: u8[..512] = [], index: i64 = -1, reveal: bool = false, pointer: bool = false, input: gfx::Event = default<gfx::Event>() }
struct Node<A> {
    name: u8[..96] = [], text: u8[..512] = [], viewport: i64 = -1,
    id: u64 = 0, kind: i32 = 0, action: A = default<A>(),
    rect: lab_ui_geometry::Rect = lab_ui_geometry::Rect {}, placement: lab_ui_geometry::Rect = lab_ui_geometry::Rect {}, clip: lab_ui_geometry::Rect = lab_ui_geometry::Rect {},
    offset: float2 = float2 { 0.0, 0.0 }, placed: bool = false,
    enabled: bool = true, value: bool = false, primary: bool = false,
    font: i64 = 0, color: float4 = lab_ui_controls_components::Theme {}.text, centered: bool = false,
    limit: i64 = 240, clear_on_submit: bool = false, accepts_text: bool = false, captures_tab: bool = false, text_tag: u32 = 0,
    scroll_region: i64 = -1, list: i64 = -1, index: i64 = -1, focusable: bool = true,
    text_layout: lab_ui_layout_engine::Context = lab_ui_layout_engine::Context { id: 0 }, layer: u64 = 0,
}
struct Viewport { name: u8[..96] = [], scroll_id: u64 = 0, content_height: f32 = 0.0, layer: u64 = 0 }
struct ScrollDrag { id: u64 = 0, grab: f32 = 0.0 }
// Owned, controlled selection: reducers adopt an event index or map it to a domain ID.
struct ListConfig<A> {
    id: u64, scroll_id: u64, count: i64, stride: f32,
    selected: i64 = -1, action: A = default<A>(), enabled: bool = true, hierarchical: bool = false, framed: bool = true, activate_on_click: bool = false,
}
struct List<A> { config: ListConfig<A>, region: i64 }
struct Shortcut<A> { scancode: i32, mods: i32, action: A, layer: u64 = 0, repeat: bool = false }
struct View<A> {
    layout: lab_ui_layout_engine::Context = lab_ui_layout_engine::Context { id: 0 }, input: lab_ui_input_interaction::State = lab_ui_input_interaction::State {},
    nodes: Node<A>[..1024] = [], fields: lab_collections_state_bank::Bank<lab_ui_controls_field::State> = lab_collections_state_bank::Bank<lab_ui_controls_field::State> {},
    scrolls: lab_collections_state_bank::Bank<lab_ui_layout_scroll::State> = lab_collections_state_bank::Bank<lab_ui_layout_scroll::State> {},
    regions: lab_ui_layout_viewport::Tree = lab_ui_layout_viewport::Tree {}, viewports: Viewport[..128] = [],
    lists: List<A>[..32] = [], drag: ScrollDrag = ScrollDrag {},
    shortcuts: Shortcut<A>[..128] = [],
    screen: lab_ui_geometry::Rect = lab_ui_geometry::Rect {}, solved: bool = false,
    layer: u64 = 0, top_layer: u64 = 0, initial_focus: u64 = 0, defer_overlays: bool = false,
    text_owner: u64 = 0,
}
fn field_state<A>(v: View<A>&, id: u64) -> lab_ui_controls_field::State& {
    lab_collections_state_bank::get(v.fields, id)
}
fn scroll_state<A>(v: View<A>&, id: u64) -> lab_ui_layout_scroll::State& { lab_collections_state_bank::get(v.scrolls, id) }
// Dispose identities by key; references returned by state accessors must not survive disposal.
fn forget_field<A>(v: View<A>&, id: u64) {
    lab_collections_state_bank::remove(v.fields, id);
    if v.input.focused == id { v.input.focused = 0; }
    if v.input.captured == id { v.input.captured = 0; }
}
fn forget_scroll<A>(v: View<A>&, id: u64) {
    lab_collections_state_bank::remove(v.scrolls, id); if v.drag.id == id { v.drag.id = 0; }
}
fn begin<A>(v: View<A>&, w: f32, h: f32, layout_height: f32 = 0.0) {
    v.nodes.resize(0); v.viewports.resize(0); v.lists.resize(0); v.shortcuts.resize(0); lab_ui_layout_viewport::begin(v.regions); v.solved = false;
    v.layer = 0; v.top_layer = 0; v.initial_focus = 0;
    v.screen = lab_ui_geometry::rect(0.0, 0.0, w, h);
    assert(lab_ui_layout_engine::begin(v.layout, w, if layout_height > 0.0 { layout_height } else { h }));
}
fn shortcut<A>(v: View<A>&, key: const u8[:], mods: i32, action: A, repeat: bool = false) {
    let code = gfx::scancode(key) as i32; assert(code > 0);
    for binding in v.shortcuts { assert(binding.layer != v.layer || binding.scancode != code || binding.mods != mods); }
    v.shortcuts.push(Shortcut<A> { code, mods, action, v.layer, repeat });
}
// Declare overlay controls after solve, outside page scroll regions. Only the
// last declared layer participates in input; all layers still paint in order.
fn modal<A,F>(v: View<A>&, id: u64, initial_focus: u64) {
    assert(v.solved && id != 0 && v.regions.current == -1);
    let previous = v.layer; v.layer = id; v.top_layer = id; v.initial_focus = initial_focus;
    F(); v.layer = previous;
}
fn bounds<A>(v: const View<A>&, name: const u8[:]) -> lab_ui_geometry::Rect {
    let r, found = lab_ui_layout_engine::bounds(v.layout, name); assert(found); r
}
fn box<A,F>(v: View<A>&, name: const u8[:], config: lab_ui_layout_engine::Config = lab_ui_layout_engine::Config {}) {
    assert(!v.solved); lab_ui_layout_engine::box(v.layout, name, config) { F(); };
}
fn leaf<A>(v: View<A>&, name: const u8[:], config: lab_ui_layout_engine::Config = lab_ui_layout_engine::Config {}) {
    assert(!v.solved); lab_ui_layout_engine::leaf(v.layout, name, config);
}
// Nested clips inherit ancestor translation. Their own offset only moves their contents.
fn viewport<A,F>(v: View<A>&, name: const u8[:], offset: float2 = float2 { 0.0, 0.0 }) {
    let region = lab_ui_layout_viewport::push(v.regions, lab_ui_geometry::Rect {}, offset);
    v.viewports.push(Viewport { name: name, layer: v.layer }); F(); lab_ui_layout_viewport::pop(v.regions, region);
}
fn at_viewport<A,F>(v: View<A>&, bounds: lab_ui_geometry::Rect, offset: float2 = float2 { 0.0, 0.0 }) {
    assert(v.solved); let region = lab_ui_layout_viewport::push(v.regions, bounds, offset);
    v.viewports.push(Viewport { layer: v.layer }); F(); lab_ui_layout_viewport::pop(v.regions, region);
}
fn at_scroll_viewport<A,F>(v: View<A>&, bounds: lab_ui_geometry::Rect, id: u64, content_height: f32) {
    assert(v.solved && id != 0 && content_height >= 0.0);
    for viewport in v.viewports { assert(viewport.scroll_id != id); }
    lab_ui_layout_scroll::constrain(scroll_state(v, id), bounds.h, content_height);
    let region = lab_ui_layout_viewport::push(v.regions, bounds, float2 { 0.0, -scroll_state(v, id).offset });
    v.viewports.push(Viewport { scroll_id: id, content_height: content_height, layer: v.layer });
    F(); lab_ui_layout_viewport::pop(v.regions, region);
    // Chrome inherits only the parent's translation, so it stays fixed in its viewport.
    record(v, Node<A> { name: str("scroll-thumb-", id), kind: SCROLLBAR, rect: bounds, placed: true, scroll_region: region });
}
fn scroll_viewport<A,F>(v: View<A>&, name: const u8[:], id: u64, content_height: f32) {
    at_scroll_viewport(v, bounds(v, name), id, content_height) { F(); };
}
fn containing_list<A>(v: const View<A>&, region: i64) -> i64 {
    var current = region;
    while current >= 0 {
        for i in v.lists.len { if v.lists[i].region == current { return i; } }
        current = v.regions.regions[current].parent;
    } -1
}
fn at_list<A,F>(v: View<A>&, bounds: lab_ui_geometry::Rect, config: ListConfig<A>) {
    assert(v.solved && config.id != 0 && config.scroll_id != 0 && config.count >= 0 && config.stride > 0.0);
    assert(config.selected >= -1 && config.selected < config.count);
    let region = v.regions.regions.len;
    v.lists.push(List<A> { config: config, region: region });
    record(v, Node<A> { name: str("list-", config.id), id: config.id, kind: LIST, rect: bounds,
        placed: true, enabled: config.enabled && config.count > 0 });
    at_scroll_viewport(v, bounds, config.scroll_id, config.count * config.stride) { F(); };
}
fn list<A,F>(v: View<A>&, name: const u8[:], config: ListConfig<A>) {
    at_list(v, bounds(v, name), config) { F(); };
}
// Only visible items need descriptors. Their identity may be unrelated to their index.
fn at_list_item<A>(v: View<A>&, name: const u8[:], id: u64, index: i64, rect: lab_ui_geometry::Rect,
    text: const u8[:] = "") {
    let list = containing_list(v, v.regions.current); assert(list >= 0);
    let config = v.lists[list].config; assert(index >= 0 && index < config.count);
    record(v, Node<A> { name: name, text: text, id: id, kind: LIST_ITEM, rect: rect,
        placed: true, enabled: config.enabled, value: config.selected == index, index: index });
}
fn record<A>(v: View<A>&, node: Node<A>) {
    assert(node.name.len > 0);
    if node.kind == BUTTON || node.kind == TOGGLE || node.kind == CHECKBOX || node.kind == FIELD || node.kind == LIST || node.kind == LIST_ITEM { assert(node.id != 0); }
    if node.id != 0 { for other in v.nodes { assert(other.id != node.id); } }
    var n: Node<A> = copy(node); n.viewport = v.regions.current; n.layer = v.layer; n.placement = n.rect;
    n.list = containing_list(v, n.viewport);
    if n.list >= 0 && n.kind != FIELD && n.kind != LIST { n.focusable = false; }
    if n.list >= 0 && n.id != 0 { n.enabled = n.enabled && v.lists[n.list].config.enabled; }
    v.nodes.push(n);
}
fn button<A>(v: View<A>&, name: const u8[:], id: u64, action: A, text: const u8[:],
    config: lab_ui_layout_engine::Config, primary: bool = false, enabled: bool = true) {
    leaf(v, name, config); record(v, Node<A> { name: name, text: text, id: id, kind: BUTTON, action: action, enabled: enabled, primary: primary });
}
fn toggle<A>(v: View<A>&, name: const u8[:], id: u64, action: A, text: const u8[:],
    value: bool, config: lab_ui_layout_engine::Config, enabled: bool = true) {
    leaf(v, name, config); record(v, Node<A> { name: name, text: text, id: id, kind: TOGGLE, action: action, enabled: enabled, value: value });
}
fn field<A>(v: View<A>&, name: const u8[:], id: u64, action: A, placeholder: const u8[:],
    config: lab_ui_layout_engine::Config, enabled: bool = true, limit: i64 = 240, clear_on_submit: bool = false) {
    assert(limit >= 0 && limit <= 512); field_state(v, id);
    leaf(v, name, config); record(v, Node<A> { name: name, text: placeholder, id: id, kind: FIELD, action: action, enabled: enabled, limit: limit, clear_on_submit: clear_on_submit });
}
fn label<A>(v: View<A>&, name: const u8[:], text: const u8[:], config: lab_ui_layout_engine::Config,
    font: i64 = 0, color: float4 = lab_ui_controls_components::Theme {}.text, centered: bool = false) {
    leaf(v, name, config); record(v, Node<A> { name: name, text: text, kind: LABEL, font: font, color: color, centered: centered });
}
fn paragraph<A>(v: View<A>&, name: const u8[:], text: const u8[:], config: lab_ui_layout_engine::Config,
    color: float4 = lab_ui_controls_components::Theme {}.muted) {
    let tag = (v.nodes.len + 1) as u32;
    box(v, name, config) { assert(lab_ui_layout_engine::tagged_text(v.layout, text, tag, lab_ui_layout_engine::WRAP_JAPANESE)); };
    record(v, Node<A> { name: name, kind: PARAGRAPH, color: color, text_tag: tag });
}
fn decoration<A>(v: View<A>&, name: const u8[:], kind: i32 = CARD, color: float4 = lab_ui_controls_components::Theme {}.surface) {
    record(v, Node<A> { name: name, kind: kind, color: color });
}
// Custom composition after solve: one rectangle supplies both painting and interaction.
fn at_field<A>(v: View<A>&, name: const u8[:], id: u64, action: A, rect: lab_ui_geometry::Rect,
    placeholder: const u8[:], enabled: bool = true, limit: i64 = 240, clear_on_submit: bool = false) {
    assert(v.solved && limit >= 0 && limit <= 512); field_state(v, id);
    record(v, Node<A> { name: name, text: placeholder, id: id, kind: FIELD, action: action,
        rect: rect, placed: true, enabled: enabled, limit: limit, clear_on_submit: clear_on_submit });
}
fn at_button<A>(v: View<A>&, name: const u8[:], id: u64, action: A, rect: lab_ui_geometry::Rect,
    text: const u8[:], enabled: bool = true, checkbox: bool = false, value: bool = false) {
    assert(v.solved); record(v, Node<A> { name: name, text: text, id: id, kind: if checkbox { CHECKBOX } else { BUTTON }, action: action, rect: rect, placed: true, enabled: enabled, value: value });
}
fn at_label<A>(v: View<A>&, name: const u8[:], rect: lab_ui_geometry::Rect, text: const u8[:],
    font: i64 = 0, color: float4 = lab_ui_controls_components::Theme {}.text, centered: bool = false) {
    assert(v.solved); record(v, Node<A> { name: name, text: text, kind: LABEL, rect: rect, placed: true, font: font, color: color, centered: centered });
}
fn at_chevron<A>(v: View<A>&, name: const u8[:], rect: lab_ui_geometry::Rect, expanded: bool,
    color: float4 = lab_ui_controls_components::Theme {}.muted) {
    assert(v.solved); record(v, Node<A> { name: name, kind: CHEVRON, rect: rect, placed: true, value: expanded, color: color });
}
// Ordered raw events for a composed control; the description never stores a callback.
fn at_custom<A>(v: View<A>&, name: const u8[:], id: u64, action: A, rect: lab_ui_geometry::Rect, enabled: bool = true, focusable: bool = true, accepts_text: bool = false, captures_tab: bool = false) {
    assert(v.solved && id != 0);
    record(v, Node<A> { name: name, id: id, kind: CUSTOM, action: action, rect: rect, placed: true, enabled: enabled, accepts_text: accepts_text, captures_tab: captures_tab, focusable: focusable });
}
// Place a completed text layout at a viewport origin. The context must remain
// valid and unchanged until paint; text stays in its native frame arena.
fn at_paragraph<A>(v: View<A>&, name: const u8[:], rect: lab_ui_geometry::Rect, layout: lab_ui_layout_engine::Context,
    tag: u32 = 0, color: float4 = lab_ui_controls_components::Theme {}.text) {
    assert(v.solved && layout.id != 0);
    record(v, Node<A> { name: name, kind: PARAGRAPH, rect: rect, placed: true, color: color, text_tag: tag, text_layout: layout });
}
fn at_decoration<A>(v: View<A>&, name: const u8[:], rect: lab_ui_geometry::Rect, kind: i32 = CARD,
    color: float4 = lab_ui_controls_components::Theme {}.surface) {
    assert(v.solved); record(v, Node<A> { name: name, kind: kind, rect: rect, placed: true, color: color });
}
fn solve<A>(v: View<A>&) { assert(!v.solved && lab_ui_layout_engine::finish(v.layout)); v.solved = true; }
fn prepare<A>(v: View<A>&) {
    if !v.solved { solve(v); }
    assert(v.regions.regions.len == v.viewports.len);
    for i in v.viewports.len {
        if v.viewports[i].name.len > 0 { v.regions.regions[i].bounds = bounds(v, v.viewports[i].name); }
    }
    lab_ui_layout_viewport::resolve(v.regions, v.screen);
    lab_ui_input_interaction::begin(v.input);
    for &n in v.nodes {
        n.rect = if n.placed { n.placement } else { bounds(v, n.name) };
        n.offset = lab_ui_layout_viewport::translation(v.regions, n.viewport);
        n.rect = lab_ui_layout_viewport::place(v.regions, n.viewport, n.rect);
        n.clip = lab_ui_layout_viewport::clip(v.regions, n.viewport);
        if n.id != 0 && n.layer == v.top_layer { lab_ui_input_interaction::register(v.input, n.id, lab_ui_geometry::intersect(n.rect, n.clip), n.enabled, n.focusable, n.kind != FIELD && n.kind != LIST && n.kind != CUSTOM, n.captures_tab); }
    }
    if v.drag.id != 0 && scroll_bar(v, v.drag.id) < 0 { v.drag.id = 0; }
}
fn reconcile<A>(v: View<A>&, pointer: float2, focused: bool, scale: f32 = 1.0) {
    // No event replay: removed/disabled focus and capture are cleared against the final view.
    lab_ui_input_interaction::resolve(v.input, [], pointer, focused, scale);
    focus_modal(v);
}
fn focus_modal<A>(v: View<A>&) {
    if v.top_layer != 0 && v.input.focused == 0 && v.input.has_focus {
        for hit in v.input.hits {
            if hit.enabled && hit.focusable && hit.bounds.w > 0.0 && hit.bounds.h > 0.0 {
                if v.input.focused == 0 || hit.id == v.initial_focus { v.input.focused = hit.id; }
                if hit.id == v.initial_focus { break; }
            }
        }
    }
}
fn scroll_bar<A>(v: View<A>&, id: u64) -> i64 {
    for i in v.nodes.len {
        let n = v.nodes[i];
        if n.layer == v.top_layer && n.kind == SCROLLBAR && v.viewports[n.scroll_region].scroll_id == id {
            let thumb = lab_ui_layout_scroll::thumb(scroll_state(v, id), n.rect, v.viewports[n.scroll_region].content_height);
            if !lab_ui_geometry::empty(thumb) && !lab_ui_geometry::empty(lab_ui_geometry::intersect(lab_ui_layout_scroll::track(n.rect), n.clip)) { return i; }
        }
    } -1
}
// Returns consumed and geometry-changed separately. Scrollbars have their own
// identity/capture namespace and cannot collide with application control IDs.
fn scrollbar_input<A>(v: View<A>&, event: gfx::Event, scale: f32) -> bool, bool {
    if event.kind == gfx::EVENT_FOCUS_LOST { v.drag.id = 0; return false, false; }
    if v.drag.id != 0 {
        if event.kind == gfx::EVENT_KEY && event.down && event.scancode == gfx::scancode("Escape") { v.drag.id = 0; return true, false; }
        if event.kind == gfx::EVENT_MOUSE_WHEEL { return true, false; }
        if event.kind == gfx::EVENT_MOUSE_MOTION || event.kind == gfx::EVENT_MOUSE_BUTTON {
            v.input.pointer = float2 { event.x / scale, event.y / scale };
            let bar = scroll_bar(v, v.drag.id);
            if bar < 0 || !v.input.has_focus { v.drag.id = 0; return true, false; }
            let node = v.nodes[bar]; let content = v.viewports[node.scroll_region].content_height;
            let before = scroll_state(v, v.drag.id).offset;
            if event.kind == gfx::EVENT_MOUSE_MOTION || event.button == gfx::MOUSE_LEFT {
                lab_ui_layout_scroll::drag(scroll_state(v, v.drag.id), v.input.pointer.y, v.drag.grab, node.rect, content);
            }
            let changed = before != scroll_state(v, v.drag.id).offset;
            if event.kind == gfx::EVENT_MOUSE_BUTTON && event.button == gfx::MOUSE_LEFT && !event.down { v.drag.id = 0; }
            return true, changed;
        }
    }
    if event.kind != gfx::EVENT_MOUSE_BUTTON || event.button != gfx::MOUSE_LEFT || !event.down || !v.input.has_focus { return false, false; }
    let pointer = float2 { event.x / scale, event.y / scale }; var i = v.nodes.len;
    while i > 0 {
        i--; let node = v.nodes[i]; if node.layer != v.top_layer { continue; }
        if node.kind == SCROLLBAR {
            let id = v.viewports[node.scroll_region].scroll_id; let content = v.viewports[node.scroll_region].content_height;
            let thumb = lab_ui_layout_scroll::thumb(scroll_state(v, id), node.rect, content);
            if lab_ui_geometry::empty(thumb) || !lab_ui_geometry::contains(lab_ui_geometry::intersect(lab_ui_layout_scroll::track(node.rect), node.clip), pointer) { continue; }
            v.input.pointer = pointer; v.input.captured = 0; let before = scroll_state(v, id).offset;
            if pointer.y >= thumb.y && pointer.y < thumb.y + thumb.h { v.drag = ScrollDrag { id: id, grab: (pointer.y - thumb.y) / thumb.h }; }
            else { lab_ui_layout_scroll::consume(scroll_state(v, id), if pointer.y < thumb.y { -node.rect.h } else { node.rect.h }, node.rect.h, content); }
            return true, before != scroll_state(v, id).offset;
        }
        if node.id != 0 && lab_ui_geometry::contains(lab_ui_geometry::intersect(node.rect, node.clip), pointer) { return false, false; }
    } return false, false;
}
fn focused_list<A>(v: const View<A>&, id: u64) -> i64 {
    for i in v.lists.len { if v.lists[i].config.id == id { return i; } } -1
}
fn key_motion(event: gfx::Event) -> lab_text_selection::Motion {
    if event.scancode == gfx::scancode("Up") { lab_text_selection::Motion.Previous }
    else if event.scancode == gfx::scancode("Down") { lab_text_selection::Motion.Next }
    else if event.scancode == gfx::scancode("Home") { lab_text_selection::Motion.First }
    else if event.scancode == gfx::scancode("End") { lab_text_selection::Motion.Last }
    else if event.scancode == gfx::scancode("PageUp") { lab_text_selection::Motion.PagePrevious }
    else if event.scancode == gfx::scancode("PageDown") { lab_text_selection::Motion.PageNext }
    else { lab_text_selection::Motion.None }
}
fn reveal_list<A>(v: View<A>&, list: i64, index: i64) -> bool {
    let description = v.lists[list]; let region = description.region; let config = description.config;
    let bounds = v.regions.regions[region].bounds;
    let before = scroll_state(v, config.scroll_id).offset; var changed = false;
    lab_ui_layout_scroll::reveal(scroll_state(v, config.scroll_id), index * config.stride, (index + 1) * config.stride, bounds.h, config.count * config.stride);
    changed = before != scroll_state(v, config.scroll_id).offset;
    var top = bounds.y + index * config.stride - scroll_state(v, config.scroll_id).offset;
    var bottom = top + config.stride; var parent = v.regions.regions[region].parent;
    while parent >= 0 {
        let ancestor = v.regions.regions[parent]; let viewport = v.viewports[parent];
        var shift = ancestor.offset.y;
        if viewport.scroll_id != 0 {
            let previous = scroll_state(v, viewport.scroll_id).offset;
            lab_ui_layout_scroll::reveal(scroll_state(v, viewport.scroll_id), top - ancestor.bounds.y, bottom - ancestor.bounds.y, ancestor.bounds.h, viewport.content_height);
            changed = changed || previous != scroll_state(v, viewport.scroll_id).offset;
            shift = -scroll_state(v, viewport.scroll_id).offset;
        }
        top += shift; bottom += shift; parent = ancestor.parent;
    } changed
}
fn route<A>(v: View<A>&, c: const lab_ui_render_scene::Canvas&, event: gfx::Event, scale: f32 = 1.0) -> Event<A>[>..] {
    var out: Event<A>[>..] = [];
    if event.kind==gfx::EVENT_CLOSE_REQUESTED { out.push(Event<A> {kind:CLOSE_REQUESTED,action:default<A>(),source:0,input:event}); return out; }
    // prepare is performed when the description changes; keep geometry unchanged otherwise.
    v.input.events.resize(0); v.input.targets.resize(0); v.input.clicks.resize(0); v.input.phase = 1;
    let previous_focus = v.input.focused;
    let previous_capture = v.input.captured;
    lab_ui_input_interaction::resolve(v.input, [event], v.input.pointer * scale, v.input.has_focus, scale);
    focus_modal(v);
    if event.kind==gfx::EVENT_KEY && v.input.composing && event.scancode!=gfx::scancode("Escape") { return out; }
    if event.kind == gfx::EVENT_KEY && event.down && v.input.has_focus && !v.input.composing {
        for binding in v.shortcuts {
            if (!event.repeat || binding.repeat) && binding.layer == v.top_layer && event.scancode == binding.scancode && event.mods == binding.mods {
                out.push(Event<A> { kind: ACTIVATE, action: binding.action, source: 0, input: event }); return out;
            }
        }
    }
    if event.kind == gfx::EVENT_MOUSE_BUTTON && event.button == gfx::MOUSE_LEFT && event.down && v.input.has_focus {
        let target = lab_ui_input_interaction::top(v.input, v.input.pointer);
        for node in v.nodes {
            if node.layer != v.top_layer || target == 0 || node.id != target || node.kind == FIELD { continue; }
            let list = if node.kind == LIST { focused_list(v, node.id) } else { node.list };
            if list < 0 { continue; }
            let config = v.lists[list].config; v.input.focused = config.id;
            for item in v.nodes {
                if item.kind == LIST_ITEM && item.list == list && lab_ui_geometry::contains(lab_ui_geometry::intersect(item.rect, item.clip), v.input.pointer) {
                    if config.hierarchical || config.selected != item.index { out.push(Event<A> { kind: SELECT, action: config.action, source: config.id, index: item.index, pointer: true }); }
                    break;
                }
            }
            break;
        }
    }
    for click in v.input.clicks {
        for n in v.nodes {
            if n.layer != v.top_layer || n.id != click { continue; }
            if n.kind == LIST_ITEM {
                let config = v.lists[n.list].config;
                if config.activate_on_click { out.push(Event<A> { kind: ACTIVATE, action: config.action, source: config.id, index: n.index, pointer: true }); }
            } else if n.kind != FIELD && n.kind != CUSTOM { out.push(Event<A> { kind: ACTIVATE, action: n.action, source: n.id }); }
        }
    }
    let list = focused_list(v, v.input.focused);
    if list >= 0 && event.kind == gfx::EVENT_KEY && event.down && v.input.has_focus {
        let description = v.lists[list]; let config = description.config;
        if previous_focus != config.id && event.scancode == gfx::scancode("Tab") {
            let index = max(0, config.selected);
            out.push(Event<A> { kind: SELECT, action: config.action, source: config.id, index: index, reveal: true });
        } else if event.mods == 0 {
            let motion = key_motion(event);
            if motion != lab_text_selection::Motion.None {
                let index = lab_text_selection::navigate(config.selected, config.count, motion,
                    lab_text_selection::page_rows(v.regions.regions[description.region].bounds.h, config.stride));
                out.push(Event<A> { kind: SELECT, action: config.action, source: config.id, index: index, reveal: true });
            } else if config.hierarchical && config.selected >= 0 && (event.scancode == gfx::scancode("Right") || event.scancode == gfx::scancode("Left")) {
                out.push(Event<A> { kind: if event.scancode == gfx::scancode("Right") { EXPAND } else { COLLAPSE }, action: config.action, source: config.id, index: config.selected, reveal: true });
            } else if !event.repeat && config.selected >= 0 && (event.scancode == gfx::scancode("Return") || event.scancode == gfx::scancode("Space")) {
                out.push(Event<A> { kind: ACTIVATE, action: config.action, source: config.id, index: config.selected });
            }
        }
    }
    for n in v.nodes {
        if n.layer != v.top_layer { continue; }
        if n.kind == CUSTOM && n.enabled {
            let pointer_event = event.kind == gfx::EVENT_MOUSE_MOTION || event.kind == gfx::EVENT_MOUSE_BUTTON;
            let releasing = event.kind == gfx::EVENT_MOUSE_BUTTON && event.button == gfx::MOUSE_LEFT && !event.down;
            let target = if releasing && previous_capture != 0 { previous_capture }
                else if pointer_event { if v.input.captured != 0 { v.input.captured } else { lab_ui_input_interaction::top(v.input, v.input.pointer) } } else { v.input.focused };
            if target == n.id || event.kind == gfx::EVENT_FOCUS_LOST {
                out.push(Event<A> { kind: INPUT, action: n.action, source: n.id, input: event });
            }
        }
        if n.kind != FIELD || !n.enabled { continue; }
        let result = lab_ui_controls_field::update(field_state(v, n.id), v.input, n.id, n.rect, c.fonts[0].font, scale, n.limit, n.clear_on_submit);
        for submission in result.submissions { out.push(Event<A> { kind: SUBMIT, action: n.action, source: n.id, text: submission.text }); }
        if result.changed && !result.submitted { out.push(Event<A> { kind: CHANGE, action: n.action, source: n.id }); }
        if field_state(v, n.id).rejected { out.push(Event<A> { kind: REJECTED, action: n.action, source: n.id }); }
        if field_state(v,n.id).rejected && event.kind==gfx::EVENT_TEXT_EDITING { v.input.composing=false; v.input.text_pending=false; }
    }
    out
}
// Route wheel movement to the innermost visible region, then pass only the remainder up.
fn wheel<A>(v: View<A>&, event: gfx::Event) -> bool {
    if event.kind != gfx::EVENT_MOUSE_WHEEL || !v.input.has_focus { return false; }
    var region: i64 = -1;
    var i = v.viewports.len;
    while i > 0 { i--; if v.viewports[i].layer == v.top_layer && lab_ui_geometry::contains(v.regions.regions[i].clip, v.input.pointer) { region = i; break; } }
    var remaining = -event.y * 44.0; var changed = false;
    while region >= 0 && v.viewports[region].layer == v.top_layer && remaining != 0.0 {
        let viewport = v.viewports[region]; let bounds = v.regions.regions[region].bounds;
        if viewport.scroll_id != 0 {
            let before = scroll_state(v, viewport.scroll_id).offset;
            remaining = lab_ui_layout_scroll::consume(scroll_state(v, viewport.scroll_id), remaining, bounds.h, viewport.content_height);
            changed = changed || before != scroll_state(v, viewport.scroll_id).offset;
        }
        region = v.regions.regions[region].parent;
    }
    changed
}
fn paint_nodes<A>(v: View<A>&, c: lab_ui_render_scene::Canvas&, overlays: bool, filtered: bool) {
    let theme = lab_ui_controls_components::Theme {};
    // Painting never dispatches actions or toggles a value.
    v.input.clicks.resize(0);
    for n in v.nodes {
        if filtered && (n.layer != 0) != overlays { continue; }
        lab_ui_render_scene::push_clip(c, n.clip);
        if n.kind == BUTTON { lab_ui_controls_components::button(c, v.input, n.id, n.rect, n.text, theme, n.primary, n.enabled); }
        else if n.kind == TOGGLE {
            lab_ui_render_scene::label(c, 0, lab_ui_geometry::rect(n.rect.x, n.rect.y, n.rect.w - 60.0, n.rect.h), n.text, if n.enabled { theme.text } else { theme.muted });
            lab_ui_controls_components::paint_toggle(c, v.input, n.id, n.rect, n.value, theme, n.enabled);
        } else if n.kind == CHECKBOX { lab_ui_controls_components::checkbox(c, v.input, n.id, n.rect, n.value, theme, n.enabled); }
        else if n.kind == FIELD { lab_ui_controls_field::paint(c, field_state(v, n.id), v.input, n.id, n.rect, n.text, n.enabled); }
        else if n.kind == LABEL { lab_ui_render_scene::label(c, n.font, n.rect, n.text, n.color, n.centered); }
        else if n.kind == CHEVRON { lab_ui_controls_components::chevron(c, n.rect, n.value, n.color); }
        else if n.kind == PARAGRAPH {
            let layout = if n.text_layout.id != 0 { n.text_layout } else { v.layout };
            let origin = if n.placed { float2 { n.rect.x, n.rect.y } } else { n.offset };
            for i in lab_ui_layout_engine::line_count(layout) {
                if lab_ui_layout_engine::line_tag(layout, i) != n.text_tag { continue; }
                let line = lab_ui_layout_engine::line(layout, i);
                lab_ui_render_scene::text(c, 0, line.bounds.x + origin.x, line.bounds.y + origin.y, line.text, n.color);
            }
        }
        else if n.kind == CARD { lab_ui_controls_components::card(c, n.rect, theme); }
        else if n.kind == FILL { lab_ui_render_scene::fill(c, n.rect, n.color); }
        else if n.kind == LIST_ITEM { lab_ui_controls_components::list_item(c, v.input, n.id, n.rect, n.text, n.value, v.input.focused == v.lists[n.list].config.id, n.enabled, theme, v.lists[n.list].config.framed); }
        else if n.kind == SCROLLBAR {
            let viewport = v.viewports[n.scroll_region]; var thumb = lab_ui_layout_scroll::thumb(scroll_state(v, viewport.scroll_id), n.rect, viewport.content_height);
            let hovered = lab_ui_geometry::contains(lab_ui_geometry::intersect(lab_ui_layout_scroll::track(n.rect), n.clip), v.input.pointer) && v.input.has_focus;
            if !lab_ui_geometry::empty(thumb) {
                if hovered || v.drag.id == viewport.scroll_id { thumb.x -= 2.0; thumb.w += 4.0; }
                lab_ui_render_scene::fill(c, thumb, if v.drag.id == viewport.scroll_id { theme.accent } else if hovered { theme.muted } else { theme.border }, 3.0);
            }
        }
        lab_ui_render_scene::pop_clip(c);
    }
}
// Applications with custom content paint it between frame and paint_overlays.
fn paint<A>(v: View<A>&, c: lab_ui_render_scene::Canvas&) { paint_nodes(v, c, false, v.defer_overlays); }
fn paint_overlays<A>(v: View<A>&, c: lab_ui_render_scene::Canvas&) { assert(v.defer_overlays); paint_nodes(v, c, true, true); }
// Build and Reduce are static, immediately invoked functions/blocks, never stored.
// Reduce returns whether geometry/visibility changed. Every input event is consumed once.
fn frame<A,Build,Reduce>(v: View<A>&, c: lab_ui_render_scene::Canvas&, events: const gfx::Event[:],
    pointer: float2, focused: bool, scale: f32 = 1.0) {
    gfx::text_transactions(true); Build(); prepare(v);
    // Samples describe the end of the batch. Ordered input must start from
    // the previous pointer/focus, so an early wheel/key cannot see later motion/focus.
    if events.len == 0 { reconcile(v, pointer, focused, scale); }
    else { reconcile(v, v.input.pointer * scale, v.input.has_focus, scale); }
    sync_text_owner(v); var discard=false;
    for event in events {
        if discard && (event.kind==gfx::EVENT_TEXT_COMMIT || event.kind==gfx::EVENT_TEXT_EDITING) { continue; }
        let was_pending=v.input.text_pending; let owner=v.text_owner;
        let consumed, scrolling = scrollbar_input(v, event, scale);
        if consumed {
            if scrolling { Build(); prepare(v); reconcile(v, v.input.pointer * scale, v.input.has_focus, scale); }
            continue;
        }
        let actions = route(v, c, event, scale); var changed = wheel(v, event);
        for action in actions { changed = Reduce(action) || changed || action.kind == SELECT; }
        if changed {
            Build(); prepare(v); var revealed = false;
            // Reveal only the model's accepted selection; a reducer may reject
            // or redirect a request. Pointer selection keeps press/release geometry stable.
            for action in actions {
                if action.kind == SELECT && action.reveal && v.input.focused == action.source {
                    let list = focused_list(v, action.source);
                    if list >= 0 && v.lists[list].config.selected == action.index { revealed = reveal_list(v, list, action.index) || revealed; }
                }
            }
            if revealed { Build(); prepare(v); }
            reconcile(v, v.input.pointer * scale, v.input.has_focus, scale);
        }
        sync_text_owner(v); if was_pending && owner!=v.text_owner { discard=true; }
        if was_pending && ((event.kind==gfx::EVENT_KEY && event.down && event.scancode==gfx::scancode("Escape")) || (event.kind==gfx::EVENT_MOUSE_BUTTON && event.down)) {
            v.input.composing=false; v.input.text_pending=false; gfx::clear_composition(); discard=true;
        }
    }
    Build(); prepare(v); reconcile(v, pointer, v.input.has_focus, scale); paint(v, c);
    sync_text_owner(v); gfx::text_input(v.text_owner!=0);
}
fn sync_text_owner<A>(v: View<A>&) {
    var owner: u64=0;
    if v.input.has_focus { for n in v.nodes { if (n.kind==FIELD || n.accepts_text) && n.enabled && n.layer==v.top_layer && n.id==v.input.focused { owner=n.id; } } }
    if owner!=v.text_owner {
        if v.text_owner!=0 { gfx::clear_composition(); } v.input.composing=false; v.input.text_pending=false; v.text_owner=owner;
        for i in v.fields.entries.len { lab_ui_input_composition::clear(v.fields.entries[i].value.composition); }
    }
}
