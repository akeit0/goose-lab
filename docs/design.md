# API design

The purpose of goose-lab is to discover reusable contracts through applications
before proposing additions to Goose's standard library. The current module
boundary is described in [the library map](libraries.md).

| Goose property | Design choice |
| --- | --- |
| Owned value data; variable-size fields | Borrow slices for synchronous calls; own stored/queued arrays |
| Isolated worker memory and typed queues | Send owned jobs/results; update UI models on the UI thread |
| No destructors | One named owner and explicit close/join paths for native resources |
| Compile-time function values | Do not store Goose closures as native callbacks |
| Flat namespaces | Hierarchical imports `lab.net.http`, flat names `lab_net_http` |
| Generated C runtime | Adapt slices/builders in glue; plain C headers stay independent of emitted names |

## HTTP

```goose
import lab.net.http;

// Once per process on the main thread, before spawning HTTP workers.
assert(lab_net_http::init() == lab_net_http::OK);
{
    let response = lab_net_http::send(lab_net_http::Request {
        url: "https://example.com/",
        method: "GET",
        headers: "Accept: text/html\n",
    }, lab_net_http::Options { timeout_ms: 5000, max_body_bytes: 262144 });
    if response.code != lab_net_http::OK { print(response.error); }
    else { print(response.status, " ", response.body.len); }
}
// After joining all HTTP workers.
lab_net_http::shutdown();
```

`Request` borrows URL, method, request headers, binary body and optional
`ca_file`. `Options` is a flat value with total/connect deadlines,
body/header byte limits and redirect policy. `Response` owns body, raw
headers and error text, alongside transport code and HTTP status.

| Field / operation | Contract |
| --- | --- |
| `code == OK` / `succeeded(response)` | Transfer completed; HTTP 404/500 can still have `OK` |
| `is_success(response)` | Transfer completed and final status is 200–299 |
| `status` | Last HTTP response code, or 0 when no status was received |
| `body` | Binary bytes; on transport/limit failure may contain an incomplete prefix |
| `headers` | Raw blocks, including status lines, informational responses, redirects and trailers |
| `error` | Empty on success; diagnostic text on transport failure |
| `max_body_bytes` | Default 1 MiB; enforced by callback even without Content-Length |
| `max_header_bytes` | Default 64 KiB; cumulative across all header blocks |
| `timeout_ms` / `connect_timeout_ms` | Defaults 15 seconds / 5 seconds; must be positive |
| `follow_redirects` | Default false; at most five redirects when enabled |
| TLS | Certificate and hostname verification always enabled; HTTPS cannot redirect to HTTP |
| Request headers | LF/CRLF-separated name:value lines, optional final newline; controls and invalid names rejected |

Transport codes are `OK`, `INVALID`, `MEMORY`, `TIMEOUT`, `TLS`, `LIMIT`,
`TRANSPORT` and `CANCELLED`. The response status remains separately inspectable
on errors. `Options.cancel` accepts an optional owned one-shot token; a copy
can signal cancellation from another thread. See [cancellation](io/cancellation.md)
for the token lifetime, cooperative transfer loop and completion policy.
libcurl's usual proxy environment variables apply; tests bypass proxies for
loopback. The current transport supports HTTP/1.1 and HTTPS; HTTP/2 dependencies
and content decompression are disabled in this baseline build.

We adopt the request/response separation and status/error distinction from
[Go net/http](https://pkg.go.dev/net/http), plus explicit configuration from
[Rust reqwest](https://docs.rs/reqwest/latest/reqwest/). Goose has no need to
borrow their interface objects, futures, reference-counted client handles or
destructor-driven response streams. This is our design inference, not an
API compatibility layer.

The C backend is [libcurl](https://curl.se/libcurl/c/libcurl-tutorial.html),
so TLS, protocol parsing, DNS and redirects are maintained externally.
Goose owns the application API. The callback limits are necessary even when
a server supplies no length. An easy handle is created per request, so this
transport does not pool connections, retain cookies, stream bodies or
implement an HTTP server. Returning a whole
bounded body avoids a native resource escaping without an ownership policy.


## UI phases and authoring

Clay calculates bounds. Interaction registers current clipped hitboxes and
resolves ordered events once. Painting consumes the resulting state. `lab.ui.view`
lets an application describe a widget's identity, sizing, label and action together
while those execution phases remain separate. See [composition](ui/ui-composition.md).
Stable IDs and explicit application reducers prevent layout changes from changing
ownership or event targets.

Text shaping, cluster boundaries, editing and painting share the same UTF-8 byte
coordinates. Glyph shaping boundaries and Unicode editing boundaries have different
purposes; caret and deletion use extended grapheme clusters. IME preedit stays
transient until one atomic commit. See [Unicode editing](ui/text-foundation.md),
[IME](ui/ime.md) and [emoji](ui/emoji.md).

Retain bounded visible-line meshes and shared font sources; redraw on changes,
timers or input. Scrolling should not duplicate the complete document. Memory
budgets and resource counters are part of the contract rather than a late cleanup.

## References

| Reference | Adaptation here |
| --- | --- |
| [GPUI element phases](https://github.com/zed-industries/zed/blob/main/crates/gpui/src/element.rs) | Separate layout, input registration and painting behind one widget declaration |
| [Flutter architecture](https://docs.flutter.dev/resources/architectural-overview) | Keep application state and controls above rendering/platform services |
| [Qt Quick scene graph](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html) | Batch adjacent compatible geometry while preserving painter order |
| [Clay](https://github.com/nicbarker/clay) | Delegate box sizing to a layout engine with a separate rendering adapter |
| [HarfBuzz](https://harfbuzz.github.io/) and [FreeType](https://freetype.org/) | Shape Unicode before rasterization; keep font data alive until faces close |

These adaptations use Goose's ownership and execution model. They do not provide
API compatibility with the reference frameworks.
