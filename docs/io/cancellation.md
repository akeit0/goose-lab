# Cancellation and native ownership

`lab.io.cancel` is a reusable one-shot, cross-thread signal. `lab.net.http` consumes it
through `Options.cancel`. API Browser uses it for a Cancel button and for
closing the app during an outstanding request. HTTP remains synchronous on
its caller/worker; no scheduler or asynchronous language feature was added.

## Token lifecycle

```goose
import std;
import lab.io.cancel;
import lab.net.http;

fn main() {
    // Main thread: initialize HTTP before spawning any HTTP worker.
    assert(lab_net_http::init() == lab_net_http::OK);
    var token = lab_io_cancel::create();
    assert(lab_io_cancel::valid(token));
    // A worker can use a copy in Options { cancel: token }.
    // Another thread may call request(token) while that request is running.
    assert(lab_io_cancel::request(token));
    let response = lab_net_http::get("https://example.com/", lab_net_http::Options { cancel: token });
    assert(response.code == lab_net_http::CANCELLED); // No transfer starts.
    lab_io_cancel::destroy(token);
    assert(token.id == 0);
    // Join any workers before HTTP shutdown.
    lab_net_http::shutdown();
}
```

`create` returns a token with a generation-checked native ID. The creator is
the owner and calls `destroy` when finished. Copying a token shares the signal;
it does **not** create another owner. `request` is thread-safe and idempotent
for a live token. Its true result means the signal was accepted, not that a
worker has finished. `requested` and `valid` are thread-safe queries. There is
no reset: create a fresh token for the next operation, avoiding late signals
cancelling a later request. Zero is the default/no-token value for HTTP options,
and is invalid for token operations.

The registry permits 64 simultaneous live/pinned slots. `create` returns zero
when no slot is available; callers must handle this before starting work.
Generations prevent a stale copy from affecting a new token reusing its slot.
An exhausted generation is retired rather than wrapped into an old ID.

Each native HTTP call acquires a private lease. Destroying the owner marks it
cancelled and invalidates public copies immediately, but a slot is not reused
until its leases finish. Thus a progress callback never follows freed/reused
storage. An operation that starts **after** destruction receives `INVALID`
instead of acquiring a stale token. Normally keep ownership until the worker's
completion notification, then destroy. Defensive pinning also makes destruction
during an already-started transfer safe. `destroy` is not a substitute for
joining a worker or keeping its other resources alive.

The registry uses a native mutex (SRW lock on Windows, pthread mutex elsewhere).
It stores only integers and flags, never pointers into a Goose stack. All
registry fields are accessed under that lock. Linking `goose_lab_cancel` supplies
the native functions/header via the existing C adapter; it depends only on
platform threading, not curl or the GUI. `goose_lab_http` links it transitively.

## HTTP behavior

Cancellation returns `lab_net_http::CANCELLED`, separate from `TIMEOUT`, `LIMIT`, TLS
and transport failures. A cancelled response may contain partial headers/body;
check the transport code before treating it as complete JSON. Pre-cancelled
valid requests return immediately. Default HTTP calls without a token retain
the existing easy-perform behavior.

Cancelable calls use a worker-local multi handle, polling with a 50 ms maximum
wait and checking the signal between transfer steps. The progress callback
also aborts active transfers. This avoids relying solely on a callback that
libcurl documents as potentially slowing to about once per second while idle:
[progress callback](https://curl.se/libcurl/c/CURLOPT_XFERINFOFUNCTION.html),
[multi polling](https://curl.se/libcurl/c/curl_multi_poll.html).
No curl handle is operated from the signalling thread, following libcurl's
[threading requirements](https://curl.se/libcurl/c/threadsafe.html).

This is cooperative cancellation, not a hard real-time 50 ms deadline. Native
resolution/TLS/cleanup work and OS scheduling may delay completion. Existing
total/connect timeouts remain the fallback bounds. The Windows loopback tests
check cancellation and join in under two seconds during a genuinely stalled
transfer; they do not claim a latency bound for every DNS/TLS backend.
Cancelling a request also does not undo side effects a server already received.

## Application acceptance and shutdown

`api_browser.client` owns one token per job. Cancel requests stopping, but the client
stays busy until the matching completion arrives. Only then is the token
destroyed and another job enabled. A serial rejects stale completions without
releasing the current job's token. If Cancel was accepted before a queued
completion was processed, the UI treats that result as cancelled even if the
transfer completed successfully: it retains the current records and local edits.

Fetch and Cancel occupy the same layout position but use different control
IDs. Completion between a Cancel press and release removes its capture, so
that release cannot accidentally activate the new Fetch button. Control
identity follows the action's lifetime rather than its screen position.

API Browser's shared `join` helper cancels, sends the stop message, joins the
worker and drains its completion before native resources are destroyed. The
sample uses this for window close/Escape. Explicit finite screenshot runs
can opt to finish their outstanding fetch instead. This makes teardown order
reviewable without destructors, shared Goose references or stored callbacks.

See [validation](../validation.md) for contract and integration checks.
