// Dense rows independent of logical identity. Supports AoS stores and SoA columns.
namespace lab_ecs_sparse;
import std;
import lab.ecs.pool;
struct Index { slots: i64[..64] = [], sparse: i64[64] = [-1; 64] }
fn row(index: const Index&, slot: i64) -> i64 { if slot >= 0 && slot < 64 { index.sparse[slot] } else { -1 } }
fn insert(index: Index&, slot: i64) -> i64 {
    if slot < 0 || slot >= 64 { return -1; }
    if index.sparse[slot] >= 0 { return index.sparse[slot]; }
    if index.slots.len == 64 { return -1; }
    let result = index.slots.len; index.slots.push(slot); index.sparse[slot] = result; result
}
// Return the removed row and former last row, so parallel columns apply the same
// swap/truncation. No row reference may survive a structural operation.
fn remove(index: Index&, slot: i64) -> i64, i64 {
    let at = row(index, slot); if at < 0 { return -1, -1; }
    let last = index.slots.len - 1; let moved = index.slots[last];
    index.slots[at] = moved; index.sparse[moved] = at; index.slots.resize(last); index.sparse[slot] = -1;
    return at, last;
}
fn check(index: const Index&) {
    for slot, at in index.slots { assert(slot >= 0 && slot < 64 && index.sparse[slot] == at); }
    for slot in 64 { let at = index.sparse[slot]; assert(at == -1 || (at >= 0 && at < index.slots.len && index.slots[at] == slot)); }
}
struct Store<T> { rows: Index = Index {}, values: T[..64] = [], generations: u64[64] = [0; 64] }
fn put<T>(s: Store<T>&, p: const lab_ecs_pool::Pool&, id: lab_ecs_pool::Id, value: T) -> i32 {
    if !lab_ecs_pool::valid(p, id) { return lab_ecs_pool::STALE; }
    let at = insert(s.rows, id.slot); assert(at >= 0);
    if at == s.values.len { s.values.push(value); } else { s.values[at] = value; }
    s.generations[id.slot] = id.generation; lab_ecs_pool::OK
}
fn lookup<T>(s: Store<T>&, p: const lab_ecs_pool::Pool&, id: lab_ecs_pool::Id) -> T? {
    if !lab_ecs_pool::valid(p, id) || s.generations[id.slot] != id.generation { return null; }
    let at = row(s.rows, id.slot); if at < 0 { return null; } s.values[at]
}
fn erase<T>(s: Store<T>&, id: lab_ecs_pool::Id) -> bool {
    if id.slot < 0 || id.slot >= 64 || s.generations[id.slot] != id.generation { return false; }
    let at, last = remove(s.rows, id.slot); if at < 0 { return false; }
    s.values[at] = s.values[last]; s.values.resize(last); s.generations[id.slot] = 0; true
}
fn prune<T>(s: Store<T>&, p: const lab_ecs_pool::Pool&) {
    for slot in 64 {
        let id = lab_ecs_pool::Id { slot, s.generations[slot] };
        if row(s.rows, slot) >= 0 && !lab_ecs_pool::valid(p, id) { assert(erase(s, id)); }
    }
}
