// Caller-owned, bounded polling server. Application callbacks never own sockets.
namespace lab_net_line_server;
import std;
import lab.net.tcp;
let OK: i32 = 0; let INVALID: i32 = 1; let TRANSPORT: i32 = 2;
let CONNECTED: i32 = 0; let REQUEST: i32 = 1;
let KEEP: i32 = 0; let CLOSE: i32 = 1; let STOP: i32 = 2;
struct Id { slot: i64 = -1, generation: u64 = 0 }
struct Reply { action: i32 = KEEP, bytes: u8[>..] = [] }
struct Options { port: i64 = 0, connections: i64 = 3, response_bytes: i64 = 1100, send_bytes: i64 = 2048,
    send_buffer: i64 = 0, idle_ms: i64 = 30000, drain_ms: i64 = 1000 }
struct Connection { socket: u64 = 0, generation: u64 = 0, eof: bool = false, closing: bool = false,
    input: u8[..256] = [], output: u8[..2048] = [], sent: i64 = 0, activity: i64 = 0, draining: i64 = 0 }
struct Counters { accepted: i64 = 0, closed: i64 = 0, requests: i64 = 0, paused: i64 = 0, partial: i64 = 0, written: i64 = 0,
    input_peak: i64 = 0, output_peak: i64 = 0, blocked: i64 = 0, compactions: i64 = 0, reclaimed: i64 = 0,
    timed_out: i64 = 0, blocked_id: Id = Id {} }
// Fields are implementation state. Do not copy an active Service; destroy exactly
// once after its owner stops polling. All callbacks and socket calls use one thread.
struct Service { code: i32 = OK, initialized: bool = false, listener: u64 = 0, port: i64 = 0,
    options: Options = Options {}, clients: Connection[16] = [Connection {}; 16], counters: Counters = Counters {}, cursor: i64 = 0 }
fn create(options: Options = Options {}) -> Service {
    if options.port < 0 || options.port > 65535 || options.connections < 1 || options.connections > 16 ||
        options.response_bytes < 32 || options.response_bytes > 2048 || options.send_bytes < 1 || options.send_bytes > 2048 ||
        options.send_buffer < 0 || options.send_buffer > 1048576 || options.idle_ms < 0 || options.idle_ms > 3600000 || options.drain_ms < 1 || options.drain_ms > 60000 {
        return Service { code: INVALID };
    }
    if !lab_net_tcp::init() { return Service { code: TRANSPORT }; }
    var port: i64 = 0; let listener = lab_net_tcp::listen(options.port, port);
    if listener == 0 { assert(lab_net_tcp::shutdown()); return Service { code: TRANSPORT }; }
    Service { initialized: true, listener: listener, port: port, options: options }
}
fn valid(s: const Service&, id: Id) -> bool {
    id.slot >= 0 && id.slot < s.options.connections && s.clients[id.slot].socket != 0 && s.clients[id.slot].generation == id.generation
}
fn retire(c: Connection&, counters: Counters&) {
    var scratch: u8[16] = [0; 16];
    for i in 16 { if lab_net_tcp::receive(c.socket, scratch[0], 16) <= 0 { break; } }
    assert(lab_net_tcp::close(c.socket)); let generation = c.generation; c = Connection { generation: generation }; counters.closed++;
}
fn closing(c: Connection&, now: i64) { if !c.closing { c.closing = true; c.draining = now; c.input.resize(0); } }
fn stop(s: Service&, now: i64) {
    if s.listener != 0 { assert(lab_net_tcp::close(s.listener)); s.listener = 0; }
    for slot in s.options.connections { if s.clients[slot].socket != 0 { closing(s.clients[slot], now); } }
}
fn running(s: const Service&) -> bool {
    if s.listener != 0 { return true; }
    for c in s.clients { if c.socket != 0 { return true; } } false
}
fn destroy(s: Service&) {
    if !s.initialized { return; }
    stop(s, 0); for slot in s.options.connections { if s.clients[slot].socket != 0 { retire(s.clients[slot], s.counters); } }
    assert(lab_net_tcp::shutdown()); s.initialized = false;
}
fn reserve(c: Connection&, counters: Counters&, bytes: i64) -> bool {
    if c.output.len > 2048 - bytes && c.sent > 0 {
        let remaining = c.output.len - c.sent;
        for i in remaining { c.output[i] = c.output[c.sent + i]; }
        c.output.resize(remaining); counters.reclaimed += c.sent; c.sent = 0; counters.compactions++;
    }
    c.output.len <= 2048 - bytes
}
fn reply(s: Service&, slot: i64, response: const Reply&, now: i64) {
    let c .= s.clients[slot];
    if response.bytes.len > s.options.response_bytes || response.action < KEEP || response.action > STOP {
        c.output.append("ERR response-limit\n"); closing(c, now); return;
    }
    c.output.append(response.bytes);
    if response.action == CLOSE { closing(c, now); }
    if response.action == STOP { stop(s, now); }
}
// F(id, borrowed line, CONNECTED/REQUEST) -> owned Reply. One request per peer per
// pass, rotating the first peer. Handler output must fit Options.response_bytes.
fn poll<F>(s: Service&, now: i64) {
    if !s.initialized { return; }
    if s.listener != 0 {
        for slot in s.options.connections {
            let c .= s.clients[slot]; if c.socket != 0 || c.generation == 0xFFFFFFFFFFFFFFFF { continue; }
            var code: i32 = 0; let socket = lab_net_tcp::accept(s.listener, s.options.send_buffer, code);
            if code == TRANSPORT { s.code = TRANSPORT; stop(s, now); break; }
            if socket == 0 { break; }
            let generation = c.generation + 1; c = Connection { socket: socket, generation: generation, activity: now }; s.counters.accepted++;
            let greeting = F(Id { slot, generation }, "", CONNECTED); reply(s, slot, greeting, now);
            if s.listener == 0 { break; }
        }
    }
    for offset in s.options.connections {
        let slot = (s.cursor + offset) % s.options.connections; let c .= s.clients[slot]; if c.socket == 0 { continue; }
        if !c.closing && s.options.idle_ms > 0 && now - c.activity >= s.options.idle_ms * 1000000 { closing(c, now); }
        if c.closing && now - c.draining >= s.options.drain_ms * 1000000 { s.counters.timed_out++; retire(c, s.counters); continue; }
        if !c.closing {
            if !reserve(c, s.counters, s.options.response_bytes) { s.counters.paused++; }
            else {
                if !c.eof && c.input.len < 256 {
                    var scratch: u8[16] = [0; 16]; let n = lab_net_tcp::receive(c.socket, scratch[0], min(16, 256 - c.input.len));
                    if n == -2 { retire(c, s.counters); continue; }
                    if n == 0 { c.eof = true; }
                    if n > 0 { c.input.append(scratch[..n]); c.activity = now; s.counters.input_peak = max(s.counters.input_peak, c.input.len); }
                }
                var newline: i64 = -1; for byte, i in c.input { if byte == '\n' { newline = i; break; } }
                if newline >= 0 {
                    let end = if newline > 0 && c.input[newline - 1] == '\r' { newline - 1 } else { newline };
                    let response = F(Id { slot, c.generation }, c.input[..end], REQUEST); s.counters.requests++;
                    let left = c.input.len - newline - 1; for i in left { c.input[i] = c.input[newline + 1 + i]; } c.input.resize(left);
                    reply(s, slot, response, now);
                } else if c.input.len == 256 || c.eof {
                    if c.input.len > 0 { c.output.append(if c.eof { "ERR truncated\n" } else { "ERR frame-limit\n" }); }
                    closing(c, now);
                }
            }
        }
        s.counters.output_peak = max(s.counters.output_peak, c.output.len); assert(c.output.len <= 2048);
        if c.sent < c.output.len {
            let remaining = c.output.len - c.sent; let n = lab_net_tcp::send(c.socket, c.output[c.sent], min(remaining, s.options.send_bytes));
            if n == -2 { retire(c, s.counters); continue; }
            if n == -1 { s.counters.blocked++; s.counters.blocked_id = Id { slot, c.generation }; }
            if n > 0 { if n < remaining { s.counters.partial++; } c.sent += n; s.counters.written += n; c.activity = now; }
        }
        if c.sent == c.output.len { c.output.resize(0); c.sent = 0; if c.closing { retire(c, s.counters); } }
    }
    s.cursor = (s.cursor + 1) % s.options.connections;
}
