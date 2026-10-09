// Owned command descriptions. Stable keys survive search and catalog reordering.
namespace lab_ui_command;
import std;
import lab.text.strings;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2;
struct Command<A> {
    id: u64, title: u8[..96], action: A,
    description: u8[..160] = [], keywords: u8[..160] = [],
    key: u8[..32] = [], mods: i32 = 0, enabled: bool = true, reason: u8[..96] = [],
}
struct Catalog<A> { code: i32 = OK, items: Command<A>[..64] = [] }
struct State { current: u64 = 0 }
struct Rows { items: i64[..64] = [] }
fn index<A>(catalog: const Catalog<A>&, id: u64) -> i64 {
    for i in catalog.items.len { if catalog.items[i].id == id { return i; } } -1
}
// Validate before copying into bounded storage. Failed catalogs cannot execute.
fn add<A>(catalog: Catalog<A>&, id: u64, title: const u8[:], action: A,
    description: const u8[:] = "", keywords: const u8[:] = "", key: const u8[:] = "", mods: i32 = 0,
    enabled: bool = true, reason: const u8[:] = "") -> bool {
    if catalog.code != OK { return false; }
    if catalog.items.len == 64 { catalog.code = LIMIT; return false; }
    if id == 0 || index(catalog, id) >= 0 || title.len == 0 || title.len > 96 || description.len > 160 || keywords.len > 160 || key.len > 32 || reason.len > 96 || mods < 0 || mods > 15 ||
        !lab_text_strings::single_line(title) || !lab_text_strings::single_line(description) || !lab_text_strings::single_line(keywords) || !lab_text_strings::single_line(key) || !lab_text_strings::single_line(reason) {
        catalog.code = INVALID; return false;
    }
    for command in catalog.items {
        if key.len > 0 && command.key.len > 0 && mods == command.mods && key == command.key { catalog.code = INVALID; return false; }
    }
    catalog.items.push(Command<A> { id, title, action, description, keywords, key, mods, enabled, reason }); true
}
fn matches<A>(command: const Command<A>&, query: const u8[:]) -> bool {
    var first: i64 = 0;
    while first < query.len {
        while first < query.len && query[first] == ' ' { first++; }
        var end = first; while end < query.len && query[end] != ' ' { end++; }
        if end > first && !lab_text_strings::contains_folded(command.title, query[first..end]) && !lab_text_strings::contains_folded(command.keywords, query[first..end]) { return false; }
        first = end;
    } true
}
fn project<A>(catalog: const Catalog<A>&, query: const u8[:]) -> Rows {
    var rows = Rows {}; if catalog.code != OK { return rows; }
    for i in catalog.items.len { if matches(catalog.items[i], trim(query)) { rows.items.push(i); } } rows
}
fn current<A>(catalog: const Catalog<A>&, state: const State&, rows: const Rows&) -> i64 {
    for i in rows.items.len { if catalog.items[rows.items[i]].id == state.current { return i; } } -1
}
fn normalize<A>(catalog: const Catalog<A>&, state: State&, rows: const Rows&) {
    if current(catalog, state, rows) >= 0 { return; }
    state.current = 0;
    for row in rows.items { if catalog.items[row].enabled { state.current = catalog.items[row].id; return; } }
    if rows.items.len > 0 { state.current = catalog.items[rows.items[0]].id; }
}
// Resolve against a fresh catalog, rather than retaining an action from opening.
fn resolve<A>(catalog: const Catalog<A>&, id: u64) -> A, bool {
    let i = index(catalog, id);
    if catalog.code == OK && i >= 0 && catalog.items[i].enabled { return catalog.items[i].action, true; }
    return default<A>(), false;
}
