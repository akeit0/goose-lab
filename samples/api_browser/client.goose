// Isolated worker boundary: parse borrowed HTTP bytes, send only owned domain data.
namespace app_api_client;
import std;
import os;
import lab.net.http;
import lab.io.cancel;
import api_browser.feed;
struct Job { stop: bool = false, serial: u64 = 0, cancel: lab_io_cancel::Token = lab_io_cancel::Token {}, url: u8[] = [] }
struct Completed { serial: u64, status: i64, elapsed_ms: i64, code: i32, url: u8[..512], feed: app_api_feed::Feed, body: u8[] = [] }
struct State {
    serial: u64 = 0, busy: bool = false, cancelling: bool = false, cancelled: bool = false, start_failed: bool = false,
    status: i64 = 0, elapsed_ms: i64 = 0, code: i32 = 0, token: lab_io_cancel::Token = lab_io_cancel::Token {}, url: u8[..512] = [],
}
thread_fn worker() {
    loop {
        let job = qget<Job>(); if job.stop { break; }
        let started = clock_ns();
        let response = lab_net_http::send(lab_net_http::Request { url: job.url, headers: "Accept: application/json\n" },
            lab_net_http::Options { timeout_ms: 8000, connect_timeout_ms: 3000, max_body_bytes: 1048576, cancel: job.cancel });
        var feed = app_api_feed::Feed {};
        if response.code != lab_net_http::OK {
            feed = app_api_feed::Feed { code: app_api_feed::SCHEMA, error: response.error[..min(response.error.len, 256)] };
        } else if response.status < 200 || response.status >= 300 {
            feed = app_api_feed::Feed { code: app_api_feed::SCHEMA, error: str("HTTP ", response.status, ". Check the URL and retry.") };
        } else if !lab_io_cancel::requested(job.cancel) { feed = app_api_feed::decode(response.body); }
        qput(Completed { serial: job.serial, status: response.status, elapsed_ms: (clock_ns() - started) / 1000000,
            code: response.code, url: job.url, feed: feed, body: response.body[..] });
    }
}
fn start(state: State&, url: const u8[:]) -> bool {
    if state.busy || url.len == 0 || url.len > 512 || state.serial == 0xFFFFFFFFFFFFFFFF { return false; }
    let token = lab_io_cancel::create(); state.start_failed = token.id == 0;
    if state.start_failed { state.code = lab_net_http::MEMORY; return false; }
    state.serial++; state.busy = true; state.cancelling = false; state.cancelled = false; state.token = token; state.url = url;
    qput(Job { serial: state.serial, cancel: token, url: url }); true
}
fn cancel(state: State&) -> bool {
    if !state.busy || state.cancelling { return false; }
    if !lab_io_cancel::request(state.token) { return false; }
    state.cancelling = true; true
}
fn accept(state: State&, result: const Completed&) -> bool {
    if !state.busy || result.serial != state.serial { return false; }
    // User intent wins even if a successful response was queued just before Cancel.
    state.cancelled = state.cancelling || result.code == lab_net_http::CANCELLED;
    state.busy = false; state.cancelling = false; state.status = result.status; state.elapsed_ms = result.elapsed_ms;
    state.code = if state.cancelled { lab_net_http::CANCELLED } else { result.code };
    lab_io_cancel::destroy(state.token); true
}
