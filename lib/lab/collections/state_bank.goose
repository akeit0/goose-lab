// Bounded persistent values keyed by stable identity, independent of any UI backend.
namespace lab_collections_state_bank;
import std;
struct Entry<T> { id: u64, value: T = default<T>() }
struct Bank<T> { entries: Entry<T>[..32] = [] }
fn index<T>(b: const Bank<T>&, id: u64) -> i64 {
    for i in b.entries.len { if b.entries[i].id == id { return i; } } -1
}
fn contains<T>(b: const Bank<T>&, id: u64) -> bool { index(b, id) >= 0 }
fn ensure<T>(b: Bank<T>&, id: u64) -> bool {
    if id == 0 { return false; }
    if contains(b, id) { return true; }
    if b.entries.len == 32 { return false; }
    b.entries.push(Entry<T> { id: id }); true
}
fn get<T>(b: Bank<T>&, id: u64) -> T& {
    assert(ensure(b, id)); b.entries[index(b, id)].value
}
// A legitimate optional reference: it borrows from the bank, never from a local value.
fn lookup<T>(b: Bank<T>&, id: u64) -> T? {
    let i = index(b, id); if i < 0 { return null; } b.entries[i].value
}
// Removal can reuse an array slot. Do not retain value references across remove/clear.
fn remove<T>(b: Bank<T>&, id: u64) -> bool {
    let i = index(b, id); if i < 0 { return false; }
    b.entries[i] = b.entries[b.entries.len - 1]; b.entries.pop(); true
}
fn clear<T>(b: Bank<T>&) { b.entries.resize(0); }
