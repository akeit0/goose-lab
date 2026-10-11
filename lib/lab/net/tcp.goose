// Thin loopback transport. Handles are owned; copies are aliases, never new owners.
namespace lab_net_tcp;
extern "glab_tcp_init" fn init() -> bool;
extern "glab_tcp_shutdown" fn shutdown() -> bool;
extern "glab_tcp_listen" fn listen(port: i64, actual: i64&) -> u64;
extern "glab_tcp_accept" fn accept(listener: u64, send_buffer: i64, code: i32&) -> u64;
extern "glab_tcp_connect" fn connect(port: i64, timeout_ms: i64, code: i32&) -> u64;
extern "glab_tcp_receive" fn receive(socket: u64, out: u8&, capacity: i64) -> i64;
extern "glab_tcp_send" fn send(socket: u64, bytes: const u8&, length: i64) -> i64;
extern "glab_tcp_close" fn close(socket: u64) -> bool;
extern "glab_tcp_live" fn live() -> i64;
