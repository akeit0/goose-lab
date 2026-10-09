import std;
import os;
import lab.net.http;
import lab.io.cancel;

struct WorkerResult { response: lab_net_http::Response }
thread_fn check_worker(url: u8[]) { qput(WorkerResult { response: lab_net_http::get(url) }); }
struct CancelReady {}
struct CancelResult { code: i32 }
thread_fn cancel_worker(url: u8[], token: lab_io_cancel::Token) {
    qput(CancelReady {});
    let response = lab_net_http::get(url, lab_net_http::Options { timeout_ms: 8000, cancel: token });
    qput(CancelResult { code: response.code });
}

fn main() {
    let argv = args();
    assert(argv.len >= 5);
    let base = argv[1];
    let tls_base = argv[2];
    let certificate = argv[3];
    let wrong_host = argv[4];
    assert(lab_net_http::init() == lab_net_http::OK);
    {
        let r = lab_net_http::get(str(base, "/hello"));
        assert(lab_net_http::is_success(r)); assert(r.status == 200);
        assert(r.body == "Hello from the fixture\n");
        assert(find(r.headers, "X-Goose-Fixture: yes") >= 0);
        let missing = lab_net_http::get(str(base, "/missing"));
        assert(lab_net_http::succeeded(missing)); assert(!lab_net_http::is_success(missing));
        assert(missing.status == 404);
        let binary = lab_net_http::send(lab_net_http::Request {
            url: str(base, "/echo"), method: "POST",
            headers: "Content-Type: application/octet-stream\r\nX-Test: goose\n",
            body: "a\0b",
        });
        assert(binary.code == lab_net_http::OK); assert(binary.body == "a\0b");
        let put = lab_net_http::send(lab_net_http::Request { url: str(base, "/echo"), method: "PUT", body: "put" });
        assert(put.code == lab_net_http::OK); assert(put.body == "put");
        let head = lab_net_http::send(lab_net_http::Request { url: str(base, "/hello"), method: "HEAD" });
        assert(head.status == 200); assert(head.body.len == 0);
        let redirect = lab_net_http::get(str(base, "/redirect"));
        assert(redirect.status == 302);
        let followed = lab_net_http::get(str(base, "/redirect"), lab_net_http::Options { follow_redirects: true });
        assert(followed.status == 200); assert(followed.body == r.body);
        let looped = lab_net_http::get(str(base, "/loop"), lab_net_http::Options { follow_redirects: true });
        assert(looped.code == lab_net_http::TRANSPORT);
        let file_redirect = lab_net_http::get(str(base, "/file-redirect"), lab_net_http::Options { follow_redirects: true });
        assert(file_redirect.code != lab_net_http::OK);
        let limited = lab_net_http::get(str(base, "/large"), lab_net_http::Options { max_body_bytes: 32 });
        assert(limited.code == lab_net_http::LIMIT); assert(limited.body.len <= 32);
        let chunked = lab_net_http::get(str(base, "/chunked"), lab_net_http::Options { max_body_bytes: 32 });
        assert(chunked.code == lab_net_http::LIMIT); assert(chunked.body.len <= 32);
        let headers = lab_net_http::get(str(base, "/hello"), lab_net_http::Options { max_header_bytes: 12 });
        assert(headers.code == lab_net_http::LIMIT); assert(headers.headers.len <= 12);
        let timed = lab_net_http::get(str(base, "/slow"), lab_net_http::Options { timeout_ms: 60 });
        assert(timed.code == lab_net_http::TIMEOUT);
        let bad_url = lab_net_http::get("file:///etc/passwd");
        assert(bad_url.code == lab_net_http::INVALID);
        let nul = lab_net_http::get("http://localhost/\0hidden");
        assert(nul.code == lab_net_http::INVALID);
        let method = lab_net_http::send(lab_net_http::Request { url: base, method: "GET\r\nX: y" });
        assert(method.code == lab_net_http::INVALID);
        let bad_headers = lab_net_http::send(lab_net_http::Request { url: base, headers: "X: a\rInjected: bad" });
        assert(bad_headers.code == lab_net_http::INVALID);
        let bare_cr = lab_net_http::send(lab_net_http::Request { url: base, headers: "X: a\r" });
        assert(bare_cr.code == lab_net_http::INVALID);
        let bad_options = lab_net_http::get(base, lab_net_http::Options { timeout_ms: 0 });
        assert(bad_options.code == lab_net_http::INVALID);
        let tls = lab_net_http::get(tls_base);
        assert(tls.code == lab_net_http::TLS);
        let trusted = lab_net_http::send(lab_net_http::Request { url: tls_base, ca_file: certificate });
        assert(trusted.code == lab_net_http::OK); assert(trusted.body == r.body);
        let mismatch = lab_net_http::send(lab_net_http::Request { url: wrong_host, ca_file: certificate });
        assert(mismatch.code == lab_net_http::TLS);
        let downgrade = lab_net_http::send(lab_net_http::Request { url: str(tls_base, "/downgrade"), ca_file: certificate },
                                    lab_net_http::Options { follow_redirects: true });
        assert(downgrade.code != lab_net_http::OK); assert(downgrade.status == 302);
        // Responses own their bytes and can cross isolated typed queues.
        let worker = thread_spawn(check_worker, str(base, "/hello"));
        let message = qget<WorkerResult>();
        thread_wait(worker);
        assert(message.response.body == r.body);
        cancellation(base, tls_base, certificate);
    }
    lab_net_http::shutdown();
    print("HTTP contract passed");
}
fn cancellation(base: const u8[:], tls_base: const u8[:], certificate: const u8[:]) {
    var token = lab_io_cancel::create(); assert(lab_io_cancel::valid(token) && !lab_io_cancel::requested(token));
    assert(lab_io_cancel::request(token) && lab_io_cancel::request(token));
    let pre = lab_net_http::get(str(base, "/hello"), lab_net_http::Options { cancel: token }); assert(pre.code == lab_net_http::CANCELLED && pre.status == 0 && pre.body.len == 0);
    let stale = token; lab_io_cancel::destroy(token); assert(token.id == 0 && !lab_io_cancel::valid(stale));
    let bad = lab_net_http::get(str(base, "/hello"), lab_net_http::Options { cancel: stale }); assert(bad.code == lab_net_http::INVALID);
    for drop_owner in [false, true] {
        var active = lab_io_cancel::create(); let worker = thread_spawn(cancel_worker, str(base, "/cancel-wait"), active);
        let ready = qget<CancelReady>();
        // Server barrier confirms that the worker has entered a live transfer.
        let started = lab_net_http::get(str(base, "/cancel-ready")); assert(started.status == 200);
        let before = clock_ns();
        if drop_owner { lab_io_cancel::destroy(active); } else { assert(lab_io_cancel::request(active)); }
        let result = qget<CancelResult>(); thread_wait(worker);
        assert(result.code == lab_net_http::CANCELLED && clock_ns() - before < 2000000000);
        lab_io_cancel::destroy(active);
    }
    var success = lab_io_cancel::create(); let done = lab_net_http::get(str(base, "/hello"), lab_net_http::Options { cancel: success }); assert(done.code == lab_net_http::OK);
    let trusted = lab_net_http::send(lab_net_http::Request { url: tls_base, ca_file: certificate }, lab_net_http::Options { cancel: success }); assert(trusted.code == lab_net_http::OK);
    let rejected = lab_net_http::get(tls_base, lab_net_http::Options { cancel: success }); assert(rejected.code == lab_net_http::TLS);
    let redirect = lab_net_http::get(str(base, "/redirect"), lab_net_http::Options { follow_redirects: true, cancel: success }); assert(redirect.status == 200 && redirect.code == lab_net_http::OK);
    let bounded = lab_net_http::get(str(base, "/chunked"), lab_net_http::Options { max_body_bytes: 32, cancel: success }); assert(bounded.code == lab_net_http::LIMIT);
    let deadline = lab_net_http::get(str(base, "/slow"), lab_net_http::Options { timeout_ms: 60, cancel: success }); assert(deadline.code == lab_net_http::TIMEOUT);
    lab_io_cancel::destroy(success);
}
