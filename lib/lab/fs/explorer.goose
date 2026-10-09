// Lazy directory adapter for lab.collections.tree. One bounded listing, committed as a whole.
namespace lab_fs_explorer;
import std;
import os;
import lab.fs.async_files;
import lab.io.event_loop;
import lab.collections.tree;
import lab.text.strings;
import lab.fs.path;
struct State {
    root: u8[..512] = [], tree: lab_collections_tree::Tree = lab_collections_tree::Tree {}, state: lab_collections_tree::State = lab_collections_tree::State {},
    loaded: bool[2048] = [false; 2048], listing: lab_fs_async_files::Listing = lab_fs_async_files::Listing {},
    parent: i64 = -1, blocked: i64 = -2, deadline: i64 = 0, code: i32 = 0, skipped: i64 = 0,
    entries: lab_fs_async_files::Entry[..512] = [],
}
fn close(s: State&) { if s.listing.id != 0 { lab_fs_async_files::cancel(s.listing); lab_fs_async_files::close(s.listing); } s.entries.resize(0); }
fn busy(s: const State&) -> bool {
    if s.listing.id != 0 { return true; }
    let rows = lab_collections_tree::project(s.tree, s.state);
    for row in rows.items { if row.expanded && !s.loaded[row.node] && s.blocked != row.node { return true; } } false
}
fn load(s: State&, context: const lab_io_event_loop::Context&, parent: i64 = -1) -> bool {
    if s.listing.id != 0 || parent < -1 || parent >= s.tree.nodes.len || (parent >= 0 && (!s.tree.nodes[parent].branch || s.loaded[parent])) { return false; }
    let path: u8[>..] = if parent < 0 { str(s.root) } else { str(s.root, "/", s.tree.nodes[parent].key) };
    if path.len > 512 { s.code = lab_io_event_loop::LIMIT; s.blocked = parent; return false; }
    s.listing = lab_fs_async_files::list(context, path, 512); s.code = s.listing.code;
    if s.code != 0 { s.blocked = parent; return false; }
    s.parent = parent; s.deadline = clock_ns() + 30000000000; s.entries.resize(0); true
}
fn create(context: const lab_io_event_loop::Context&, root: const u8[:]) -> State {
    var s = State {};
    if root.len == 0 || root.len > 512 || !lab_fs_async_files::valid_path(root) { s.code = lab_io_event_loop::INVALID; return s; }
    let absolute = lab_fs_path::absolute(root, 512); if absolute.code != 0 { s.code = absolute.code; return s; }
    s.root = absolute.bytes; load(s, context); s
}
fn adopt(s: State&) -> bool {
    // The retained tree is single. This temporary snapshot permits failed listings/builds
    // to leave the visible forest intact; it contains no document/text arena.
    var tree = if s.parent < 0 { lab_collections_tree::Tree {} } else { s.tree };
    let prefix: u8[>..] = if s.parent < 0 { str("") } else { str(s.tree.nodes[s.parent].key, "/") };
    var skipped: i64 = 0;
    for entry in s.entries {
        if entry.name == ".git" || (entry.kind != lab_fs_async_files::FILE && entry.kind != lab_fs_async_files::DIRECTORY) { skipped++; continue; }
        let key = str(prefix, entry.name);
        if key.len > 512 || !lab_text_strings::single_line(entry.name) { s.code = lab_io_event_loop::LIMIT; return false; }
        if !lab_fs_path::relative(key) { skipped++; continue; }
        let id = lab_collections_tree::add(tree, key, entry.name, s.parent, entry.kind == lab_fs_async_files::DIRECTORY, tree.nodes.len);
        if id < 0 { s.code = lab_io_event_loop::LIMIT; return false; }
    }
    let first = if s.parent < 0 { 0 } else { s.tree.nodes.len };
    var new_branch: bool[..2048] = []; new_branch.resize(tree.nodes.len, false);
    for i in first..tree.nodes.len { new_branch[i] = tree.nodes[i].branch && lab_collections_tree::index(s.tree, tree.nodes[i].key) < 0; }
    if s.parent < 0 { s.loaded = [false; 2048]; }
    s.tree = tree; lab_collections_tree::prune(s.tree, s.state);
    for i in first..s.tree.nodes.len { if new_branch[i] { lab_collections_tree::set_expanded(s.state, s.tree.nodes[i], false); } }
    if s.parent >= 0 { s.loaded[s.parent] = true; }
    s.skipped += skipped; s.code = 0; s.blocked = -2;
    let rows = lab_collections_tree::project(s.tree, s.state); lab_collections_tree::normalize(s.tree, s.state, rows); true
}
fn poll(s: State&, context: const lab_io_event_loop::Context&) {
    if s.root.len == 0 { return; }
    if s.listing.id != 0 {
        let driven = lab_io_event_loop::wait(context, 0); if driven != 0 { s.code = driven; s.blocked = s.parent; close(s); return; }
        let page = lab_fs_async_files::poll(s.listing);
        if page.code != 0 || (page.done && page.result != 0) || clock_ns() >= s.deadline {
            s.code = if page.code != 0 { page.code } else if page.done { page.result } else { lab_io_event_loop::CANCELLED };
            s.blocked = s.parent; close(s); return;
        }
        for entry in page.entries { s.entries.push(entry); }
        if page.done { if !adopt(s) { s.blocked = s.parent; } close(s); } return;
    }
    let rows = lab_collections_tree::project(s.tree, s.state);
    for row in rows.items { if row.expanded && !s.loaded[row.node] && s.blocked != row.node { load(s, context, row.node); break; } }
}
fn refresh(s: State&, context: const lab_io_event_loop::Context&) -> bool { close(s); s.blocked = -2; s.skipped = 0; load(s, context) }
fn message(s: const State&) -> const u8[:] {
    if s.code == lab_io_event_loop::LIMIT { return "Folder limit · Previous tree kept"; }
    if s.code != 0 { return lab_io_event_loop::message(s.code); }
    if s.listing.id != 0 { return "Reading folder…"; } "Expand folders · Links omitted"
}
