// Virtual tree rows on the shared list protocol. Reducers, not painting, own state.
namespace lab_ui_views_tree;
import std;
import lab.collections.tree;
import lab.ui.view;
import lab.ui.geometry;
import lab.ui.layout.scroll;
import lab.ui.controls.components;
struct Config<A> {
    id: u64, scroll_id: u64, row_base: u64, action: A,
    enabled: bool = true, blocked: bool = false, stride: f32 = 28.0, indent: f32 = 16.0, trailing: f32 = 0.0,
}
struct Changed { changed: bool = false, leaf: i64 = -1 }
fn at_tree<A,F>(view: lab_ui_view::View<A>&, bounds: lab_ui_geometry::Rect, config: Config<A>,
    tree: const lab_collections_tree::Tree&, state: const lab_collections_tree::State&, rows: const lab_collections_tree::Rows&) {
    assert(config.row_base > 0 && config.stride >= 12.0 && config.indent >= 0.0 && config.trailing >= 0.0);
    let theme = lab_ui_controls_components::Theme {};
    lab_ui_view::at_list(view, bounds, lab_ui_view::ListConfig<A> { id: config.id, scroll_id: config.scroll_id, count: rows.items.len,
        stride: config.stride, selected: lab_collections_tree::current(tree, state, rows), action: config.action, enabled: config.enabled, blocked: config.blocked, hierarchical: true, framed: false }) {
        let range = lab_ui_layout_scroll::visible(lab_ui_view::scroll_state(view, config.scroll_id), bounds.h, config.stride, rows.items.len);
        for i in range.first..range.end {
            let row = rows.items[i]; let node = tree.nodes[row.node]; let prefix = str("tree-", config.id, "-");
            let r = lab_ui_geometry::rect(bounds.x + 4.0, bounds.y + i * config.stride, max(0.0, bounds.w - 20.0), config.stride);
            lab_ui_view::at_list_item(view, str(prefix, "row-", i), config.row_base + row.node as u64, i, r);
            let left = r.x + 12.0 + row.depth * config.indent;
            if node.branch { lab_ui_view::at_chevron(view, str(prefix, "arrow-", i), lab_ui_geometry::rect(left, r.y, 18.0, r.h), row.expanded); }
            lab_ui_view::at_label(view, str(prefix, "label-", i), lab_ui_geometry::rect(left + 18.0, r.y, max(0.0, r.x + r.w - 12.0 - config.trailing - left - 18.0), r.h), node.label,
                0, if config.enabled { theme.text } else { theme.muted });
            F(row.node, i, r);
        }
    };
}
fn reduce<A>(tree: const lab_collections_tree::Tree&, state: lab_collections_tree::State&, rows: const lab_collections_tree::Rows&, event: lab_ui_view::Event<A>) -> Changed {
    if event.index < 0 || event.index >= rows.items.len { return Changed {}; }
    let row = rows.items[event.index]; let node = tree.nodes[row.node]; var changed = false;
    if event.kind == lab_ui_view::SELECT {
        changed = state.current != node.key; state.current = node.key;
        if event.pointer && node.branch && !rows.filtered { changed = lab_collections_tree::set_expanded(state, node, !row.expanded) || changed; }
    } else if event.kind == lab_ui_view::ACTIVATE {
        state.current = node.key;
        if node.branch && !rows.filtered { changed = lab_collections_tree::set_expanded(state, node, !row.expanded); }
    } else if event.kind == lab_ui_view::EXPAND {
        if node.branch && !row.expanded && !rows.filtered { changed = lab_collections_tree::set_expanded(state, node, true); }
        else if node.branch && event.index + 1 < rows.items.len && tree.nodes[rows.items[event.index + 1].node].parent == row.node {
            state.current = tree.nodes[rows.items[event.index + 1].node].key; changed = true;
        }
    } else if event.kind == lab_ui_view::COLLAPSE {
        if node.branch && row.expanded && !rows.filtered { changed = lab_collections_tree::set_expanded(state, node, false); }
        else if node.parent >= 0 { state.current = tree.nodes[node.parent].key; changed = true; }
    } else { return Changed {}; }
    let current = lab_collections_tree::index(tree, state.current);
    Changed { changed: changed, leaf: if current >= 0 && !tree.nodes[current].branch { tree.nodes[current].data } else { -1 } }
}
fn reveal<A>(view: lab_ui_view::View<A>&, tree: const lab_collections_tree::Tree&, state: const lab_collections_tree::State&, rows: const lab_collections_tree::Rows&,
    bounds: lab_ui_geometry::Rect, scroll_id: u64, stride: f32 = 28.0) {
    let selected = lab_collections_tree::current(tree, state, rows); if selected < 0 { return; }
    lab_ui_layout_scroll::reveal(lab_ui_view::scroll_state(view, scroll_id), selected * stride, (selected + 1) * stride, bounds.h, rows.items.len * stride);
}
