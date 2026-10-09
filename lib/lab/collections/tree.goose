// Owned bounded forest, stable keys, persistent expansion and transient projections.
namespace lab_collections_tree;
import std;
import lab.text.strings;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2;
struct Node {
    key: u8[..512], label: u8[..512], parent: i64 = -1, depth: i64 = 0,
    branch: bool = false, data: i64 = -1, first: i64 = -1, next: i64 = -1,
}
struct Tree { code: i32 = OK, first: i64 = -1, nodes: Node[..2048] = [] }
struct State { current: u8[..512] = [], closed: u8[..512][..2048] = [] }
struct Row { node: i64, depth: i64, expanded: bool = false }
struct Rows { filtered: bool = false, items: Row[..2048] = [] }
fn index(tree: const Tree&, key: const u8[:]) -> i64 {
    for i in tree.nodes.len { if tree.nodes[i].key == key { return i; } } -1
}
fn closed_index(state: const State&, key: const u8[:]) -> i64 {
    for i in state.closed.len { if state.closed[i] == key { return i; } } -1
}
fn expanded(state: const State&, node: const Node&) -> bool { node.branch && closed_index(state, node.key) < 0 }
fn before(a: const Node&, b: const Node&) -> bool {
    if a.branch != b.branch { return a.branch; }
    for i in min(a.label.len, b.label.len) {
        let left = lab_text_strings::folded(a.label[i]); let right = lab_text_strings::folded(b.label[i]);
        if left != right { return left < right; }
    }
    if a.label.len != b.label.len { return a.label.len < b.label.len; }
    for i in min(a.key.len, b.key.len) { if a.key[i] != b.key[i] { return a.key[i] < b.key[i]; } }
    a.key.len < b.key.len
}
// Parents must exist first and be branches; this prevents cycles without references.
// A failed builder has code != OK and must not be adopted by a consumer.
fn add(tree: Tree&, key: const u8[:], label: const u8[:], parent: i64 = -1, branch: bool = false, data: i64 = -1) -> i64 {
    if tree.code != OK { return -1; }
    if tree.nodes.len == 2048 { tree.code = LIMIT; return -1; }
    if key.len == 0 || key.len > 512 || label.len == 0 || label.len > 512 || !lab_text_strings::single_line(label) ||
        parent < -1 || parent >= tree.nodes.len || index(tree, key) >= 0 { tree.code = INVALID; return -1; }
    if parent >= 0 && !tree.nodes[parent].branch { tree.code = INVALID; return -1; }
    let depth = if parent >= 0 { tree.nodes[parent].depth + 1 } else { 0 };
    if depth > 32 { tree.code = LIMIT; return -1; }
    let id = tree.nodes.len; tree.nodes.push(Node { key: key, label: label, parent: parent, depth: depth, branch: branch, data: data });
    var next = if parent >= 0 { tree.nodes[parent].first } else { tree.first }; var previous: i64 = -1;
    while next >= 0 && !before(tree.nodes[id], tree.nodes[next]) { previous = next; next = tree.nodes[next].next; }
    tree.nodes[id].next = next;
    if previous >= 0 { tree.nodes[previous].next = id; }
    else if parent >= 0 { tree.nodes[parent].first = id; } else { tree.first = id; }
    id
}
fn set_expanded(state: State&, node: const Node&, open: bool) -> bool {
    if !node.branch { return false; } let at = closed_index(state, node.key);
    if open {
        if at < 0 { return false; } state.closed[at] = state.closed[state.closed.len - 1]; state.closed.pop();
    } else {
        if at >= 0 { return false; } assert(state.closed.len < 2048); state.closed.push(node.key);
    } true
}
fn prune(tree: const Tree&, state: State&) {
    var i: i64 = 0;
    while i < state.closed.len {
        let node = index(tree, state.closed[i]);
        if node < 0 || !tree.nodes[node].branch { state.closed[i] = state.closed[state.closed.len - 1]; state.closed.pop(); }
        else { i++; }
    }
}
// A supplied match mask forces only matching nodes and their ancestors open;
// it never edits State. Omitted mask projects the saved expansion state.
fn project(tree: const Tree&, state: const State&, matches: const bool[:] = []) -> Rows {
    assert(tree.code == OK && (matches.len == 0 || matches.len == tree.nodes.len));
    var include: bool[..2048] = []; include.resize(tree.nodes.len, matches.len == 0);
    if matches.len > 0 {
        for i in matches.len { include[i] = matches[i]; }
        var i = tree.nodes.len;
        while i > 0 { i--; let p = tree.nodes[i].parent; if include[i] && p >= 0 { include[p] = true; } }
    }
    var rows = Rows { filtered: matches.len > 0 }; var at = tree.first;
    while at >= 0 {
        let node = tree.nodes[at]; let open = node.branch && (rows.filtered || expanded(state, node));
        if include[at] { rows.items.push(Row { at, node.depth, open }); }
        if include[at] && open && node.first >= 0 { at = node.first; continue; }
        while at >= 0 && tree.nodes[at].next < 0 { at = tree.nodes[at].parent; }
        if at >= 0 { at = tree.nodes[at].next; }
    } rows
}
fn row_index(rows: const Rows&, node: i64) -> i64 {
    for i in rows.items.len { if rows.items[i].node == node { return i; } } -1
}
fn current(tree: const Tree&, state: const State&, rows: const Rows&) -> i64 { row_index(rows, index(tree, state.current)) }
// A hidden focused child falls back to its visible ancestor; removed keys to the first row.
fn normalize(tree: const Tree&, state: State&, rows: const Rows&) {
    var node = index(tree, state.current);
    while node >= 0 {
        if row_index(rows, node) >= 0 { state.current = tree.nodes[node].key; return; } node = tree.nodes[node].parent;
    }
    state.current = if rows.items.len > 0 { tree.nodes[rows.items[0].node].key[..] } else { "" };
}
fn message(code: i32) -> const u8[:] {
    match code { 0 => "Tree ready", 1 => "Invalid tree key, label or parent", _ => "Tree exceeds 2048 nodes, 512-byte keys or depth 32" }
}
