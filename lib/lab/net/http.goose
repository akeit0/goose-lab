// Borrow requests for one synchronous call; return flat, owned response data.
namespace lab_net_http;
import std;
import lab.io.cancel;

let OK: i32 = 0;
let INVALID: i32 = 1;
let MEMORY: i32 = 2;
let TIMEOUT: i32 = 3;
let TLS: i32 = 4;
let LIMIT: i32 = 5;
let TRANSPORT: i32 = 6;
let CANCELLED: i32 = 7;

struct Options {
    timeout_ms: i64 = 15000,
    connect_timeout_ms: i64 = 5000,
    max_body_bytes: i64 = 1048576,
    max_header_bytes: i64 = 65536,
    follow_redirects: bool = false,
    // Zero means no cancellation; nonzero tokens must stay owned until completion.
    cancel: lab_io_cancel::Token = lab_io_cancel::Token {},
}
struct Request {
    url: const u8[:],
    method: const u8[:] = "GET",
    // LF or CRLF separated name:value lines, optional trailing newline.
    headers: const u8[:] = "",
    body: const u8[:] = "",
    // Empty uses the platform trust store/default CA path.
    ca_file: const u8[:] = "",
}
struct Response {
    code: i32,
    status: i64,
    body: u8[],
    // Raw status/header blocks, including redirects and trailers.
    headers: u8[],
    error: u8[],
}

// Process lifetime: call once on main, before any worker; join before shutdown.
extern "glab_http_init" fn init() -> i32;
extern "glab_http_shutdown" fn shutdown();
extern "glab_goose_http_send" fn send_raw(method: const u8[:], url: const u8[:],
    headers: const u8[:], body: const u8[:], timeout_ms: i64, connect_timeout_ms: i64,
    max_body_bytes: i64, max_header_bytes: i64, follow_redirects: bool, ca_file: const u8[:],
    cancel_id: u64, body_out: u8[>..]&, header_out: u8[>..]&, error_out: u8[>..]&, status: i64&) -> i32;

fn send(request: Request, options: Options = Options {}) -> Response {
    var body: u8[>..] = [];
    var headers: u8[>..] = [];
    var error: u8[>..] = [];
    var status: i64 = 0;
    let code = send_raw(request.method, request.url, request.headers, request.body,
        options.timeout_ms, options.connect_timeout_ms, options.max_body_bytes,
        options.max_header_bytes, options.follow_redirects, request.ca_file,
        options.cancel.id, body, headers, error, status);
    return Response { code: code, status: status, body: body, headers: headers, error: error };
}
fn get(url: const u8[:], options: Options = Options {}) -> Response {
    send(Request { url: url }, options)
}
// Transport success and HTTP status are independent, like Go net/http.
fn succeeded(response: const Response&) -> bool { response.code == OK }
fn is_success(response: const Response&) -> bool {
    response.code == OK && response.status >= 200 && response.status < 300
}
