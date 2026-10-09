#include "fs/internal/write_job.h"
#include <stdlib.h>
#include <string.h>

enum write_stage { CHECK_TARGET, CREATE_TEMP, SET_MODE, WRITE_TEMP, SYNC_TEMP,
    CLOSE_TEMP, RECHECK_TARGET, PUBLISH, REMOVE_TEMP };
struct glab_write_job {
    uv_loop_t *loop;
    uv_fs_t request;
    uv_buf_t buffer;
    uv_file file;
    char *path, *temporary;
    uint8_t *bytes;
    int64_t length, written;
    uint64_t digest;
    int mode, automatic, sync_file, synced, created, active, cancelled;
    int ready, ready_seen, done, terminal_seen, committed;
    int32_t result, cleanup;
    enum write_stage stage;
};
static void submit_write(struct glab_write_job *p, enum write_stage stage);
static void finish_write(struct glab_write_job *p) {
    if (p->cancelled && !p->committed) p->result = GLAB_CANCELLED;
    p->ready = 0; p->done = 1; free(p->bytes); p->bytes = NULL;
}
static void cleanup_write(struct glab_write_job *p, int32_t code) {
    if (p->result == GLAB_OK) p->result = code;
    p->ready = 0;
    if (p->file >= 0) submit_write(p, CLOSE_TEMP);
    else if (p->created) submit_write(p, REMOVE_TEMP);
    else finish_write(p);
}
static void completed_write(uv_fs_t *request) {
    struct glab_write_job *p = request->data;
    int64_t result = request->result;
    enum write_stage stage = p->stage;
    int regular = 1;
    p->active = 0;
    if (result >= 0) {
        if (stage == CREATE_TEMP) {
            p->file = (uv_file)result; p->created = 1;
            /* mkstemp owns req.path; capture its actual name before cleanup. */
            memcpy(p->temporary, request->path, strlen(request->path) + 1);
        } else if (stage == CHECK_TARGET || stage == RECHECK_TARGET) {
            regular = (request->statbuf.st_mode & 0170000) == 0100000;
            if (stage == CHECK_TARGET) p->mode = (int)(request->statbuf.st_mode & 0777);
        }
    }
    uv_fs_req_cleanup(request);
    if (stage == PUBLISH && result >= 0) {
        /* The visibility boundary wins even if cancellation arrived in flight. */
        p->committed = 1; p->created = 0; p->result = GLAB_OK; finish_write(p); return;
    }
    if (stage == REMOVE_TEMP) {
        if (result < 0 && result != UV_ENOENT) p->cleanup = glab_file_error(result);
        else p->created = 0;
        finish_write(p); return;
    }
    if (stage == CLOSE_TEMP) {
        p->file = -1;
        if (result < 0) {
            p->cleanup = glab_file_error(result);
            if (p->result == GLAB_OK) p->result = p->cleanup;
        }
        free(p->bytes); p->bytes = NULL;
        if (p->cancelled || p->result != GLAB_OK) { cleanup_write(p, GLAB_CANCELLED); return; }
        if (p->automatic) submit_write(p, RECHECK_TARGET);
        else p->ready = 1;
        return;
    }
    if (p->cancelled) { cleanup_write(p, GLAB_CANCELLED); return; }
    if (stage == CHECK_TARGET || stage == RECHECK_TARGET) {
        if (result < 0 && result != UV_ENOENT) { cleanup_write(p, glab_file_error(result)); return; }
        if (!regular) { cleanup_write(p, GLAB_NOT_REGULAR); return; }
        submit_write(p, stage == CHECK_TARGET ? CREATE_TEMP : PUBLISH); return;
    }
    if (result < 0) { cleanup_write(p, glab_file_error(result)); return; }
    switch (stage) {
    case CREATE_TEMP:
#ifdef _WIN32
        submit_write(p, WRITE_TEMP);
#else
        submit_write(p, SET_MODE);
#endif
        break;
    case SET_MODE: submit_write(p, WRITE_TEMP); break;
    case WRITE_TEMP:
        if (!result || result > p->length - p->written) { cleanup_write(p, GLAB_IO); break; }
        for (int64_t i = 0; i < result; ++i) {
            p->digest ^= p->bytes[p->written + i]; p->digest *= UINT64_C(1099511628211);
        }
        p->written += result;
        submit_write(p, p->written < p->length ? WRITE_TEMP : p->sync_file ? SYNC_TEMP : CLOSE_TEMP);
        break;
    case SYNC_TEMP: p->synced = 1; submit_write(p, CLOSE_TEMP); break;
    default: break;
    }
}
static void submit_write(struct glab_write_job *p, enum write_stage stage) {
    /* Empty payload still creates/flushes/closes a replacement file. */
    if (stage == WRITE_TEMP && p->length == 0) stage = p->sync_file ? SYNC_TEMP : CLOSE_TEMP;
    p->stage = stage; p->request.data = p;
    int error = 0;
    switch (stage) {
    case CHECK_TARGET: case RECHECK_TARGET: error = uv_fs_lstat(p->loop, &p->request, p->path, completed_write); break;
    case CREATE_TEMP: error = uv_fs_mkstemp(p->loop, &p->request, p->temporary, completed_write); break;
    case SET_MODE: error = uv_fs_fchmod(p->loop, &p->request, p->file, p->mode, completed_write); break;
    case WRITE_TEMP: {
        int64_t remaining = p->length - p->written;
        unsigned int n = (unsigned int)(remaining < 65536 ? remaining : 65536);
        p->buffer = uv_buf_init((char *)p->bytes + p->written, n);
        error = uv_fs_write(p->loop, &p->request, p->file, &p->buffer, 1, p->written, completed_write); break;
    }
    case SYNC_TEMP: error = uv_fs_fsync(p->loop, &p->request, p->file, completed_write); break;
    case CLOSE_TEMP: error = uv_fs_close(p->loop, &p->request, p->file, completed_write); break;
    case PUBLISH: error = uv_fs_rename(p->loop, &p->request, p->temporary, p->path, completed_write); break;
    case REMOVE_TEMP: error = uv_fs_unlink(p->loop, &p->request, p->temporary, completed_write); break;
    }
    if (error >= 0) { p->active = 1; return; }
    if (stage == CLOSE_TEMP || stage == REMOVE_TEMP) {
        /* Cleanup cannot retain a request that failed submission. */
        uv_fs_req_cleanup(&p->request);
        int cleaned = stage == CLOSE_TEMP ? uv_fs_close(p->loop, &p->request, p->file, NULL)
            : uv_fs_unlink(p->loop, &p->request, p->temporary, NULL);
        p->request.data = p; p->request.result = cleaned;
        if (stage == CLOSE_TEMP && p->result == GLAB_OK) p->result = glab_file_error(error);
        completed_write(&p->request); return;
    }
    p->request.result = error; completed_write(&p->request);
}
struct glab_write_job *glab_write_job_create(uv_loop_t *loop, const uint8_t *path, int64_t path_length,
    const uint8_t *bytes, int64_t length, int automatic, int sync_file, int32_t *code) {
    int64_t parent = 0;
    for (int64_t i = 0; i < path_length; ++i) {
        if (path[i] == '/') parent = i + 1;
#ifdef _WIN32
        if (path[i] == '\\') parent = i + 1;
#endif
    }
#ifdef _WIN32
    if (!parent && path_length >= 2 && path[1] == ':') parent = 2;
#endif
    const char suffix[] = ".goose-lab-save-XXXXXX";
    if (parent + sizeof suffix > 32769) { *code = GLAB_INVALID; return NULL; }
    struct glab_write_job *p = calloc(1, sizeof *p);
    if (!p) { *code = GLAB_MEMORY; return NULL; }
    p->path = malloc((size_t)path_length + 1);
    p->temporary = malloc((size_t)parent + sizeof suffix);
    p->bytes = malloc((size_t)length + 1);
    if (!p->path || !p->temporary || !p->bytes) {
        free(p->path); free(p->temporary); free(p->bytes); free(p); *code = GLAB_MEMORY; return NULL;
    }
    memcpy(p->path, path, (size_t)path_length); p->path[path_length] = 0;
    memcpy(p->temporary, path, (size_t)parent); memcpy(p->temporary + parent, suffix, sizeof suffix);
    if (length) memcpy(p->bytes, bytes, (size_t)length);
    p->loop = loop; p->file = -1; p->mode = 0600; p->automatic = automatic; p->sync_file = sync_file;
    p->length = length; p->digest = UINT64_C(14695981039346656037); *code = GLAB_OK; return p;
}
void glab_write_job_start(struct glab_write_job *p) { submit_write(p, CHECK_TARGET); }
int glab_write_job_pending(const struct glab_write_job *p) {
    return (p->ready && !p->ready_seen) || (p->done && !p->terminal_seen);
}
int32_t glab_write_job_commit(struct glab_write_job *p) {
    if (!p->ready || p->cancelled || p->done) return GLAB_NOT_READY;
    p->ready = 0; submit_write(p, RECHECK_TARGET); return GLAB_OK;
}
void glab_write_job_poll(struct glab_write_job *p, uint8_t *ready, uint8_t *done, int32_t *result,
    uint8_t *committed, uint8_t *synced, int32_t *cleanup, int64_t *written, int64_t *size,
    uint64_t *digest, uint8_t *temporary, int64_t *temporary_length) {
    *ready = (uint8_t)p->ready; *done = (uint8_t)p->done; *result = p->done ? p->result : -1;
    *committed = (uint8_t)p->committed; *synced = (uint8_t)p->synced; *cleanup = p->cleanup;
    *written = p->written; *size = p->committed ? p->length : 0; *digest = p->committed ? p->digest : 0;
    *temporary_length = p->done && p->created ? (int64_t)strlen(p->temporary) : 0;
    if (*temporary_length) memcpy(temporary, p->temporary, (size_t)*temporary_length);
    if (p->ready) p->ready_seen = 1;
    if (p->done) p->terminal_seen = 1;
}
void glab_write_job_cancel(struct glab_write_job *p) {
    if (p->done || p->committed) return;
    p->cancelled = 1; p->ready = 0;
    if (p->active) {
        if (p->stage != CLOSE_TEMP && p->stage != REMOVE_TEMP) uv_cancel((uv_req_t *)&p->request);
    } else cleanup_write(p, GLAB_CANCELLED);
}
void glab_write_job_dispose(struct glab_write_job *p) {
    glab_write_job_cancel(p);
    while (!p->done) uv_run(p->loop, UV_RUN_ONCE);
    free(p->bytes); free(p->path); free(p->temporary); free(p);
}
