import std;
import os;
import lab.net.line_server;
import lab.net.line_client;
import lab.net.tcp;
fn echo(s: lab_net_line_server::Service&, now: i64) {
    lab_net_line_server::poll(s, now) { id, line, kind =>
        lab_net_line_server::Reply { bytes: if kind == 0 { str("WELCOME\n") } else { str("ECHO ", line, "\n") } }
    };
}
fn receive(s: lab_net_line_server::Service&, c: lab_net_line_client::Client&, expected: const u8[:]) {
    let deadline = clock_ns() + 3000000000;
    loop {
        assert(clock_ns() < deadline); echo(s, clock_ns()); lab_net_line_client::poll(c);
        let line, complete = lab_net_line_client::line(c); if complete { assert(line == expected); break; } sleep_ms(1);
    }
}
fn main() {
    var invalid = lab_net_line_server::create(lab_net_line_server::Options { connections: 17 }); assert(invalid.code == 1 && lab_net_tcp::live() == 0); lab_net_line_server::destroy(invalid);
    var a = lab_net_line_server::create(lab_net_line_server::Options { connections: 1, response_bytes: 64, send_bytes: 1, drain_ms: 1 });
    var b = lab_net_line_server::create(lab_net_line_server::Options { connections: 1 }); assert(a.code == 0 && b.code == 0 && a.port != b.port);
    let old_listener = a.listener;
    var first = lab_net_line_client::connect(a.port); var other = lab_net_line_client::connect(b.port);
    receive(a, first, "WELCOME"); receive(b, other, "WELCOME");
    let old = lab_net_line_server::Id { 0, 1 }; assert(lab_net_line_server::valid(a, old));
    // Unsolicited pushes share the bounded FIFO; failed capacity/stale checks
    // preserve bytes and offsets, including when compaction would be required.
    assert(lab_net_line_server::send(a, old, "PUSH\n")); receive(a, first, "PUSH");
    var large: u8[..2048] = []; for i in 2048 { large.push('x'); }
    assert(lab_net_line_server::send(a, old, large)); let queued = to_bytes([a]);
    assert(!lab_net_line_server::send(a, old, "another") && to_bytes([a]) == queued);
    assert(!lab_net_line_server::send(a, lab_net_line_server::Id { 0, 99 }, "stale") && to_bytes([a]) == queued);
    // Retire this peer rather than wasting thousands of one-byte test writes.
    lab_net_line_client::destroy(first); lab_net_line_server::stop(a, clock_ns());
    echo(a, clock_ns() + 2000000); lab_net_line_server::destroy(a);
    a = lab_net_line_server::create(lab_net_line_server::Options { connections: 1, response_bytes: 64, send_bytes: 1, drain_ms: 1 });
    first = lab_net_line_client::connect(a.port); receive(a, first, "WELCOME");
    assert(lab_net_line_client::send(first, "retained")); let image = to_bytes([first]);
    assert(!lab_net_line_client::send(first, "other") && to_bytes([first]) == image); receive(a, first, "ECHO retained");
    let socket = first.socket; lab_net_line_client::destroy(first); assert(!lab_net_tcp::close(socket));
    let deadline = clock_ns() + 3000000000;
    while lab_net_line_server::valid(a, old) { echo(a, clock_ns()); assert(clock_ns() < deadline); sleep_ms(1); }
    var next = lab_net_line_client::connect(a.port); receive(a, next, "WELCOME");
    assert(!lab_net_line_server::valid(a, old) && lab_net_line_server::valid(a, lab_net_line_server::Id { 0, 2 }));
    var scratch: u8 = 0; assert(lab_net_tcp::receive(socket, scratch, 1) == -2);
    // A deadline expires before the intentionally one-byte write can drain.
    assert(lab_net_line_client::send(next, "pending response"));
    for i in 4 { echo(a, clock_ns()); lab_net_line_client::poll(next); sleep_ms(1); }
    assert(a.clients[0].output.len > a.clients[0].sent);
    let now = clock_ns(); lab_net_line_server::stop(a, now); echo(a, now + 2000000);
    assert(!lab_net_line_server::running(a) && a.counters.timed_out == 1);
    lab_net_line_client::destroy(next); lab_net_line_server::destroy(a);
    assert(!lab_net_tcp::close(old_listener));
    // Closing one server and its clients must preserve the second owner's sockets.
    assert(lab_net_line_client::send(other, "independent")); receive(b, other, "ECHO independent");
    lab_net_line_client::destroy(other); lab_net_line_server::destroy(b); assert(lab_net_tcp::live() == 0);
    print("Reusable line server/client contract passed");
}
