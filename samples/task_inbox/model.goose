// Application model: pure commands, stable IDs, bounded undo and derived views.
namespace app_tasks_model;
import std;
import binary;
import lab.text.strings;
import lab.fs.storage;
let ADD: i32 = 1; let TOGGLE: i32 = 2; let RENAME: i32 = 3; let DELETE: i32 = 4;
let OK: i32 = 0; let INVALID: i32 = 1; let FULL: i32 = 2; let ABSENT: i32 = 3; let UNCHANGED: i32 = 4;
let ALL: i32 = 0; let ACTIVE: i32 = 1; let DONE: i32 = 2;
struct Task { id: u32, title: u8[..240] = [], done: bool = false }
struct Store { next_id: u32 = 1, items: Task[..128] = [] }
struct Journal { store: Store = Store {}, past: Store[..16] = [] }
struct Command { kind: i32, id: u32 = 0, title: u8[..240] = [] }
fn index(store: const Store&, id: u32) -> i64 { for i in store.items.len { if store.items[i].id == id { return i; } } -1 }
fn checkpoint(j: Journal&) { if j.past.len == 16 { remove_at(j.past, 0); } j.past.push(j.store); }
fn apply(j: Journal&, command: Command) -> i32 {
    if command.kind == ADD || command.kind == RENAME {
        let title = trim(command.title);
        if title.len == 0 || !lab_text_strings::single_line(title) { return INVALID; }
        if command.kind == ADD {
            if j.store.items.len == 128 || j.store.next_id == 0xFFFFFFFF { return FULL; }
            checkpoint(j); j.store.items.push(Task { id: j.store.next_id, title: title }); j.store.next_id++; return OK;
        }
        let i = index(j.store, command.id); if i < 0 { return ABSENT; }
        if j.store.items[i].title == title { return UNCHANGED; }
        checkpoint(j); j.store.items[i].title.resize(0); j.store.items[i].title.append(title); return OK;
    }
    let i = index(j.store, command.id); if i < 0 { return ABSENT; }
    if command.kind != TOGGLE && command.kind != DELETE { return INVALID; }
    checkpoint(j);
    if command.kind == TOGGLE { j.store.items[i].done = !j.store.items[i].done; }
    else { remove_at(j.store.items, i); }
    OK
}
fn undo(j: Journal&) -> bool {
    if j.past.len == 0 { return false; }
    let next = j.store.next_id; j.store = j.past[j.past.len - 1];
    // Undo never reuses IDs allocated during this session.
    j.store.next_id = max(next, j.store.next_id); j.past.resize(j.past.len - 1); true
}
fn visible(store: const Store&, filter: i32, query: const u8[:]) -> u32[>..] {
    var ids: u32[>..] = [];
    for task in store.items {
        if filter == ACTIVE && task.done { continue; }
        if filter == DONE && !task.done { continue; }
        if lab_text_strings::contains_folded(task.title, trim(query)) { ids.push(task.id); }
    }
    ids
}
fn completed(store: const Store&) -> i64 { var count = 0; for task in store.items { if task.done { count++; } } count }
fn encode(store: const Store&) -> u8[>..] {
    var out: u8[>..] = []; lab_fs_storage::u32le(out, store.next_id); lab_fs_storage::u16le(out, store.items.len as u16);
    for task in store.items {
        lab_fs_storage::u32le(out, task.id); out.push(if task.done { 1 as u8 } else { 0 as u8 });
        lab_fs_storage::u16le(out, task.title.len as u16); out.append(task.title);
    }
    out
}
fn decode(bytes: const u8[:]) -> Store, bool {
    var out = Store {}; var r = binary::reader(bytes);
    let next_id, n = binary::read_u32le(r); let count, c = binary::read_u16le(r);
    if !n || !c || count > 128 || next_id == 0 { return Store {}, false; }
    out.next_id = next_id;
    for i in count {
        let id, a = binary::read_u32le(r); let flags, b = binary::read_bytes(r, 1); let size, s = binary::read_u16le(r);
        if !a || !b || !s || id == 0 || id >= next_id || size == 0 || size > 240 { return Store {}, false; }
        let title, t = binary::read_bytes(r, size);
        if !t || flags[0] > 1 || !lab_text_strings::single_line(title) || trim(title).len != title.len || index(out, id) >= 0 { return Store {}, false; }
        out.items.push(Task { id: id, title: title, done: flags[0] == 1 });
    }
    if r.pos != bytes.len { return Store {}, false; }
    return out, true;
}
fn load(path: const u8[:]) -> Store, i32 {
    let loaded = lab_fs_storage::load(path, "GXTASKS!", 1);
    if loaded.code != lab_fs_storage::OK { return Store {}, loaded.code; }
    let store, valid = decode(loaded.data);
    return store, if valid { lab_fs_storage::OK } else { lab_fs_storage::CORRUPT };
}
fn save(path: const u8[:], store: const Store&) -> i32 { let data = encode(store); lab_fs_storage::save(path, "GXTASKS!", 1, data) }
