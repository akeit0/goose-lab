namespace lab_io_timer;
import std;
import lab.io.event_loop;
struct Handle { id: u64 = 0, code: i32 = lab_io_event_loop::OK }
struct Fired { code: i32, count: i64 = 0 }
extern "glab_loop_timer" fn open_raw(context_id: u64, delay: i64, repeat: i64, id: u64&) -> i32;
extern "glab_timer_start" fn start_raw(id: u64, delay: i64, repeat: i64) -> i32;
extern "glab_timer_stop" fn stop_raw(id: u64) -> i32;
extern "glab_timer_poll" fn poll_raw(id: u64, count: i64&) -> i32;
extern "glab_loop_resource_close" fn close_raw(id: u64, kind: i32) -> bool;
// Milliseconds, bounded to one day. repeat=0 means one-shot.
fn start(context: const lab_io_event_loop::Context&, delay_ms: i64, repeat_ms: i64 = 0) -> Handle {
    let code = lab_io_event_loop::status(context); if code != lab_io_event_loop::OK { return Handle { code: code }; }
    var handle = Handle {}; handle.code = open_raw(context.id, delay_ms, repeat_ms, handle.id); handle
}
fn restart(handle: const Handle&, delay_ms: i64, repeat_ms: i64 = 0) -> i32 {
    if handle.id == 0 { return if handle.code != 0 { handle.code } else { lab_io_event_loop::CLOSED }; } start_raw(handle.id, delay_ms, repeat_ms)
}
// Stop and restart discard unconsumed firings from the old schedule.
fn stop(handle: const Handle&) -> i32 { if handle.id == 0 { return lab_io_event_loop::CLOSED; } stop_raw(handle.id) }
fn poll(handle: const Handle&) -> Fired {
    if handle.id == 0 { return Fired { code: if handle.code != 0 { handle.code } else { lab_io_event_loop::CLOSED } }; }
    var count: i64 = 0; let code = poll_raw(handle.id, count); Fired { code, count }
}
fn close(handle: Handle&) -> bool {
    if handle.id == 0 || !close_raw(handle.id, 3) { return false; } handle.id = 0; handle.code = lab_io_event_loop::CLOSED; true
}
