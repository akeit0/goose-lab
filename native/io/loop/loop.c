#include "io/loop/loop.h"
#include "fs/watch/watch.h"
#include "io/process/process.h"
#include "io/cancel/cancel.h"
#include "fs/internal/file_job.h"
#include "fs/internal/write_job.h"
#include <uv.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#ifdef _WIN32
static SRWLOCK gate = SRWLOCK_INIT;
static void lock(void) { AcquireSRWLockExclusive(&gate); }
static void unlock(void) { ReleaseSRWLockExclusive(&gate); }
#else
#include <pthread.h>
static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static void lock(void) { pthread_mutex_lock(&gate); }
static void unlock(void) { pthread_mutex_unlock(&gate); }
#endif
enum { LOOP = 1, WATCH = 2, TIMER = 3, STREAM = 4, FILE_READ = 5, DIRECTORY = 6, FILE_WRITE = 7, SLOTS = 256,
    WATCH_BYTES = 65536, CHUNK_BYTES = 4096, STREAM_PACKET = 32 * (4096 + 5),
    RESCAN = 1, GLAB_OVERFLOW = 2 };
struct context;
struct resource { int kind; uint64_t id; struct context *context; };
struct context {
    struct resource base;
    uv_loop_t loop;
    uv_async_t wake;
    uv_timer_t deadline;
    uv_thread_t owner;
    int64_t resources;
};
struct watcher {
    struct resource base;
    uv_fs_event_t handle;
    int closed, private_loop;
    uint8_t bytes[WATCH_BYTES];
    int64_t count;
    int32_t flags, error;
};
struct timer { struct resource base; uv_timer_t handle; int closed; int64_t fired; };
struct file_resource { struct resource base; struct glab_file_job *job; };
struct write_resource { struct resource base; struct glab_write_job *job; };
struct chunk { struct chunk *next; uint32_t size; uint8_t stream; };
struct input_chunk { struct input_chunk *next; size_t size, used; };
struct stream;
struct sink { struct stream *stream; uint8_t number; };
struct stream {
    struct resource base;
    uv_thread_t thread;
    uv_mutex_t mutex;
    char *program, *cwd, *args;
    int64_t plen, clen, alen, timeout, limit;
    uint64_t cancel;
    struct sink out, err;
    struct chunk *head, *tail;
    int chunks, finished, terminal_seen;
    int32_t failure, result;
    int64_t exit_code;
    struct input_chunk *input_head, *input_tail;
    int input_enabled, input_eof, input_closed, input_stopped, input_dirty, input_chunks;
    int32_t input_result;
    int64_t input_limit, input_pending, input_accepted, input_sent;
};
struct entry { uint32_t generation; int kind, closing; struct resource *resource; };
static struct entry entries[SLOTS];
static struct resource *lookup(uint64_t id, int kind) {
    uint32_t slot = (uint32_t)id, generation = (uint32_t)(id >> 32);
    if (!slot || slot > SLOTS || !generation) return NULL;
    struct entry *e = &entries[slot - 1];
    return e->resource && !e->closing && e->generation == generation && e->kind == kind ? e->resource : NULL;
}
static int32_t owner(struct context *c) {
    uv_thread_t caller = uv_thread_self();
    return uv_thread_equal(&caller, &c->owner) ? GLAB_OK : GLAB_THREAD;
}
static int32_t get(uint64_t id, int kind, struct resource **out) {
    *out = lookup(id, kind); if (!*out) return GLAB_CLOSED;
    return owner(kind == LOOP ? (struct context *)*out : (*out)->context);
}
static int slot_for(int kind, struct context *context) {
    int count = 0, available = -1;
    for (int i = 0; i < SLOTS; ++i) {
        if (entries[i].resource && entries[i].kind == kind) count++;
        if (!entries[i].resource && entries[i].generation != UINT32_MAX && available < 0) available = i;
    }
    int limit = kind == LOOP ? 64 : kind == WATCH ? 32 : kind == TIMER ? 128 : 16;
    return count >= limit || (context && context->resources >= 64) ? -1 : available;
}
static void publish(int slot, struct resource *r, int kind, struct context *c, uint64_t *id) {
    entries[slot].generation++;
    r->kind = kind; r->context = c;
    *id = r->id = ((uint64_t)entries[slot].generation << 32) | (uint32_t)(slot + 1);
    entries[slot].resource = r; entries[slot].kind = kind; entries[slot].closing = 0;
    if (c) c->resources++;
}
static void forget(struct resource *r) {
    entries[(uint32_t)r->id - 1].resource = NULL;
    if (r->context) r->context->resources--;
}
static int32_t error_code(int error) {
    if (!error) return GLAB_OK;
    if (error == UV_ENOENT) return GLAB_MISSING;
    if (error == UV_ENOTDIR) return GLAB_NOT_DIRECTORY;
    if (error == UV_ENOSYS || error == UV_ENOTSUP) return GLAB_UNSUPPORTED;
    if (error == UV_ENOSPC || error == UV_EMFILE || error == UV_ENFILE) return GLAB_LIMIT;
    return error == UV_ENOMEM ? GLAB_MEMORY : GLAB_IO;
}
static int valid_text(const uint8_t *p, int64_t n, int empty) {
    return n >= (empty ? 0 : 1) && n <= 32768 && (!n || (p && !memchr(p, 0, (size_t)n)));
}
static char *owned_text(const uint8_t *p, int64_t n) {
    char *s = malloc((size_t)n + 1); if (!s) return NULL;
    if (n) memcpy(s, p, (size_t)n); s[n] = 0; return s;
}
static void wake(uv_async_t *handle) { (void)handle; }
static void deadline(uv_timer_t *handle) { (void)handle; }
static int pending(struct context *c) {
    for (int i = 0; i < SLOTS; ++i) {
        if (entries[i].closing) continue;
        struct resource *r = entries[i].resource; if (!r || r->context != c) continue;
        if (r->kind == TIMER && ((struct timer *)r)->fired) return 1;
        if (r->kind == WATCH) { struct watcher *w = (struct watcher *)r; if (w->count || w->flags || w->error) return 1; }
        if ((r->kind == FILE_READ || r->kind == DIRECTORY) && glab_file_job_pending(((struct file_resource *)r)->job)) return 1;
        if (r->kind == FILE_WRITE && glab_write_job_pending(((struct write_resource *)r)->job)) return 1;
        if (r->kind == STREAM) {
            struct stream *p = (struct stream *)r; uv_mutex_lock(&p->mutex);
            int ready = p->head || p->input_dirty || (p->finished && !p->terminal_seen); uv_mutex_unlock(&p->mutex);
            if (ready) return 1;
        }
    } return 0;
}
int32_t glab_loop_open(uint64_t *id) {
    *id = 0; lock(); int slot = slot_for(LOOP, NULL);
    if (slot < 0) { unlock(); return GLAB_LIMIT; }
    struct context *c = calloc(1, sizeof *c);
    if (!c) { unlock(); return GLAB_MEMORY; }
    int error = uv_loop_init(&c->loop);
    if (error) { free(c); unlock(); return error_code(error); }
    error = uv_async_init(&c->loop, &c->wake, wake);
    if (error) { uv_loop_close(&c->loop); free(c); unlock(); return error_code(error); }
    error = uv_timer_init(&c->loop, &c->deadline);
    if (error) {
        uv_close((uv_handle_t *)&c->wake, NULL); uv_run(&c->loop, UV_RUN_DEFAULT);
        uv_loop_close(&c->loop); free(c); unlock(); return error_code(error);
    }
    c->owner = uv_thread_self(); publish(slot, &c->base, LOOP, NULL, id); unlock(); return GLAB_OK;
}
int32_t glab_loop_step(uint64_t id, int64_t wait_ms) {
    if (wait_ms < 0 || wait_ms > 60000) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(id, LOOP, &r);
    if (code) { unlock(); return code; } struct context *c = (struct context *)r;
    if (wait_ms && pending(c)) wait_ms = 0;
    /* The owner cannot close its context during this call; other owners must
       remain able to drive independent loops while this one waits. */
    unlock();
    if (wait_ms) {
        uv_update_time(&c->loop); uv_timer_start(&c->deadline, deadline, (uint64_t)wait_ms, 0);
        uv_run(&c->loop, UV_RUN_ONCE); uv_timer_stop(&c->deadline);
    } else { uv_run(&c->loop, UV_RUN_NOWAIT); }
    return GLAB_OK;
}
int32_t glab_loop_info(uint64_t id, int64_t *resources) {
    *resources = 0; lock(); struct resource *r; int32_t code = get(id, LOOP, &r);
    if (!code) *resources = ((struct context *)r)->resources;
    unlock(); return code;
}
static void timer_fired(uv_timer_t *handle) {
    struct timer *t = handle->data; if (t->fired < INT64_MAX) t->fired++;
}
static void timer_closed(uv_handle_t *handle) { ((struct timer *)handle->data)->closed = 1; }
static void watcher_closed(uv_handle_t *handle) { ((struct watcher *)handle->data)->closed = 1; }
static void dispose_timer(struct timer *t) {
    uv_timer_stop(&t->handle); uv_close((uv_handle_t *)&t->handle, timer_closed);
    while (!t->closed) uv_run(&t->base.context->loop, UV_RUN_NOWAIT);
}
static void dispose_watcher(struct watcher *w) {
    uv_fs_event_stop(&w->handle); uv_close((uv_handle_t *)&w->handle, watcher_closed);
    while (!w->closed) uv_run(&w->base.context->loop, UV_RUN_NOWAIT);
}
int32_t glab_loop_timer(uint64_t loop, int64_t delay_ms, int64_t repeat_ms, uint64_t *id) {
    *id = 0;
    if (delay_ms < 0 || delay_ms > 86400000 || repeat_ms < 0 || repeat_ms > 86400000) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(loop, LOOP, &r);
    if (code) { unlock(); return code; } struct context *c = (struct context *)r; int slot = slot_for(TIMER, c);
    if (slot < 0) { unlock(); return GLAB_LIMIT; }
    struct timer *t = calloc(1, sizeof *t); if (!t) { unlock(); return GLAB_MEMORY; }
    t->base.context = c; int error = uv_timer_init(&c->loop, &t->handle);
    if (error) { free(t); unlock(); return error_code(error); } t->handle.data = t;
    uv_update_time(&c->loop); error = uv_timer_start(&t->handle, timer_fired, (uint64_t)delay_ms, (uint64_t)repeat_ms);
    if (error) { dispose_timer(t); free(t); unlock(); return error_code(error); }
    publish(slot, &t->base, TIMER, c, id); unlock(); return GLAB_OK;
}
int32_t glab_timer_start(uint64_t id, int64_t delay_ms, int64_t repeat_ms) {
    if (delay_ms < 0 || delay_ms > 86400000 || repeat_ms < 0 || repeat_ms > 86400000) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(id, TIMER, &r);
    if (!code) {
        struct timer *t = (struct timer *)r; t->fired = 0; uv_update_time(&t->base.context->loop);
        code = error_code(uv_timer_start(&t->handle, timer_fired, (uint64_t)delay_ms, (uint64_t)repeat_ms));
    } unlock(); return code;
}
int32_t glab_timer_stop(uint64_t id) {
    lock(); struct resource *r; int32_t code = get(id, TIMER, &r);
    if (!code) { struct timer *t = (struct timer *)r; uv_timer_stop(&t->handle); t->fired = 0; }
    unlock(); return code;
}
int32_t glab_timer_poll(uint64_t id, int64_t *count) {
    *count = 0; lock(); struct resource *r; int32_t code = get(id, TIMER, &r);
    if (!code) { struct timer *t = (struct timer *)r; *count = t->fired; t->fired = 0; }
    unlock(); return code;
}
static void changed(uv_fs_event_t *handle, const char *name, int events, int status) {
    struct watcher *w = handle->data;
    if (status < 0) { w->error = error_code(status); w->flags |= RESCAN; }
    if (!name || !*name || status < 0) { w->flags |= RESCAN; w->count = 0; return; }
    if (w->flags & RESCAN) return;
    size_t length = strlen(name);
    if (length > 1024 || w->count + (int64_t)length + 2 > WATCH_BYTES) { w->flags |= RESCAN | GLAB_OVERFLOW; w->count = 0; return; }
    w->bytes[w->count++] = (uint8_t)events;
    for (size_t i = 0; i < length; ++i) {
#ifdef _WIN32
        w->bytes[w->count++] = name[i] == '\\' ? '/' : (uint8_t)name[i];
#else
        w->bytes[w->count++] = (uint8_t)name[i];
#endif
    } w->bytes[w->count++] = 0;
}
int32_t glab_loop_watch(uint64_t loop, const uint8_t *path, int64_t length, uint8_t subtree, uint64_t *id) {
    *id = 0; if (!valid_text(path, length, 0)) return GLAB_INVALID;
#if !defined(_WIN32) && !defined(__APPLE__)
    if (subtree) return GLAB_UNSUPPORTED;
#endif
    char *name = owned_text(path, length); if (!name) return GLAB_MEMORY;
    lock(); struct resource *r; int32_t code = get(loop, LOOP, &r);
    if (code) { unlock(); free(name); return code; } struct context *c = (struct context *)r; int slot = slot_for(WATCH, c);
    if (slot < 0) { unlock(); free(name); return GLAB_LIMIT; }
    uv_fs_t stat; int error = uv_fs_stat(&c->loop, &stat, name, NULL);
    int directory = !error && (stat.statbuf.st_mode & 0170000) == 0040000; uv_fs_req_cleanup(&stat);
    if (error || !directory) { unlock(); free(name); return error ? error_code(error) : GLAB_NOT_DIRECTORY; }
    struct watcher *w = calloc(1, sizeof *w); if (!w) { unlock(); free(name); return GLAB_MEMORY; }
    w->base.context = c; error = uv_fs_event_init(&c->loop, &w->handle);
    if (error) { free(w); unlock(); free(name); return error_code(error); } w->handle.data = w;
    error = uv_fs_event_start(&w->handle, changed, name, subtree ? UV_FS_EVENT_RECURSIVE : 0); free(name);
    if (error) { dispose_watcher(w); free(w); unlock(); return error_code(error); }
    publish(slot, &w->base, WATCH, c, id); unlock(); return GLAB_OK;
}
int32_t glab_watch_open(const uint8_t *path, int64_t length, uint8_t subtree, uint64_t *id) {
    uint64_t loop = 0; *id = 0; int32_t code = glab_loop_open(&loop); if (code) return code;
    code = glab_loop_watch(loop, path, length, subtree, id);
    if (code) { glab_loop_close(loop); return code; }
    lock(); ((struct watcher *)lookup(*id, WATCH))->private_loop = 1; unlock(); return GLAB_OK;
}
int32_t glab_watch_poll(uint64_t id, uint8_t *out, int64_t capacity, int64_t *count, int32_t *flags) {
    *count = 0; *flags = 0; if (!out || capacity != WATCH_BYTES) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(id, WATCH, &r);
    if (code) { unlock(); return code; } struct watcher *w = (struct watcher *)r;
    if (w->private_loop) uv_run(&w->base.context->loop, UV_RUN_NOWAIT);
    *count = w->count; *flags = w->flags; memcpy(out, w->bytes, (size_t)w->count);
    code = w->error; w->count = 0; w->flags = 0; w->error = 0; unlock(); return code;
}
static void output(void *context, const uint8_t *bytes, size_t length) {
    struct sink *sink = context; struct stream *p = sink->stream;
    while (length) {
        size_t n = length < CHUNK_BYTES ? length : CHUNK_BYTES;
        uv_mutex_lock(&p->mutex);
        if (!p->failure) {
            struct chunk *c = p->chunks >= 512 ? NULL : malloc(sizeof *c + n);
            if (!c) p->failure = p->chunks >= 512 ? 4 /* process LIMIT */ : 7 /* process MEMORY */;
            else {
                c->next = NULL; c->size = (uint32_t)n; c->stream = sink->number; memcpy(c + 1, bytes, n);
                if (p->tail) p->tail->next = c; else p->head = c; p->tail = c; p->chunks++;
            }
        }
        int failed = p->failure != 0; uv_mutex_unlock(&p->mutex);
        if (failed) glab_cancel_request(p->cancel);
        uv_async_send(&p->base.context->wake); if (failed) return;
        bytes += n; length -= n;
    }
}
static int input_peek(void *arg, uint8_t *bytes, size_t capacity, size_t *length) {
    struct stream *p = arg; *length = 0; uv_mutex_lock(&p->mutex);
    int state = 0;
    if (p->input_head) {
        struct input_chunk *c = p->input_head;
        *length = c->size - c->used; if (*length > capacity) *length = capacity;
        memcpy(bytes, (uint8_t *)(c + 1) + c->used, *length); state = 1;
    } else if (p->input_eof) state = 2;
    uv_mutex_unlock(&p->mutex); return state;
}
static void input_ack(void *arg, size_t length) {
    struct stream *p = arg; uv_mutex_lock(&p->mutex);
    struct input_chunk *c = p->input_head; c->used += length;
    p->input_pending -= (int64_t)length; p->input_sent += (int64_t)length; p->input_dirty = 1;
    if (c->used == c->size) { p->input_head = c->next; if (!p->input_head) p->input_tail = NULL; p->input_chunks--; free(c); }
    uv_mutex_unlock(&p->mutex); uv_async_send(&p->base.context->wake);
}
static void input_closed(void *arg, int32_t result) {
    struct stream *p = arg; uv_mutex_lock(&p->mutex);
    if (!p->input_closed) {
        p->input_closed = 1; p->input_dirty = 1;
        p->input_result = result == 6 || p->input_stopped ? GLAB_CANCELLED : result == 0 && !p->input_pending ? GLAB_OK : GLAB_IO;
        struct input_chunk *c = p->input_head;
        while (c) { struct input_chunk *next = c->next; free(c); c = next; }
        p->input_head = p->input_tail = NULL; p->input_chunks = 0; p->input_pending = 0;
    }
    uv_mutex_unlock(&p->mutex); uv_async_send(&p->base.context->wake);
}
static void process_worker(void *arg) {
    struct stream *p = arg; int64_t exit_code = -1;
    glab_process_input input = {p, input_peek, input_ack, input_closed};
    int32_t result = glab_process_run_input((const uint8_t *)p->program, p->plen, (const uint8_t *)p->cwd, p->clen,
        (const uint8_t *)p->args, p->alen, p->timeout, p->limit, p->cancel, output, &p->out, output, &p->err,
        p->input_enabled ? &input : NULL, &exit_code);
    if (p->input_enabled) input_closed(p, result);
    uv_mutex_lock(&p->mutex); p->result = p->failure ? p->failure : result; p->exit_code = exit_code; p->finished = 1; uv_mutex_unlock(&p->mutex);
    uv_async_send(&p->base.context->wake);
}
static void dispose_stream(struct stream *p, int joined) {
    if (!joined) {
        uv_mutex_lock(&p->mutex); p->input_stopped = 1; uv_mutex_unlock(&p->mutex);
        glab_cancel_request(p->cancel); uv_thread_join(&p->thread);
    }
    glab_cancel_destroy(p->cancel); struct chunk *c = p->head;
    while (c) { struct chunk *next = c->next; free(c); c = next; }
    struct input_chunk *in = p->input_head;
    while (in) { struct input_chunk *next = in->next; free(in); in = next; }
    uv_mutex_destroy(&p->mutex); free(p->program); free(p->cwd); free(p->args);
}
int32_t glab_loop_process(uint64_t loop, const uint8_t *program, int64_t plen,
    const uint8_t *cwd, int64_t clen, const uint8_t *args, int64_t alen,
    int64_t timeout_ms, int64_t max_bytes, uint8_t input, int64_t max_pending, uint64_t *id) {
    *id = 0;
    if (!valid_text(program, plen, 0) || !valid_text(cwd, clen, 1) || alen < 0 || alen > 32768 ||
        (alen && (!args || args[alen - 1])) || timeout_ms < 1 || timeout_ms > 60000 || max_bytes < 1 || max_bytes > 2097152 ||
        max_pending < 1 || max_pending > 2097152) return GLAB_INVALID;
    int argc = 0; for (int64_t i = 0; i < alen; ++i) if (!args[i]) argc++; if (argc > 64) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(loop, LOOP, &r);
    if (code) { unlock(); return code; } struct context *c = (struct context *)r; int slot = slot_for(STREAM, c);
    if (slot < 0) { unlock(); return GLAB_LIMIT; }
    struct stream *p = calloc(1, sizeof *p); if (!p) { unlock(); return GLAB_MEMORY; }
    p->program = owned_text(program, plen); p->cwd = owned_text(cwd, clen); p->args = owned_text(args, alen);
    if (!p->program || !p->cwd || !p->args || uv_mutex_init(&p->mutex)) {
        free(p->program); free(p->cwd); free(p->args); free(p); unlock(); return GLAB_MEMORY;
    }
    p->base.context = c; p->plen = plen; p->clen = clen; p->alen = alen; p->timeout = timeout_ms; p->limit = max_bytes;
    p->input_enabled = input != 0; p->input_limit = max_pending; p->input_closed = !input; p->input_result = input ? -1 : GLAB_OK;
    p->cancel = glab_cancel_create(); p->out.stream = p; p->out.number = 1; p->err.stream = p; p->err.number = 2; p->exit_code = -1;
    if (!p->cancel) { dispose_stream(p, 1); free(p); unlock(); return GLAB_LIMIT; }
    publish(slot, &p->base, STREAM, c, id);
    int error = uv_thread_create(&p->thread, process_worker, p);
    if (error) { forget(&p->base); dispose_stream(p, 1); free(p); *id = 0; unlock(); return error_code(error); }
    unlock(); return GLAB_OK;
}
int32_t glab_stream_send(uint64_t id, const uint8_t *bytes, int64_t length) {
    if (length < 0 || (length && !bytes)) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(id, STREAM, &r);
    if (!code) {
        struct stream *p = (struct stream *)r; uv_mutex_lock(&p->mutex);
        if (!p->input_enabled) code = GLAB_UNSUPPORTED;
        else if (p->input_stopped || p->failure) code = GLAB_CANCELLED;
        else if (p->input_eof || p->input_closed || p->finished) code = GLAB_INPUT_CLOSED;
        else if (length > p->input_limit) code = GLAB_LIMIT;
        else if (length && (length > p->input_limit - p->input_pending || p->input_chunks >= 512)) code = GLAB_WOULD_BLOCK;
        else if (length > INT64_MAX - p->input_accepted) code = GLAB_LIMIT;
        else if (length) {
            struct input_chunk *c = malloc(sizeof *c + (size_t)length);
            if (!c) code = GLAB_MEMORY;
            else {
                c->next = NULL; c->size = (size_t)length; c->used = 0; memcpy(c + 1, bytes, (size_t)length);
                if (p->input_tail) p->input_tail->next = c; else p->input_head = c;
                p->input_tail = c; p->input_chunks++; p->input_pending += length; p->input_accepted += length;
            }
        }
        uv_mutex_unlock(&p->mutex);
    }
    unlock(); return code;
}
int32_t glab_stream_eof(uint64_t id) {
    lock(); struct resource *r; int32_t code = get(id, STREAM, &r);
    if (!code) {
        struct stream *p = (struct stream *)r; uv_mutex_lock(&p->mutex);
        if (!p->input_enabled) code = GLAB_UNSUPPORTED;
        else if (p->input_stopped || p->failure) code = GLAB_CANCELLED;
        else if (p->input_eof) code = GLAB_OK;
        else if (p->input_closed || p->finished) code = GLAB_INPUT_CLOSED;
        else p->input_eof = 1;
        uv_mutex_unlock(&p->mutex);
    }
    unlock(); return code;
}
int32_t glab_stream_cancel(uint64_t id) {
    lock(); struct resource *r; int32_t code = get(id, STREAM, &r);
    if (!code) {
        struct stream *p = (struct stream *)r; uv_mutex_lock(&p->mutex); p->input_stopped = 1; uv_mutex_unlock(&p->mutex);
        glab_cancel_request(p->cancel);
    }
    unlock(); return code;
}
int32_t glab_stream_poll(uint64_t id, uint8_t *out, int64_t capacity,
    int64_t *length, uint8_t *done, int32_t *result, int64_t *exit_code,
    uint8_t *input_enabled, uint8_t *input_eof, uint8_t *closed, int32_t *input_result,
    int64_t *input_pending, int64_t *input_accepted, int64_t *input_sent) {
    *length = 0; *done = 0; *result = -1; *exit_code = -1;
    *input_enabled = 0; *input_eof = 0; *closed = 0; *input_result = -1; *input_pending = 0; *input_accepted = 0; *input_sent = 0;
    if (!out || capacity != STREAM_PACKET) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(id, STREAM, &r);
    if (code) { unlock(); return code; } struct stream *p = (struct stream *)r;
    uv_mutex_lock(&p->mutex);
    *input_enabled = (uint8_t)p->input_enabled; *input_eof = (uint8_t)p->input_eof; *closed = (uint8_t)p->input_closed;
    *input_result = p->input_result; *input_pending = p->input_pending; *input_accepted = p->input_accepted; *input_sent = p->input_sent;
    p->input_dirty = 0;
    for (int i = 0; i < 32 && p->head; ++i) {
        struct chunk *c = p->head; p->head = c->next; if (!p->head) p->tail = NULL; p->chunks--;
        out[(*length)++] = c->stream;
        for (int shift = 0; shift < 32; shift += 8) out[(*length)++] = (uint8_t)(c->size >> shift);
        memcpy(out + *length, c + 1, c->size); *length += c->size; free(c);
    }
    *done = p->finished && !p->head;
    if (*done) { *result = p->result; *exit_code = p->exit_code; p->terminal_seen = 1; }
    uv_mutex_unlock(&p->mutex); unlock(); return GLAB_OK;
}
static int32_t open_file_job(uint64_t loop, const uint8_t *path, int64_t length, int kind, int64_t limit, uint64_t *id) {
    *id = 0;
    if (!valid_text(path, length, 0) || limit < 0 || limit > (kind == FILE_READ ? 2097152 : 4096)) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(loop, LOOP, &r);
    if (code) { unlock(); return code; }
    struct context *c = (struct context *)r; int slot = slot_for(kind, c);
    if (slot < 0) { unlock(); return GLAB_LIMIT; }
    struct file_resource *f = calloc(1, sizeof *f);
    if (!f) { unlock(); return GLAB_MEMORY; }
    f->job = glab_file_job_create(&c->loop, path, length, kind == DIRECTORY, limit);
    if (!f->job) { free(f); unlock(); return GLAB_MEMORY; }
    publish(slot, &f->base, kind, c, id); glab_file_job_start(f->job);
    unlock(); return GLAB_OK;
}
int32_t glab_loop_read(uint64_t loop, const uint8_t *path, int64_t length, int64_t max_bytes, uint64_t *id) {
    return open_file_job(loop, path, length, FILE_READ, max_bytes, id);
}
int32_t glab_loop_directory(uint64_t loop, const uint8_t *path, int64_t length, int64_t max_entries, uint64_t *id) {
    return open_file_job(loop, path, length, DIRECTORY, max_entries, id);
}
int32_t glab_read_poll(uint64_t id, uint8_t *done, int32_t *result, glab_file_sink sink, void *context) {
    *done = 0; *result = -1; if (!sink) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(id, FILE_READ, &r);
    if (!code) glab_file_job_read(((struct file_resource *)r)->job, done, result, sink, context);
    unlock(); return code;
}
int32_t glab_directory_poll(uint64_t id, uint8_t *out, int64_t capacity, int64_t *length, uint8_t *done, int32_t *result) {
    *length = 0; *done = 0; *result = -1;
    if (!out || capacity != GLAB_DIRECTORY_PACKET) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(id, DIRECTORY, &r);
    if (!code) glab_file_job_directory(((struct file_resource *)r)->job, out, length, done, result);
    unlock(); return code;
}
int32_t glab_file_cancel(uint64_t id, int32_t kind) {
    if (kind != FILE_READ && kind != DIRECTORY && kind != FILE_WRITE) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(id, kind, &r);
    if (!code) {
        if (kind == FILE_WRITE) glab_write_job_cancel(((struct write_resource *)r)->job);
        else glab_file_job_cancel(((struct file_resource *)r)->job);
    }
    unlock(); return code;
}
int32_t glab_loop_replace(uint64_t loop, const uint8_t *path, int64_t path_length,
    const uint8_t *bytes, int64_t length, uint8_t automatic, uint8_t sync_file, uint64_t *id) {
    *id = 0;
    if (!valid_text(path, path_length, 0) || length < 0 || (length && !bytes)) return GLAB_INVALID;
    if (length > 2097152) return GLAB_LIMIT;
    lock(); struct resource *r; int32_t code = get(loop, LOOP, &r);
    if (code) { unlock(); return code; }
    struct context *c = (struct context *)r; int slot = slot_for(FILE_WRITE, c);
    if (slot < 0) { unlock(); return GLAB_LIMIT; }
    struct write_resource *w = calloc(1, sizeof *w);
    if (!w) { unlock(); return GLAB_MEMORY; }
    w->job = glab_write_job_create(&c->loop, path, path_length, bytes, length, automatic, sync_file, &code);
    if (!w->job) { free(w); unlock(); return code; }
    publish(slot, &w->base, FILE_WRITE, c, id); glab_write_job_start(w->job); unlock(); return GLAB_OK;
}
int32_t glab_write_commit(uint64_t id) {
    lock(); struct resource *r; int32_t code = get(id, FILE_WRITE, &r);
    if (!code) code = glab_write_job_commit(((struct write_resource *)r)->job);
    unlock(); return code;
}
int32_t glab_write_poll(uint64_t id, uint8_t *ready, uint8_t *done, int32_t *result,
    uint8_t *committed, uint8_t *synced, int32_t *cleanup, int64_t *written, int64_t *size,
    uint64_t *digest, uint8_t *temporary, int64_t capacity, int64_t *temporary_length) {
    *ready = 0; *done = 0; *result = -1; *committed = 0; *synced = 0; *cleanup = 0;
    *written = 0; *size = 0; *digest = 0; *temporary_length = 0;
    if (!temporary || capacity != 32768) return GLAB_INVALID;
    lock(); struct resource *r; int32_t code = get(id, FILE_WRITE, &r);
    if (!code) glab_write_job_poll(((struct write_resource *)r)->job, ready, done, result,
        committed, synced, cleanup, written, size, digest, temporary, temporary_length);
    unlock(); return code;
}
static void dispose_resource(struct resource *r) {
    if (r->kind == TIMER) dispose_timer((struct timer *)r);
    else if (r->kind == WATCH) dispose_watcher((struct watcher *)r);
    else if (r->kind == STREAM) dispose_stream((struct stream *)r, 0);
    else if (r->kind == FILE_WRITE) glab_write_job_dispose(((struct write_resource *)r)->job);
    else { struct file_resource *f = (struct file_resource *)r; glab_file_job_dispose(f->job); }
    /* Closing entries reserve their capacity until native cleanup finishes. */
    lock(); forget(r); unlock(); free(r);
}
/* Under the registry gate, invalidate IDs and signal all children first.
   Waiting for OS work afterward must not lock out unrelated owners. */
static int detach_context(struct context *c, struct resource **children) {
    int count = 0;
    for (int i = 0; i < SLOTS; ++i) {
        if (entries[i].closing) continue;
        struct resource *r = entries[i].resource;
        if (!r || r->context != c) continue;
        if (r->kind == STREAM) {
            struct stream *p = (struct stream *)r; uv_mutex_lock(&p->mutex); p->input_stopped = 1; uv_mutex_unlock(&p->mutex);
            glab_cancel_request(p->cancel);
        }
        else if (r->kind == FILE_READ || r->kind == DIRECTORY) glab_file_job_cancel(((struct file_resource *)r)->job);
        else if (r->kind == FILE_WRITE) glab_write_job_cancel(((struct write_resource *)r)->job);
        children[count++] = r; entries[i].closing = 1;
    }
    entries[(uint32_t)c->base.id - 1].closing = 1; return count;
}
static void dispose_context(struct context *c, struct resource **children, int count) {
    for (int i = 0; i < count; ++i) dispose_resource(children[i]);
    uv_timer_stop(&c->deadline); uv_close((uv_handle_t *)&c->deadline, NULL); uv_close((uv_handle_t *)&c->wake, NULL);
    uv_run(&c->loop, UV_RUN_DEFAULT); uv_loop_close(&c->loop);
    lock(); forget(&c->base); unlock(); free(c);
}
uint8_t glab_loop_resource_close(uint64_t id, int32_t kind) {
    if (kind != WATCH && kind != TIMER && kind != STREAM && kind != FILE_READ && kind != DIRECTORY && kind != FILE_WRITE) return 0;
    lock(); struct resource *r; int32_t code = get(id, kind, &r);
    if (code) { unlock(); return 0; }
    struct context *c = r->context; int private_loop = kind == WATCH && ((struct watcher *)r)->private_loop;
    if (private_loop) {
        struct resource *children[64]; int count = detach_context(c, children); unlock();
        dispose_context(c, children, count);
    } else { entries[(uint32_t)r->id - 1].closing = 1; unlock(); dispose_resource(r); }
    return 1;
}
uint8_t glab_watch_close(uint64_t id) { return glab_loop_resource_close(id, WATCH); }
uint8_t glab_loop_close(uint64_t id) {
    lock(); struct resource *r; int32_t code = get(id, LOOP, &r);
    if (code) { unlock(); return 0; }
    struct context *c = (struct context *)r; struct resource *children[64];
    int count = detach_context(c, children); unlock(); dispose_context(c, children, count); return 1;
}
