// Multiple logical searches over bounded worker/ACK lanes. One Service per program.
namespace lab_fs_search_clients;
import std;
import os;
import lab.io.stream;
import lab.io.cancel;
import lab.io.event_loop;
import lab.fs.search;
struct Job { stop: bool = false, request: lab_io_stream::Request = lab_io_stream::Request { lab_io_stream::Id {}, 0, 0, lab_io_cancel::Token {} },
    root: u8[..512] = [], query: u8[..512] = [], options: lab_fs_search::Options = lab_fs_search::Options {} }
struct Service { flow: lab_io_stream::Service<lab_fs_search::Batch> = lab_io_stream::Service<lab_fs_search::Batch> {} }
fn result_code(result: i32) -> i32 {
    if result == lab_fs_search::OK { lab_io_stream::OK }
    else if result == lab_fs_search::CANCELLED { lab_io_stream::CANCELLED }
    else if result == lab_fs_search::TIMEOUT { lab_io_stream::TIMEOUT }
    else { lab_io_stream::FAILED }
}
fn run<L>(lane: i64) {
    loop {
        lab_io_stream::drain_lane<lab_fs_search::Batch, L>();
        let job = qget<Job>(); if job.stop { break; }
        var options = job.options; options.cancel = job.request.token;
        var search = lab_fs_search::start(job.root, job.query, options);
        var sequence: u64 = 1;
        if search.code != 0 {
            lab_io_stream::publish<lab_fs_search::Batch>(job.request, lane, sequence, lab_fs_search::Batch { done: true, result: search.code }, true, lab_io_stream::FAILED); continue;
        }
        loop {
            var batch = lab_fs_search::poll(search, 20);
            if batch.code != 0 { batch = lab_fs_search::Batch { done: true, result: lab_fs_search::IO }; }
            if batch.done {
                // Close thread-owned native resources before publishing terminal.
                assert(lab_fs_search::close(search));
                lab_io_stream::publish<lab_fs_search::Batch>(job.request, lane, sequence, batch, true, result_code(batch.result)); break;
            }
            if batch.hits.len == 0 && batch.issues.len == 0 { continue; }
            lab_io_stream::publish<lab_fs_search::Batch>(job.request, lane, sequence, batch);
            let ack = lab_io_stream::await_ack<lab_fs_search::Batch, L>(job.request, sequence, search.deadline);
            if ack.code != lab_io_stream::OK {
                var progress = batch.progress; progress.active = 0; assert(lab_fs_search::close(search));
                lab_io_stream::publish<lab_fs_search::Batch>(job.request, lane, sequence,
                    lab_fs_search::Batch { done: true, result: if ack.code == lab_io_stream::CANCELLED { lab_fs_search::CANCELLED } else { lab_fs_search::TIMEOUT }, progress: progress }, true, ack.code);
                break;
            }
            sequence++;
        }
    }
    lab_io_stream::drain_lane<lab_fs_search::Batch, L>();
}
// thread_fn cannot be generic. Eight concrete entry points specialize the
// shared implementation and, through L, select distinct existing typed queues.
thread_fn worker0() { run<lab_io_stream::Lane0>(0); }
thread_fn worker1() { run<lab_io_stream::Lane1>(1); }
thread_fn worker2() { run<lab_io_stream::Lane2>(2); }
thread_fn worker3() { run<lab_io_stream::Lane3>(3); }
thread_fn worker4() { run<lab_io_stream::Lane4>(4); }
thread_fn worker5() { run<lab_io_stream::Lane5>(5); }
thread_fn worker6() { run<lab_io_stream::Lane6>(6); }
thread_fn worker7() { run<lab_io_stream::Lane7>(7); }
fn create(limits: lab_io_stream::Limits = lab_io_stream::Limits {}) -> Service {
    var s = Service { flow: lab_io_stream::create<lab_fs_search::Batch>(limits) };
    if s.flow.code != 0 { return s; }
    s.flow.workers.push(thread_spawn(worker0));
    if limits.workers > 1 { s.flow.workers.push(thread_spawn(worker1)); }
    if limits.workers > 2 { s.flow.workers.push(thread_spawn(worker2)); }
    if limits.workers > 3 { s.flow.workers.push(thread_spawn(worker3)); }
    if limits.workers > 4 { s.flow.workers.push(thread_spawn(worker4)); }
    if limits.workers > 5 { s.flow.workers.push(thread_spawn(worker5)); }
    if limits.workers > 6 { s.flow.workers.push(thread_spawn(worker6)); }
    if limits.workers > 7 { s.flow.workers.push(thread_spawn(worker7)); } s
}
fn start(s: Service&, id: lab_io_stream::Id, root: const u8[:], query: const u8[:], options: lab_fs_search::Options = lab_fs_search::Options {}) -> i32 {
    // Validate without creating a host-thread search context. Remaining engine
    // option/query errors are reported by a worker as a terminal Batch.
    if root.len == 0 || root.len > 512 || query.len == 0 || query.len > 512 || options.cancel.id != 0 { return lab_io_stream::INVALID; }
    let request, code = lab_io_stream::begin(s.flow, id); if code != 0 { return code; }
    // The existing native registry allows 16 simultaneous read handles across
    // the process. Divide that budget across lanes rather than starting 8*4.
    var bounded = options;
    if bounded.parallel >= 1 && bounded.parallel <= 8 { bounded.parallel = min(bounded.parallel, 16 / s.flow.limits.workers); }
    qput(Job { request: request, root: root, query: query, options: bounded }); lab_io_stream::OK
}
fn take(s: Service&, id: lab_io_stream::Id) -> lab_io_stream::Page<lab_fs_search::Batch>, i32 {
    var page, code = lab_io_stream::take(s.flow, id);
    if code == 0 && page.done {
        page.data.done = true;
        if page.code == lab_io_stream::CANCELLED { page.data.result = lab_fs_search::CANCELLED; }
        else if page.code == lab_io_stream::TIMEOUT { page.data.result = lab_fs_search::TIMEOUT; }
    }
    return page, code;
}
fn shutdown(s: Service&) {
    if !s.flow.running { return; }
    lab_io_stream::prepare_shutdown(s.flow);
    for i in s.flow.workers.len { qput(Job { stop: true }); }
    lab_io_stream::finish_shutdown(s.flow);
}
