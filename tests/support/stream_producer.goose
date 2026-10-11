namespace support_stream_producer;
import std;
import os;
import lab.io.stream;
import lab.io.cancel;
struct Payload { owner: i64 = 0, ordinal: u64 = 0, text: u8[..64] = [], rejected: i64 = 0 }
struct Job { stop: bool = false, request: lab_io_stream::Request = lab_io_stream::Request { lab_io_stream::Id {}, 0, 0, lab_io_cancel::Token {} },
    pages: i64 = 3, timeout_ms: i64 = 10000 }
fn run<L>(lane: i64) {
    loop {
        lab_io_stream::drain_lane<Payload, L>(); let job = qget<Job>(); if job.stop { break; }
        let deadline = clock_ns() + job.timeout_ms * 1000000; var sequence: u64 = 1; var code: i32 = 0; var rejected: i64 = 0;
        for i in job.pages {
            if lab_io_cancel::requested(job.request.token) { code = lab_io_stream::CANCELLED; break; }
            lab_io_stream::publish<Payload>(job.request, lane, sequence,
                Payload { job.request.client.slot, sequence, str(job.request.client.slot, ":", job.request.serial, ":", sequence), rejected });
            let ack = lab_io_stream::await_ack<Payload, L>(job.request, sequence, deadline); rejected += ack.rejected;
            if ack.code != 0 { code = ack.code; break; } sequence++;
        }
        lab_io_stream::publish<Payload>(job.request, lane, sequence,
            Payload { owner: job.request.client.slot, ordinal: sequence, rejected: rejected }, true, code);
    }
    lab_io_stream::drain_lane<Payload, L>();
}
thread_fn worker0() { run<lab_io_stream::Lane0>(0); }
thread_fn worker1() { run<lab_io_stream::Lane1>(1); }
thread_fn worker2() { run<lab_io_stream::Lane2>(2); }
thread_fn worker3() { run<lab_io_stream::Lane3>(3); }
thread_fn worker4() { run<lab_io_stream::Lane4>(4); }
thread_fn worker5() { run<lab_io_stream::Lane5>(5); }
thread_fn worker6() { run<lab_io_stream::Lane6>(6); }
thread_fn worker7() { run<lab_io_stream::Lane7>(7); }
fn create(limits: lab_io_stream::Limits = lab_io_stream::Limits {}) -> lab_io_stream::Service<Payload> {
    var s = lab_io_stream::create<Payload>(limits); if s.code != 0 { return s; }
    s.workers.push(thread_spawn(worker0));
    if limits.workers > 1 { s.workers.push(thread_spawn(worker1)); }
    if limits.workers > 2 { s.workers.push(thread_spawn(worker2)); }
    if limits.workers > 3 { s.workers.push(thread_spawn(worker3)); }
    if limits.workers > 4 { s.workers.push(thread_spawn(worker4)); }
    if limits.workers > 5 { s.workers.push(thread_spawn(worker5)); }
    if limits.workers > 6 { s.workers.push(thread_spawn(worker6)); }
    if limits.workers > 7 { s.workers.push(thread_spawn(worker7)); } s
}
fn start(s: lab_io_stream::Service<Payload>&, id: lab_io_stream::Id, pages: i64 = 3, timeout_ms: i64 = 10000) -> i32 {
    if pages < 0 || pages > 64 || timeout_ms < 1 { return lab_io_stream::INVALID; }
    let request, code = lab_io_stream::begin(s, id); if code != 0 { return code; }
    qput(Job { request: request, pages: pages, timeout_ms: timeout_ms }); 0
}
fn shutdown(s: lab_io_stream::Service<Payload>&) {
    if !s.running { return; } lab_io_stream::prepare_shutdown(s);
    for i in s.workers.len { qput(Job { stop: true }); } lab_io_stream::finish_shutdown(s);
}
