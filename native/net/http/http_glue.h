#ifndef GOOSE_LAB_HTTP_GLUE_H
#define GOOSE_LAB_HTTP_GLUE_H
/* Runtime adapter, included after generated Goose runtime types. */
#include "net/http/http.h"
static void glab_goose_sink(void *context, const uint8_t *bytes, size_t len) {
    gs_bld_append(*(gs_rref *)context, bytes, (int64_t)len);
}
static int32_t glab_goose_http_send(sl_u8 method, sl_u8 url, sl_u8 headers, sl_u8 body,
    int64_t timeout_ms, int64_t connect_timeout_ms, int64_t max_body_bytes,
    int64_t max_header_bytes, uint8_t follow_redirects, sl_u8 ca_file,
    uint64_t cancel_id, gs_rref body_out, gs_rref header_out, gs_rref error_out, int64_t *status) {
    glab_http_request r = {
        {method.data, (size_t)method.len}, {url.data, (size_t)url.len},
        {headers.data, (size_t)headers.len}, {body.data, (size_t)body.len},
        {ca_file.data, (size_t)ca_file.len},
        timeout_ms, connect_timeout_ms, max_body_bytes, max_header_bytes,
        follow_redirects, cancel_id, glab_goose_sink, glab_goose_sink, glab_goose_sink,
        &body_out, &header_out, &error_out
    };
    return glab_http_send(&r, status);
}
#endif
