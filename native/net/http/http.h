#ifndef GOOSE_LAB_HTTP_H
#define GOOSE_LAB_HTTP_H
#include <stddef.h>
#include <stdint.h>

/* Native internals only; applications use lib/lab/net/http.goose. Buffers are
   borrowed for this call. A sink may append to a Goose data stack. */
typedef struct { const uint8_t *data; size_t len; } glab_bytes;
typedef void (*glab_sink)(void *context, const uint8_t *bytes, size_t len);
typedef struct {
    glab_bytes method, url, headers, body, ca_file;
    int64_t timeout_ms, connect_timeout_ms, max_body_bytes, max_header_bytes;
    int follow_redirects;
    uint64_t cancel_id;
    glab_sink body_sink, header_sink, error_sink;
    void *body_context, *header_context, *error_context;
} glab_http_request;

enum {
    GLAB_HTTP_OK, GLAB_HTTP_INVALID, GLAB_HTTP_MEMORY, GLAB_HTTP_TIMEOUT,
    GLAB_HTTP_TLS, GLAB_HTTP_LIMIT, GLAB_HTTP_TRANSPORT, GLAB_HTTP_CANCELLED
};
/* Initialize before spawning workers; cleanup after joining them. */
int32_t glab_http_init(void);
void glab_http_shutdown(void);
int32_t glab_http_send(const glab_http_request *request, int64_t *status);
#endif
