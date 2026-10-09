#include "fs/internal/file_job.h"
#include <stdlib.h>
#include <string.h>

enum stage { INSPECT, OPEN_FILE, CHECK_FILE, READ_FILE, CLOSE_FILE, OPEN_DIRECTORY, READ_DIRECTORY, CLOSE_DIRECTORY };
struct glab_file_job {
    uv_loop_t *loop;
    uv_fs_t request;
    uv_file file;
    uv_dir_t *directory;
    uv_dirent_t entries[32];
    uv_buf_t buffer;
    char *path;
    uint8_t *bytes;
    uint8_t packet[GLAB_DIRECTORY_PACKET];
    int64_t limit, count, packet_length;
    int directory_job, active, cancelled, done, terminal_seen;
    enum stage stage;
    int32_t result;
};
int32_t glab_file_error(int64_t error) {
    if (error == UV_ENOENT) return GLAB_MISSING;
    if (error == UV_ENOTDIR) return GLAB_NOT_DIRECTORY;
    if (error == UV_ENOMEM) return GLAB_MEMORY;
    if (error == UV_EMFILE || error == UV_ENFILE || error == UV_ENOSPC) return GLAB_LIMIT;
    if (error == UV_ENOSYS || error == UV_ENOTSUP) return GLAB_UNSUPPORTED;
    if (error == UV_ECANCELED) return GLAB_CANCELLED;
    return GLAB_IO;
}
static void submit(struct glab_file_job *p, enum stage stage);
static void finish(struct glab_file_job *p) {
    if (p->cancelled) { p->result = GLAB_CANCELLED; p->packet_length = 0; }
    if (p->result != GLAB_OK) { free(p->bytes); p->bytes = NULL; p->count = 0; }
    p->done = 1;
}
static void end(struct glab_file_job *p, int32_t result) {
    if (p->result == GLAB_OK) p->result = result;
    if (p->file >= 0) submit(p, CLOSE_FILE);
    else if (p->directory) submit(p, CLOSE_DIRECTORY);
    else finish(p);
}
static int32_t checked_type(struct glab_file_job *p, const uv_stat_t *info) {
    uint64_t kind = info->st_mode & 0170000;
    if (p->directory_job) return kind == 0040000 ? GLAB_OK : GLAB_NOT_DIRECTORY;
    if (kind != 0100000) return GLAB_NOT_REGULAR;
    return info->st_size > (uint64_t)p->limit ? GLAB_LIMIT : GLAB_OK;
}
static int32_t pack_directory(struct glab_file_job *p, int64_t count) {
    for (int64_t i = 0; i < count; ++i) {
        if (p->count == p->limit) return GLAB_LIMIT;
        const uv_dirent_t *e = &p->entries[i];
        size_t n = strlen(e->name);
        if (n > 1024) return GLAB_LIMIT;
        /* Unknown type is a hint, not a reason to discard an entry. */
        p->packet[p->packet_length++] = (uint8_t)e->type;
        p->packet[p->packet_length++] = (uint8_t)n;
        p->packet[p->packet_length++] = (uint8_t)(n >> 8);
        memcpy(p->packet + p->packet_length, e->name, n);
        p->packet_length += (int64_t)n; p->count++;
    }
    return GLAB_OK;
}
static void completed(uv_fs_t *request) {
    struct glab_file_job *p = request->data;
    int64_t result = request->result;
    enum stage stage = p->stage;
    int32_t inspected = GLAB_OK;
    p->active = 0;
    /* Take ownership/copy results before request cleanup, including on cancel. */
    if (result >= 0) {
        if (stage == OPEN_FILE) p->file = (uv_file)result;
        else if (stage == OPEN_DIRECTORY) p->directory = request->ptr;
        else if (stage == INSPECT || stage == CHECK_FILE) inspected = checked_type(p, &request->statbuf);
        else if (stage == READ_DIRECTORY && !p->cancelled) inspected = pack_directory(p, result);
    }
    uv_fs_req_cleanup(request);
    if (stage == CLOSE_FILE || stage == CLOSE_DIRECTORY) {
        if (stage == CLOSE_FILE) p->file = -1; else p->directory = NULL;
        if (result < 0 && p->result == GLAB_OK) p->result = glab_file_error(result);
        finish(p); return;
    }
    if (p->cancelled) { end(p, GLAB_CANCELLED); return; }
    if (result < 0) { end(p, glab_file_error(result)); return; }
    if (inspected != GLAB_OK) { end(p, inspected); return; }
    switch (stage) {
    case INSPECT: submit(p, p->directory_job ? OPEN_DIRECTORY : OPEN_FILE); break;
    case OPEN_FILE: submit(p, CHECK_FILE); break;
    case CHECK_FILE:
        p->bytes = malloc((size_t)p->limit + 1);
        if (!p->bytes) end(p, GLAB_MEMORY); else submit(p, READ_FILE);
        break;
    case READ_FILE:
        p->count += result;
        if (p->count > p->limit) end(p, GLAB_LIMIT);
        else if (!result) end(p, GLAB_OK);
        else submit(p, READ_FILE);
        break;
    case OPEN_DIRECTORY: submit(p, READ_DIRECTORY); break;
    case READ_DIRECTORY:
        if (!result) end(p, GLAB_OK);
        /* Otherwise wait for poll to consume the page before reading more. */
        break;
    default: break;
    }
}
static void submit(struct glab_file_job *p, enum stage stage) {
    p->stage = stage; p->request.data = p;
    int error = 0;
    switch (stage) {
    case INSPECT: error = uv_fs_stat(p->loop, &p->request, p->path, completed); break;
    case OPEN_FILE:
        error = uv_fs_open(p->loop, &p->request, p->path, UV_FS_O_RDONLY | UV_FS_O_NONBLOCK, 0, completed); break;
    case CHECK_FILE: error = uv_fs_fstat(p->loop, &p->request, p->file, completed); break;
    case READ_FILE: {
        int64_t available = p->limit + 1 - p->count;
        unsigned int n = (unsigned int)(available < 65536 ? available : 65536);
        p->buffer = uv_buf_init((char *)p->bytes + p->count, n);
        error = uv_fs_read(p->loop, &p->request, p->file, &p->buffer, 1, p->count, completed); break;
    }
    case CLOSE_FILE: error = uv_fs_close(p->loop, &p->request, p->file, completed); break;
    case OPEN_DIRECTORY: error = uv_fs_opendir(p->loop, &p->request, p->path, completed); break;
    case READ_DIRECTORY: {
        int64_t remaining = p->limit - p->count + 1;
        p->directory->dirents = p->entries;
        p->directory->nentries = (size_t)(remaining < 32 ? remaining : 32);
        error = uv_fs_readdir(p->loop, &p->request, p->directory, completed); break;
    }
    case CLOSE_DIRECTORY: error = uv_fs_closedir(p->loop, &p->request, p->directory, completed); break;
    }
    if (error >= 0) { p->active = 1; return; }
    if (stage == CLOSE_FILE || stage == CLOSE_DIRECTORY) {
        /* Submission failed: synchronous cleanup is a last-resort fallback.
           Close requests themselves are never cancelled. */
        uv_fs_req_cleanup(&p->request);
        int closed = stage == CLOSE_FILE ? uv_fs_close(p->loop, &p->request, p->file, NULL)
            : uv_fs_closedir(p->loop, &p->request, p->directory, NULL);
        uv_fs_req_cleanup(&p->request);
        if (stage == CLOSE_FILE) p->file = -1; else p->directory = NULL;
        if (p->result == GLAB_OK) p->result = glab_file_error(closed < 0 ? closed : error);
        finish(p); return;
    }
    p->request.result = error; completed(&p->request);
}
struct glab_file_job *glab_file_job_create(uv_loop_t *loop, const uint8_t *path, int64_t length, int directory, int64_t limit) {
    struct glab_file_job *p = calloc(1, sizeof *p);
    if (!p) return NULL;
    p->path = malloc((size_t)length + 1);
    if (!p->path) { free(p); return NULL; }
    memcpy(p->path, path, (size_t)length); p->path[length] = 0;
    p->loop = loop; p->file = -1; p->directory_job = directory; p->limit = limit;
    return p;
}
void glab_file_job_start(struct glab_file_job *p) { submit(p, INSPECT); }
int glab_file_job_pending(const struct glab_file_job *p) { return p->packet_length || (p->done && !p->terminal_seen); }
void glab_file_job_read(struct glab_file_job *p, uint8_t *done, int32_t *result, glab_file_sink sink, void *context) {
    *done = (uint8_t)p->done; *result = p->done ? p->result : -1;
    if (!p->done) return;
    if (!p->terminal_seen && p->result == GLAB_OK && p->count) sink(context, p->bytes, p->count);
    free(p->bytes); p->bytes = NULL; p->terminal_seen = 1;
}
void glab_file_job_directory(struct glab_file_job *p, uint8_t *out, int64_t *length, uint8_t *done, int32_t *result) {
    *length = p->packet_length;
    if (*length) memcpy(out, p->packet, (size_t)*length);
    p->packet_length = 0;
    *done = (uint8_t)p->done; *result = p->done ? p->result : -1;
    if (p->done) p->terminal_seen = 1;
    else if (*length && !p->active && p->result == GLAB_OK && !p->cancelled) submit(p, READ_DIRECTORY);
}
void glab_file_job_cancel(struct glab_file_job *p) {
    if (p->done) return;
    p->cancelled = 1; p->packet_length = 0;
    if (p->active) {
        if (p->stage != CLOSE_FILE && p->stage != CLOSE_DIRECTORY) uv_cancel((uv_req_t *)&p->request);
    } else end(p, GLAB_CANCELLED);
}
void glab_file_job_dispose(struct glab_file_job *p) {
    glab_file_job_cancel(p);
    while (!p->done) uv_run(p->loop, UV_RUN_ONCE);
    free(p->bytes); free(p->path); free(p);
}
