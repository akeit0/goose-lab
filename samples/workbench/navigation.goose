// App navigation stays with the sample; reusable controls remain in lab.ui.
namespace app_workbench_navigation;
import lab.ui.view;
import lab.ui.layout.engine;
fn header<A>(view: lab_ui_view::View<A>&, name: const u8[:], changes: bool, editor: A, git: A, open_file: A, can_open: bool = false) {
    lab_ui_view::box(view, "workbench-header", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
        lab_ui_view::label(view, "workbench-name", name, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
        lab_ui_view::button(view, "workbench-editor", 900001, editor, "Editor", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(72.0), height: lab_ui_layout_engine::grow() }, !changes);
        lab_ui_view::button(view, "workbench-changes", 900002, git, "Git", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(56.0), height: lab_ui_layout_engine::grow() }, changes);
        if changes { lab_ui_view::button(view, "workbench-open-file", 900003, open_file, "Edit file", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(86.0), height: lab_ui_layout_engine::grow() }, false, can_open); }
    };
}

import std;
import gfx;
import lab.ui.geometry;
import lab.ui.controls.components;
import lab.ui.overlays.modal;
import lab.ui.input.shortcuts;
struct Tab { path: u8[..512], name: u8[..260], cursor: i64 = 0, anchor: i64 = 0, vertical: f32 = 0.0, horizontal: f32 = 0.0 }
struct Tabs { items: Tab[..16] = [], active: i64 = -1 }
fn sidebar_width(width: f32) -> f32 { min(264.0, max(176.0, width * 0.23)) }
// All pages describe the same shell; the sample supplies the sidebar and content.
fn shell<A,F>(view: lab_ui_view::View<A>&, width: f32, name: const u8[:], changes: bool, searching: bool,
    files_action: A, git_action: A, search_action: A, help_action: A, panel_name: const u8[:], status: const u8[:], history: bool = false) {
    let theme = lab_ui_controls_components::Theme {};
    lab_ui_view::box(view, "workbench-root", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }) {
        lab_ui_view::box(view, "workbench-header", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(30.0), padding: lab_ui_layout_engine::padding(4) }) {
            lab_ui_view::decoration(view, "workbench-header", lab_ui_view::FILL, theme.surface);
            lab_ui_view::label(view, "workbench-name", str(name, "  /  Goose Lab"), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, 0, theme.muted);
            lab_ui_view::button(view, "workbench-help", 900005, help_action, "Help", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(52.0), height: lab_ui_layout_engine::grow() }, false, true, true);
        };
        lab_ui_view::box(view, "workbench-body", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }) {
            lab_ui_view::box(view, "activity", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(44.0), height: lab_ui_layout_engine::grow(), gap: 4 }) {
                lab_ui_view::decoration(view, "activity", lab_ui_view::FILL, theme.background);
                lab_ui_view::button(view, "workbench-editor", 900001, files_action, "Files", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(40.0) }, !changes && !searching, true, true);
                lab_ui_view::button(view, "workbench-search", 900004, search_action, "Find", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(40.0) }, !changes && searching, true, true);
                lab_ui_view::button(view, "workbench-changes", 900002, git_action, "Git", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(40.0) }, changes, true, true);
            };
            if panel_name == "git-sidebar" {
                lab_ui_view::box(view, panel_name, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(sidebar_width(width)), height: lab_ui_layout_engine::grow() }) {
                    lab_ui_view::decoration(view, panel_name, lab_ui_view::FILL, theme.surface);
                    lab_ui_view::leaf(view, "git-tools", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(94.0) });
                    if history {
                        lab_ui_view::leaf(view, "history-tools", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(26.0) });
                        lab_ui_view::leaf(view, "commits", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(180.0) });
                    }
                    lab_ui_view::leaf(view, "files", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
                };
            } else {
                lab_ui_view::leaf(view, panel_name, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(sidebar_width(width)), height: lab_ui_layout_engine::grow() });
                lab_ui_view::decoration(view, panel_name, lab_ui_view::FILL, theme.surface);
            }
            lab_ui_view::box(view, "workbench-content", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }) {
                lab_ui_view::leaf(view, "tab-strip", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0) });
                lab_ui_view::decoration(view, "tab-strip", lab_ui_view::FILL, theme.surface);
                F();
            };
        };
        lab_ui_view::box(view, "workbench-status", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(24.0), padding: lab_ui_layout_engine::padding(4) }) {
            lab_ui_view::decoration(view, "workbench-status", lab_ui_view::FILL, theme.surface);
            lab_ui_view::label(view, "position", status, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, 0, theme.muted);
        };
    };
}
fn tabs<A>(view: lab_ui_view::View<A>&, tabs: const Tabs&, select: A, close: A, dirty: bool, diff: bool = false, diff_name: const u8[:] = [], diff_action: A = default<A>(), previous: A = default<A>(), next: A = default<A>()) {
    let r = lab_ui_view::bounds(view, "tab-strip");
    lab_ui_view::at_viewport(view, r) {
        // Bound visible labels and keep the active file in view on narrow windows.
        var x = r.x;
        let tw: f32 = 132.0;
        let overflow = tabs.items.len * tw + (if diff { 160.0 } else { 0.0 }) > r.w;
        let reserve: f32 = if overflow { 48.0 } else { 0.0 };
        let count = max(1, ((r.w - reserve - (if diff { 160.0 } else { 0.0 })) / tw) as i64);
        let first = max(0, tabs.active - count + 1);
        for i in first..min(tabs.items.len, first + count) {
            let active = !diff && i == tabs.active;
            lab_ui_view::record(view, lab_ui_view::Node<A> { name: str("file-tab-", i), text: str(if i == tabs.active && dirty { "● " } else { "" }, tabs.items[i].name), id: 920000 + i as u64 * 2, kind: lab_ui_view::BUTTON, action: select, rect: lab_ui_geometry::rect(x, r.y, tw - 22.0, r.h), placed: true, primary: active, flat: true });
            lab_ui_view::at_button(view, str("close-tab-", i), 920001 + i as u64 * 2, close, lab_ui_geometry::rect(x + tw - 22.0, r.y, 22.0, r.h), "×", true, false, false, true);
            x += tw;
        }
        if diff {
            lab_ui_view::record(view, lab_ui_view::Node<A> { name: "diff-tab", text: diff_name, id: 919999, kind: lab_ui_view::BUTTON, action: diff_action, rect: lab_ui_geometry::rect(x, r.y, max(132.0, min(220.0, r.w - reserve - (x - r.x))), r.h), placed: true, primary: true, flat: true });
        }
        if overflow {
            lab_ui_view::at_button(view, "tabs-previous", 919996, previous, lab_ui_geometry::rect(r.x + r.w - 48.0, r.y, 24.0, r.h), "‹", tabs.items.len > 1, false, false, true);
            lab_ui_view::at_button(view, "tabs-next", 919997, next, lab_ui_geometry::rect(r.x + r.w - 24.0, r.y, 24.0, r.h), "›", tabs.items.len > 1, false, false, true);
        }
    };
}
fn help<A>(view: lab_ui_view::View<A>&, state: const lab_ui_overlays_modal::State&, dismiss: A) {
    if !state.opened { return; }
    let w = min(540.0, view.screen.w - 24.0); let h: f32 = 450.0;
    let panel = lab_ui_geometry::rect((view.screen.w - w) / 2.0, max(8.0, (view.screen.h - h) / 2.0), w, h);
    let theme = lab_ui_controls_components::Theme {}; let primary = lab_ui_input_shortcuts::primary();
    lab_ui_overlays_modal::at_panel(view, 930000, 930002, panel, dismiss) {
        lab_ui_view::shortcut(view, "Escape", 0, dismiss); lab_ui_view::shortcut(view, "F1", 0, dismiss);
        lab_ui_view::at_label(view, "help-title", lab_ui_geometry::rect(panel.x + 16.0, panel.y + 12.0, panel.w - 32.0, 28.0), "Workbench / Keyboard shortcuts");
        var row: i64 = 0;
        fn entry(label: const u8[:], key: const u8[:], mods: i32) {
            let y = panel.y + 54.0 + row * 25.0;
            lab_ui_view::at_label(view, str("help-action-", row), lab_ui_geometry::rect(panel.x + 16.0, y, panel.w * 0.58, 25.0), label);
            lab_ui_view::at_label(view, str("help-key-", row), lab_ui_geometry::rect(panel.x + panel.w * 0.62, y, panel.w * 0.38 - 16.0, 25.0), lab_ui_input_shortcuts::hint(key, mods), 0, theme.muted); row++;
        }
        entry("Save file", "S", primary); entry("Open file path", "O", primary);
        entry("Undo", "Z", primary); entry("Redo (with Shift)", "Z", primary | gfx::MOD_SHIFT);
        entry("Explorer / Git sidebar", "E / G", primary | gfx::MOD_SHIFT);
        entry("Find in files", "F", primary | gfx::MOD_SHIFT); entry("Next / previous tab", "Tab / Shift+Tab", gfx::MOD_CTRL);
        entry("Close active file tab", "W", primary); entry("Select all / copy / paste", "A / C / V", primary);
        entry("Git: working / staged / history", "1 / 2 / 3", primary); entry("Git: find in displayed text", "F", primary);
        entry("Git: next / previous hunk", "F7 / Shift+F7", 0); entry("Git: command palette", "K", primary);
        lab_ui_view::at_label(view, "help-platform", lab_ui_geometry::rect(panel.x + 16.0, panel.y + 387.0, panel.w - 100.0, 28.0), "F1: Help · macOS: Cmd · Windows/Linux: Ctrl", 0, theme.muted);
        lab_ui_view::at_button(view, "help-close", 930002, dismiss, lab_ui_geometry::rect(panel.x + panel.w - 76.0, panel.y + h - 44.0, 60.0, 28.0), "Close", true, false, false, true);
    };
}
