// Worker adapter: owned result pages, latest query wins, explicit join.
namespace lab_fs_search_client;
import std;
import os;
import lab.io.cancel;
import lab.fs.search;
struct Job { stop: bool = false, serial: u64 = 0, root: u8[..512] = [], query: u8[..512] = [], options: lab_fs_search::Options = lab_fs_search::Options {} }
struct Update { serial: u64, root: u8[..512], query: u8[..512], batch: lab_fs_search::Batch }
struct Ack { serial: u64 }
struct State { worker: i64 = -1, serial: u64 = 0, busy: bool = false, pending: bool = false, code: i32 = 0,
    token: lab_io_cancel::Token = lab_io_cancel::Token {}, queued: Job = Job {} }
thread_fn worker() {
    loop {
        let job = qget<Job>(); if job.stop { break; }
        var search = lab_fs_search::start(job.root, job.query, job.options); var last: i64 = 0;
        if search.code != 0 { qput(Update { job.serial, job.root, job.query, lab_fs_search::Batch { done: true, result: search.code } }); continue; }
        loop {
            let batch = lab_fs_search::poll(search, 20);
            if batch.code != 0 {
                lab_fs_search::close(search); qput(Update { job.serial, job.root, job.query, lab_fs_search::Batch { done: true, result: lab_fs_search::IO } }); break;
            }
            let now = clock_ns();
            if batch.hits.len > 0 || batch.issues.len > 0 || batch.done || now - last >= 100000000 {
                qput(Update { job.serial, job.root, job.query, batch }); last = now;
                // One unacknowledged page: a stalled UI cannot accumulate output.
                if !batch.done {
                    loop {
                        if lab_io_cancel::requested(job.options.cancel) || clock_ns() >= search.deadline { break; }
                        let ack, available = qpoll<Ack>(); if available && ack.serial == job.serial { break; }
                        sleep_ms(2);
                    }
                }
            }
            if batch.done { lab_fs_search::close(search); break; }
        }
    }
}
fn create() -> State { State { worker: thread_spawn(worker) } }
fn start(state: State&, request: const Job&) -> bool {
    if state.worker < 0 || state.serial == 0xFFFFFFFFFFFFFFFF { state.code = lab_fs_search::INVALID; return false; }
    state.code = 0;
    if state.busy { state.queued = request; state.pending = true; lab_io_cancel::request(state.token); return true; }
    state.token = lab_io_cancel::create(); if state.token.id == 0 { state.code = lab_fs_search::IO; return false; }
    var job = request; state.serial++; state.busy = true; job.serial = state.serial; job.options.cancel = state.token; qput(job); true
}
fn accept(state: State&, update: const Update&) -> bool {
    if !update.batch.done { qput(Ack { update.serial }); }
    if !state.busy || state.serial != update.serial { return false; }
    if !update.batch.done { return !state.pending; }
    state.busy = false; lab_io_cancel::destroy(state.token);
    if state.pending { state.pending = false; let job = state.queued; start(state, job); return false; } true
}
fn cancel(state: State&) { state.pending = false; lab_io_cancel::request(state.token); }
fn close(state: State&) {
    if state.worker < 0 { return; }
    cancel(state); qput(Job { stop: true }); thread_wait(state.worker); state.worker = -1;
    loop { let update, available = qpoll<Update>(); if !available { break; } }
    loop { let ack, available = qpoll<Ack>(); if !available { break; } }
    lab_io_cancel::destroy(state.token); state.busy = false;
}
