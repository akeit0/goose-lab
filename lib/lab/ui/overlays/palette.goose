namespace lab_ui_overlays_palette;
import std;
import gfx;
import lab.ui.command;
import lab.ui.overlays.modal;
import lab.ui.view;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.text.selection;
import lab.ui.geometry;
import lab.ui.controls.components;
struct State { modal: lab_ui_overlays_modal::State = lab_ui_overlays_modal::State {}, selection: lab_ui_command::State = lab_ui_command::State {} }
struct Config<A> { base: u64, scroll_id: u64, query: A, choose: A, dismiss: A, meta_font: i64 = 0 }
struct Result<A> { changed: bool = false, invoked: bool = false, action: A = default<A>() }
fn hint<A>(command: const lab_ui_command::Command<A>&) -> u8[>..] {
    if command.key.len == 0 { return str(""); }
    str(if (command.mods & gfx::MOD_CTRL) != 0 { "Ctrl+" } else { "" },
        if (command.mods & gfx::MOD_ALT) != 0 { "Alt+" } else { "" },
        if (command.mods & gfx::MOD_SHIFT) != 0 { "Shift+" } else { "" },
        if (command.mods & gfx::MOD_GUI) != 0 { "Super+" } else { "" }, command.key)
}
fn bindings<A>(view: lab_ui_view::View<A>&, catalog: const lab_ui_command::Catalog<A>&) {
    assert(catalog.code == lab_ui_command::OK);
    for command in catalog.items { if command.enabled && command.key.len > 0 { lab_ui_view::shortcut(view, command.key, command.mods, command.action); } }
}
fn open<A>(view: lab_ui_view::View<A>&, state: State&, config: Config<A>) {
    assert(config.base > 0 && config.base <= 18446744073709551598 && config.scroll_id != 0);
    lab_ui_controls_field::set(lab_ui_view::field_state(view, config.base + 2), "");
    lab_ui_view::scroll_state(view, config.scroll_id).offset = 0.0; state.selection.current = 0;
    lab_ui_overlays_modal::open(view, state.modal, config.base + 2);
}
fn panel(screen: lab_ui_geometry::Rect) -> lab_ui_geometry::Rect {
    let w = max(0.0, min(640.0, screen.w - 32.0)); let h = max(0.0, min(420.0, screen.h - 32.0));
    lab_ui_geometry::rect((screen.w - w) * 0.5, max(16.0, min(88.0, (screen.h - h) * 0.5)), w, h)
}
fn list_rect(screen: lab_ui_geometry::Rect) -> lab_ui_geometry::Rect {
    let r = panel(screen); lab_ui_geometry::rect(r.x + 12.0, r.y + 94.0, max(0.0, r.w - 24.0), max(0.0, r.h - 130.0))
}
fn show<A>(view: lab_ui_view::View<A>&, state: State&, config: Config<A>, catalog: const lab_ui_command::Catalog<A>&) {
    if !state.modal.opened { return; }
    assert(config.base > 0 && config.base <= 18446744073709551598 && config.scroll_id != 0 && catalog.code == lab_ui_command::OK);
    let rows = lab_ui_command::project(catalog, lab_ui_view::field_state(view, config.base + 2).text);
    lab_ui_command::normalize(catalog, state.selection, rows);
    let selected = lab_ui_command::current(catalog, state.selection, rows);
    let r = panel(view.screen); let list = list_rect(view.screen); let theme = lab_ui_controls_components::Theme {};
    lab_ui_overlays_modal::at_panel(view, config.base, config.base + 2, r, config.dismiss) {
        lab_ui_view::shortcut(view, "Escape", 0, config.dismiss); lab_ui_view::shortcut(view, "K", gfx::MOD_CTRL, config.dismiss);
        for key in ["Up", "Down", "PageUp", "PageDown"] { lab_ui_view::shortcut(view, key, 0, config.choose, true); }
        lab_ui_view::at_label(view, "commands-title", lab_ui_geometry::rect(r.x + 16.0, r.y + 10.0, max(0.0, r.w - 128.0), 24.0), "Commands");
        lab_ui_view::at_label(view, "commands-toggle", lab_ui_geometry::rect(r.x + max(16.0, r.w - 92.0), r.y + 10.0, 76.0, 24.0), "Ctrl+K", config.meta_font, theme.muted);
        lab_ui_view::record(view, lab_ui_view::Node<A> { name: "commands-query", text: "Search commands…", id: config.base + 2, kind: lab_ui_view::FIELD, action: config.query,
            rect: lab_ui_geometry::rect(r.x + 16.0, r.y + 42.0, max(0.0, r.w - 32.0), 40.0), placed: true });
        lab_ui_view::at_list(view, list, lab_ui_view::ListConfig<A> { id: config.base + 3, scroll_id: config.scroll_id, count: rows.items.len, stride: 48.0,
            selected: selected, action: config.choose, framed: false, activate_on_click: true }) {
            let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(view, config.scroll_id), list.h, 48.0, rows.items.len);
            for index in range.first..range.end {
                let command = catalog.items[rows.items[index]];
                assert(command.id <= 18446744073709551615 - config.base - 16);
                let row = lab_ui_geometry::rect(list.x + 4.0, list.y + index * 48.0 + 2.0, max(0.0, list.w - 22.0), 44.0);
                lab_ui_view::at_list_item(view, str("command-", command.id), config.base + 16 + command.id, index, row);
                lab_ui_view::at_label(view, str("command-title-", command.id), lab_ui_geometry::rect(row.x + 10.0, row.y + 1.0, max(0.0, row.w - 166.0), 23.0), command.title, 0, if command.enabled { theme.text } else { theme.muted });
                lab_ui_view::at_label(view, str("command-key-", command.id), lab_ui_geometry::rect(row.x + max(0.0, row.w - 144.0), row.y + 1.0, 134.0, 23.0), hint(command), config.meta_font, theme.muted);
                let description: const u8[:] = if !command.enabled { if command.reason.len > 0 { command.reason[..] } else { "Unavailable" } } else { command.description[..] };
                lab_ui_view::at_label(view, str("command-description-", command.id), lab_ui_geometry::rect(row.x + 10.0, row.y + 23.0, max(0.0, row.w - 20.0), 18.0), description, config.meta_font, theme.muted);
            }
        };
        if rows.items.len == 0 { lab_ui_view::at_label(view, "commands-empty", list, "No matching commands", config.meta_font, theme.muted, true); }
        lab_ui_view::at_label(view, "commands-footer", lab_ui_geometry::rect(r.x + 16.0, r.y + r.h - 29.0, r.w - 32.0, 20.0), "↑↓ choose · Enter run · Esc close", config.meta_font, theme.muted);
    };
}
fn reduce<A>(view: lab_ui_view::View<A>&, state: State&, config: Config<A>, catalog: const lab_ui_command::Catalog<A>&, event: lab_ui_view::Event<A>) -> Result<A> {
    var result = Result<A> {}; if !state.modal.opened { return result; }
    if event.action == config.dismiss {
        if event.kind == lab_ui_view::ACTIVATE || lab_ui_overlays_modal::backdrop(event) { lab_ui_overlays_modal::close(view, state.modal); result.changed = true; }
        return result;
    }
    if event.action != config.query && event.action != config.choose { return result; }
    let rows = lab_ui_command::project(catalog, lab_ui_view::field_state(view, config.base + 2).text);
    lab_ui_command::normalize(catalog, state.selection, rows);
    if event.action == config.query && event.kind == lab_ui_view::CHANGE {
        lab_ui_view::scroll_state(view, config.scroll_id).offset = 0.0; result.changed = true; return result;
    }
    if event.action == config.choose {
        var index = event.index;
        if event.source == 0 && event.kind == lab_ui_view::ACTIVATE {
            index = lab_text_selection::navigate(lab_ui_command::current(catalog, state.selection, rows), rows.items.len, lab_ui_view::key_motion(event.input), lab_text_selection::page_rows(list_rect(view.screen).h, 48.0));
        }
        if index >= 0 && index < rows.items.len {
            state.selection.current = catalog.items[rows.items[index]].id;
            if !event.pointer { lab_ui_layout_scroll::reveal(lab_ui_view::scroll_state(view, config.scroll_id), index * 48.0, (index + 1) * 48.0, list_rect(view.screen).h, rows.items.len * 48.0); }
        }
        if event.source != 0 && (index < 0 || index >= rows.items.len) { return result; }
        result.changed = true;
        if event.kind != lab_ui_view::ACTIVATE || event.source == 0 { return result; }
    } else if event.kind != lab_ui_view::SUBMIT { return result; }
    let action, allowed = lab_ui_command::resolve(catalog, state.selection.current);
    if allowed {
        lab_ui_overlays_modal::close(view, state.modal); result.changed = true; result.invoked = true; result.action = action;
    } result
}
