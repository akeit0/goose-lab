namespace lab_ui_controls_components;
import vec;
import lab.ui.geometry;
import lab.ui.render.scene;
import lab.ui.input.interaction;
struct Theme {
    background: float4 = float4 { 0.045, 0.055, 0.075, 1.0 },
    surface: float4 = float4 { 0.075, 0.090, 0.120, 1.0 },
    border: float4 = float4 { 0.16, 0.19, 0.24, 1.0 },
    text: float4 = float4 { 0.91, 0.93, 0.97, 1.0 },
    muted: float4 = float4 { 0.51, 0.57, 0.67, 1.0 },
    accent: float4 = float4 { 0.43, 0.40, 0.96, 1.0 },
}
fn button(c: lab_ui_render_scene::Canvas&, s: const lab_ui_input_interaction::State&, id: u64, r: lab_ui_geometry::Rect,
    label: const u8[:], theme: Theme = Theme {}, primary: bool = false, enabled: bool = true, flat: bool = false) -> bool {
    let hovered = s.hovered == id && enabled;
    let down = s.captured == id && hovered;
    if flat {
        if primary || hovered || (s.focused == id && enabled) { lab_ui_render_scene::fill(c, r, if primary { theme.surface } else { theme.border }); }
        if primary { lab_ui_render_scene::fill(c, lab_ui_geometry::rect(r.x, r.y + r.h - 2.0, r.w, 2.0), theme.accent); }
        lab_ui_render_scene::label(c, 0, r, label, if enabled { theme.text } else { theme.muted }, true);
        return enabled && lab_ui_input_interaction::clicked(s, id);
    }
    var color = if primary { theme.accent } else { theme.surface };
    if hovered { color.x += 0.05; color.y += 0.05; color.z += 0.05; }
    if down { color.x *= 0.85; color.y *= 0.85; color.z *= 0.85; }
    if !enabled { color = theme.surface; }
    if s.focused == id && enabled { lab_ui_render_scene::fill(c, lab_ui_geometry::rect(r.x - 3.0, r.y - 3.0, r.w + 6.0, r.h + 6.0), theme.accent, 11.0); }
    lab_ui_render_scene::border(c, r, color, if primary { color } else { theme.border }, 8.0);
    lab_ui_render_scene::label(c, 0, r, label, if enabled { theme.text } else { theme.muted }, true);
    enabled && lab_ui_input_interaction::clicked(s, id)
}
fn toggle(c: lab_ui_render_scene::Canvas&, s: const lab_ui_input_interaction::State&, id: u64, r: lab_ui_geometry::Rect,
    value: bool, theme: Theme = Theme {}) -> bool {
    let current = if lab_ui_input_interaction::clicked(s, id) { !value } else { value };
    paint_toggle(c, s, id, r, current, theme); current
}
fn paint_toggle(c: lab_ui_render_scene::Canvas&, s: const lab_ui_input_interaction::State&, id: u64, r: lab_ui_geometry::Rect,
    value: bool, theme: Theme = Theme {}, enabled: bool = true) {
    let track = lab_ui_geometry::rect(r.x + r.w - 44.0, r.y + (r.h - 24.0) / 2.0, 44.0, 24.0);
    if s.focused == id && enabled { lab_ui_render_scene::fill(c, lab_ui_geometry::rect(track.x - 3.0, track.y - 3.0, 50.0, 30.0), theme.border, 15.0); }
    lab_ui_render_scene::fill(c, track, if value && enabled { theme.accent } else { theme.border }, 12.0);
    lab_ui_render_scene::fill(c, lab_ui_geometry::rect(track.x + (if value { 23.0 } else { 3.0 }), track.y + 3.0, 18.0, 18.0), theme.text, 9.0);
}
fn card(c: lab_ui_render_scene::Canvas&, r: lab_ui_geometry::Rect, theme: Theme = Theme {}) {
    lab_ui_render_scene::fill(c, lab_ui_geometry::rect(r.x, r.y + 4.0, r.w, r.h), float4 { 0.0, 0.0, 0.0, 0.15 }, 14.0);
    lab_ui_render_scene::border(c, r, theme.surface, theme.border, 14.0);
}
// Geometry avoids depending on a font's disclosure-triangle coverage.
fn chevron(c: lab_ui_render_scene::Canvas&, r: lab_ui_geometry::Rect, expanded: bool, color: float4) {
    let x = r.x + r.w / 2.0; let y = r.y + r.h / 2.0;
    let a = if expanded { float2 { x - 3.0, y - 1.5 } } else { float2 { x - 1.5, y - 3.0 } };
    let b = if expanded { float2 { x, y + 1.5 } } else { float2 { x + 1.5, y } };
    let d = if expanded { float2 { x + 3.0, y - 1.5 } } else { float2 { x - 1.5, y + 3.0 } };
    lab_ui_render_scene::stroke(c, a, b, color, 1.5); lab_ui_render_scene::stroke(c, b, d, color, 1.5);
}
fn list_item(c: lab_ui_render_scene::Canvas&, s: const lab_ui_input_interaction::State&, id: u64, r: lab_ui_geometry::Rect,
    label: const u8[:], selected: bool, focused: bool, enabled: bool = true, theme: Theme = Theme {}, framed: bool = true) {
    var color = theme.surface;
    if selected && enabled { color = float4 { 0.13, 0.12, 0.25, 1.0 }; }
    if s.hovered == id && enabled { color.x += 0.025; color.y += 0.025; color.z += 0.025; }
    if framed {
        lab_ui_render_scene::border(c, r, color, if selected && enabled { theme.accent } else { theme.border }, 8.0,
            if selected && focused && enabled { 2.0 } else { 1.0 });
    } else if enabled && (selected || s.hovered == id) {
        if selected && focused { color = float4 { 0.19, 0.17, 0.34, 1.0 }; }
        lab_ui_render_scene::fill(c, r, color);
    }
    if label.len > 0 {
        let text_rect = if framed { r } else { lab_ui_geometry::rect(r.x + 12.0, r.y, max(0.0, r.w - 24.0), r.h) };
        lab_ui_render_scene::label(c, 0, text_rect, label, if enabled { theme.text } else { theme.muted }, framed);
    }
}

fn checkbox(c: lab_ui_render_scene::Canvas&, s: const lab_ui_input_interaction::State&, id: u64, r: lab_ui_geometry::Rect,
    value: bool, theme: Theme = Theme {}, enabled: bool = true) {
    let tick = lab_ui_geometry::rect(r.x + 6.0, r.y + 12.0, 24.0, 24.0);
    if s.focused == id && enabled { lab_ui_render_scene::fill(c, lab_ui_geometry::rect(tick.x - 3.0, tick.y - 3.0, 30.0, 30.0), theme.accent, 9.0); }
    lab_ui_render_scene::border(c, tick, if value && enabled { theme.accent } else { theme.surface }, if enabled && (value || s.hovered == id) { theme.accent } else { theme.border }, 6.0);
    if value {
        let joint = float2 { tick.x + 10.0, tick.y + 17.0 };
        lab_ui_render_scene::stroke(c, float2 { tick.x + 5.0, tick.y + 12.0 }, joint, if enabled { theme.text } else { theme.muted });
        lab_ui_render_scene::stroke(c, joint, float2 { tick.x + 19.0, tick.y + 7.0 }, if enabled { theme.text } else { theme.muted });
    }
}
