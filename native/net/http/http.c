#include "net/http/http.h"
#include "io/cancel/cancel.h"
#include <curl/curl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

static char *terminated(glab_bytes s) {
    if (s.len == SIZE_MAX || (s.len && (!s.data || memchr(s.data, 0, s.len)))) return NULL;
    char *out = (char *)malloc(s.len + 1);
    if (out) {
        if (s.len) memcpy(out, s.data, s.len);
        out[s.len] = 0;
    }
    return out;
}

static int token_byte(unsigned char c) {
    return c != 0 && ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || strchr("!#$%&'*+-.^_`|~", c) != NULL);
}

typedef struct { glab_sink sink; void *context; size_t used, limit; int exceeded; } receiver;
static size_t receive(char *bytes, size_t size, size_t count, void *opaque) {
    receiver *r = (receiver *)opaque;
    if (size && count > SIZE_MAX / size) { r->exceeded = 1; return 0; }
    size_t n = size * count;
    if (n > r->limit - r->used) { r->exceeded = 1; return 0; }
    if (n && r->sink) r->sink(r->context, (const uint8_t *)bytes, n);
    r->used += n;
    return n;
}

static void error_text(const glab_http_request *r, const char *s) {
    if (r->error_sink) r->error_sink(r->error_context, (const uint8_t *)s, strlen(s));
}

int32_t glab_http_init(void) { return curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK ? GLAB_HTTP_OK : GLAB_HTTP_MEMORY; }
void glab_http_shutdown(void) { curl_global_cleanup(); }

static int progress(void *data, curl_off_t dt, curl_off_t dn, curl_off_t ut, curl_off_t un) {
    (void)dt; (void)dn; (void)ut; (void)un;
    return glab_cancel_check((glab_cancel_lease)data) ? 1 : 0;
}
/* All curl handles remain worker-local. Polling also checks cancellation during
   idle periods, when the ordinary progress callback may run only once/second. */
static CURLcode perform_cancelable(CURL *easy, glab_cancel_lease lease, char *detail) {
    CURLM *multi = curl_multi_init(); if (!multi) return CURLE_OUT_OF_MEMORY;
    CURLMcode m = curl_multi_add_handle(multi, easy);
    CURLcode result = CURLE_FAILED_INIT; int added = m == CURLM_OK;
    while (m == CURLM_OK) {
        if (glab_cancel_check(lease)) { result = CURLE_ABORTED_BY_CALLBACK; break; }
        int running = 0; m = curl_multi_perform(multi, &running);
        if (m != CURLM_OK) break;
        if (!running) {
            int remaining = 0; CURLMsg *msg;
            while ((msg = curl_multi_info_read(multi, &remaining))) {
                if (msg->msg == CURLMSG_DONE && msg->easy_handle == easy) { result = msg->data.result; break; }
            } break;
        }
        m = curl_multi_poll(multi, NULL, 0, 50, NULL);
    }
    if (m != CURLM_OK) {
        result = m == CURLM_OUT_OF_MEMORY ? CURLE_OUT_OF_MEMORY : CURLE_FAILED_INIT;
        const char *message = curl_multi_strerror(m);
        size_t n = strlen(message); if (n >= CURL_ERROR_SIZE) n = CURL_ERROR_SIZE - 1;
        memcpy(detail, message, n); detail[n] = 0;
    }
    if (added) curl_multi_remove_handle(multi, easy);
    curl_multi_cleanup(multi); return result;
}

int32_t glab_http_send(const glab_http_request *r, int64_t *status) {
    *status = 0;
    if (r->timeout_ms <= 0 || r->timeout_ms > LONG_MAX ||
        r->connect_timeout_ms <= 0 || r->connect_timeout_ms > LONG_MAX ||
        r->max_body_bytes < 0 || r->max_header_bytes < 0 ||
        (uint64_t)r->max_body_bytes > SIZE_MAX || (uint64_t)r->max_header_bytes > SIZE_MAX ||
        r->url.len == 0 || r->url.len > 16384 || r->method.len == 0 || r->method.len > 32 ||
        r->headers.len > 65536 || r->ca_file.len > 4096 ||
        (r->body.len && !r->body.data)) {
        error_text(r, "invalid request options or input size");
        return GLAB_HTTP_INVALID;
    }
    /* Strings must not be silently truncated at an embedded NUL. */
    glab_bytes strings[] = {r->method, r->url, r->headers, r->ca_file};
    for (size_t i = 0; i < sizeof(strings) / sizeof(strings[0]); i++) {
        if (strings[i].len && (!strings[i].data || memchr(strings[i].data, 0, strings[i].len))) {
            error_text(r, "NUL in request string"); return GLAB_HTTP_INVALID;
        }
    }
    for (size_t i = 0; i < r->method.len; i++) {
        if (!token_byte(r->method.data[i])) { error_text(r, "invalid HTTP method"); return GLAB_HTTP_INVALID; }
    }

    glab_cancel_lease cancel = NULL;
    if (r->cancel_id) {
        if (!glab_cancel_acquire(r->cancel_id, &cancel)) {
            error_text(r, "invalid or destroyed cancellation token"); return GLAB_HTTP_INVALID;
        }
        if (glab_cancel_check(cancel)) {
            glab_cancel_release(cancel); error_text(r, "request cancelled"); return GLAB_HTTP_CANCELLED;
        }
    }

    char *method = terminated(r->method), *url = terminated(r->url);
    char *headers = terminated(r->headers), *ca = terminated(r->ca_file);
    CURL *easy = NULL;
    struct curl_slist *list = NULL;
    int32_t result = GLAB_HTTP_MEMORY;
    CURLcode code = CURLE_OK;
    char detail[CURL_ERROR_SIZE] = {0};
    receiver body_out = {r->body_sink, r->body_context, 0, (size_t)r->max_body_bytes, 0};
    receiver header_out = {r->header_sink, r->header_context, 0, (size_t)r->max_header_bytes, 0};
    if (!method || !url || !headers || !ca || !(easy = curl_easy_init())) goto done;
    /* Require an explicit scheme. Restrict both first request and redirects. */
    if (strncmp(url, "http://", 7) && strncmp(url, "https://", 8)) {
        result = GLAB_HTTP_INVALID; strcpy(detail, "expected http:// or https:// URL"); goto done;
    }
    if (strchr(url, '\r') || strchr(url, '\n')) {
        result = GLAB_HTTP_INVALID; strcpy(detail, "newline in URL"); goto done;
    }
    /* One name:value per LF/CRLF line. Reject bare CR, invalid names, control
       bytes, and empty lines; there is no C-string header injection. */
    char *line = headers;
    while (*line) {
        char *end = strchr(line, '\n');
        if (end) *end = 0;
        size_t len = strlen(line);
        if (end && len && line[len - 1] == '\r') line[--len] = 0;
        char *colon = strchr(line, ':');
        if (!len || !colon || colon == line) {
            result = GLAB_HTTP_INVALID; strcpy(detail, "expected header name:value"); goto done;
        }
        for (char *p = line; p < colon; p++) {
            if (!token_byte((unsigned char)*p)) {
                result = GLAB_HTTP_INVALID; strcpy(detail, "invalid header name"); goto done;
            }
        }
        for (char *p = colon + 1; *p; p++) {
            unsigned char c = (unsigned char)*p;
            if ((c < 32 && c != '\t') || c == 127) {
                result = GLAB_HTTP_INVALID; strcpy(detail, "control byte in header value"); goto done;
            }
        }
        struct curl_slist *next = curl_slist_append(list, line);
        if (!next) goto done;
        list = next;
        if (!end) break;
        line = end + 1;
    }

    /* Check every setopt: a feature mismatch must fail visibly. */
#define SET(option, value) do { code = curl_easy_setopt(easy, option, value); \
    if (code != CURLE_OK) { result = GLAB_HTTP_TRANSPORT; goto done; } } while (0)
    SET(CURLOPT_URL, url);
    SET(CURLOPT_PROTOCOLS_STR, "http,https");
    /* HTTPS redirects cannot downgrade to plaintext. */
    SET(CURLOPT_REDIR_PROTOCOLS_STR, strncmp(url, "https://", 8) == 0 ? "https" : "http,https");
    SET(CURLOPT_FOLLOWLOCATION, r->follow_redirects ? 1L : 0L);
    SET(CURLOPT_MAXREDIRS, 5L);
    SET(CURLOPT_TIMEOUT_MS, (long)r->timeout_ms);
    SET(CURLOPT_CONNECTTIMEOUT_MS, (long)r->connect_timeout_ms);
    SET(CURLOPT_NOSIGNAL, 1L);
    if (cancel) {
        SET(CURLOPT_NOPROGRESS, 0L);
        SET(CURLOPT_XFERINFOFUNCTION, progress);
        SET(CURLOPT_XFERINFODATA, cancel);
    }
    SET(CURLOPT_SSL_VERIFYPEER, 1L);
    SET(CURLOPT_SSL_VERIFYHOST, 2L);
    if (*ca) SET(CURLOPT_CAINFO, ca);
    SET(CURLOPT_ERRORBUFFER, detail);
    SET(CURLOPT_WRITEFUNCTION, receive);
    SET(CURLOPT_WRITEDATA, &body_out);
    SET(CURLOPT_HEADERFUNCTION, receive);
    SET(CURLOPT_HEADERDATA, &header_out);
    SET(CURLOPT_USERAGENT, "goose-lab/0.1");
    SET(CURLOPT_HTTPHEADER, list);
    /* Configure uploads before CUSTOMREQUEST: it sets only the wire method.
       libcurl retains POST->GET redirect semantics for a real POST. */
    if (r->body.len || strcmp(method, "POST") == 0 || strcmp(method, "PUT") == 0 || strcmp(method, "PATCH") == 0) {
        SET(CURLOPT_POSTFIELDS, r->body.len ? (const char *)r->body.data : "");
        SET(CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)r->body.len);
    }
    if (strcmp(method, "HEAD") == 0) SET(CURLOPT_NOBODY, 1L);
    if ((strcmp(method, "GET") != 0 && strcmp(method, "POST") != 0) ||
        (strcmp(method, "GET") == 0 && r->body.len))
        SET(CURLOPT_CUSTOMREQUEST, method);
    code = cancel ? perform_cancelable(easy, cancel, detail) : curl_easy_perform(easy);
    long http_status = 0;
    curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &http_status);
    *status = http_status;
    if (body_out.exceeded || header_out.exceeded) {
        result = GLAB_HTTP_LIMIT; strcpy(detail, "response exceeds configured byte limit");
    } else if (code == CURLE_OK) result = GLAB_HTTP_OK;
    else if (code == CURLE_ABORTED_BY_CALLBACK) { result = GLAB_HTTP_CANCELLED; strcpy(detail, "request cancelled"); }
    else if (code == CURLE_OPERATION_TIMEDOUT) result = GLAB_HTTP_TIMEOUT;
    else if (code == CURLE_PEER_FAILED_VERIFICATION || code == CURLE_SSL_CONNECT_ERROR ||
             code == CURLE_SSL_CACERT_BADFILE || code == CURLE_SSL_CERTPROBLEM)
        result = GLAB_HTTP_TLS;
    else if (code == CURLE_OUT_OF_MEMORY) result = GLAB_HTTP_MEMORY;
    else if (code == CURLE_URL_MALFORMAT || code == CURLE_UNSUPPORTED_PROTOCOL) result = GLAB_HTTP_INVALID;
    else result = GLAB_HTTP_TRANSPORT;
#undef SET
done:
    if (result != GLAB_HTTP_OK)
        error_text(r, detail[0] ? detail : result == GLAB_HTTP_MEMORY ? "native allocation failed" : curl_easy_strerror(code));
    if (easy) curl_easy_cleanup(easy);
    curl_slist_free_all(list);
    free(method); free(url); free(headers); free(ca);
    glab_cancel_release(cancel);
    return result;
}
