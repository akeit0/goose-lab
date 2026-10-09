// Monotonic nanosecond clock supplied by the caller; no timer or callback owner.
namespace lab_io_debounce;
import std;
struct State { pending: bool = false, first: i64 = 0, last: i64 = 0 }
fn push(state: State&, now: i64) {
    assert(now >= 0); if !state.pending || now < state.last { state.first = now; }
    state.pending = true; state.last = now;
}
fn ready(state: const State&, now: i64, quiet: i64 = 180000000, maximum: i64 = 1200000000) -> bool {
    assert(now >= 0 && quiet >= 0 && maximum >= quiet);
    state.pending && now >= state.last && (now - state.last >= quiet || now - state.first >= maximum)
}
fn clear(state: State&) { state = State {}; }
