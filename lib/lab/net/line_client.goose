// Nonblocking progress after a bounded loopback connect; complete lines are owned.
namespace lab_net_line_client;
import std;
import lab.net.tcp;
let OK: i32 = 0; let TRANSPORT: i32 = 2; let LIMIT: i32 = 3; let EOF: i32 = 4;
struct Client { code: i32 = OK, initialized: bool = false, socket: u64 = 0,
    input: u8[..2048] = [], output: u8[..256] = [], sent: i64 = 0 }
fn connect(port: i64, timeout_ms: i64 = 1000) -> Client {
    if !lab_net_tcp::init() { return Client { code: TRANSPORT }; }
    var code: i32 = 0; let socket = lab_net_tcp::connect(port, timeout_ms, code);
    if socket == 0 { assert(lab_net_tcp::shutdown()); return Client { code: TRANSPORT }; }
    Client { initialized: true, socket: socket }
}
fn destroy(c: Client&) {
    if !c.initialized { return; }
    if c.socket != 0 { assert(lab_net_tcp::close(c.socket)); c.socket = 0; }
    assert(lab_net_tcp::shutdown()); c.initialized = false;
}
// Refusal preserves the existing queued command. The owner correlates replies.
fn send(c: Client&, line: const u8[:]) -> bool {
    if c.code != OK || c.socket == 0 || line.len == 0 || line.len > 255 || c.output.len != 0 { return false; }
    for byte in line { if byte == '\n' || byte == '\r' { return false; } }
    c.output.append(line); c.output.push('\n'); true
}
fn poll(c: Client&) {
    if c.code != OK || c.socket == 0 { return; }
    if c.sent < c.output.len {
        let n = lab_net_tcp::send(c.socket, c.output[c.sent], c.output.len - c.sent);
        if n == -2 { c.code = TRANSPORT; return; }
        if n > 0 { c.sent += n; }
        if c.sent == c.output.len { c.sent = 0; c.output.resize(0); }
    }
    if c.input.len < 2048 {
        var scratch: u8[256] = [0; 256]; let n = lab_net_tcp::receive(c.socket, scratch[0], min(256, 2048 - c.input.len));
        if n == -2 { c.code = TRANSPORT; }
        if n == 0 { c.code = EOF; }
        if n > 0 { c.input.append(scratch[..n]); }
    }
}
fn line(c: Client&) -> u8[>..], bool {
    var newline: i64 = -1; for byte, i in c.input { if byte == '\n' { newline = i; break; } }
    if newline < 0 { if c.input.len == 2048 { c.code = LIMIT; } return [], false; }
    let end = if newline > 0 && c.input[newline - 1] == '\r' { newline - 1 } else { newline };
    var owned: u8[>..] = []; owned.append(c.input[..end]);
    let left = c.input.len - newline - 1; for i in left { c.input[i] = c.input[newline + 1 + i]; } c.input.resize(left);
    return owned, true;
}
