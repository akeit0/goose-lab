#ifndef GOOSE_LAB_WRITE_JOB_H
#define GOOSE_LAB_WRITE_JOB_H
#include "fs/internal/file_job.h"
struct glab_write_job;
struct glab_write_job *glab_write_job_create(uv_loop_t *loop, const uint8_t *path, int64_t path_length,
    const uint8_t *bytes, int64_t length, int automatic, int sync_file, int32_t *code);
void glab_write_job_start(struct glab_write_job *job);
int glab_write_job_pending(const struct glab_write_job *job);
int32_t glab_write_job_commit(struct glab_write_job *job);
void glab_write_job_poll(struct glab_write_job *job, uint8_t *ready, uint8_t *done, int32_t *result,
    uint8_t *committed, uint8_t *synced, int32_t *cleanup, int64_t *written, int64_t *size,
    uint64_t *digest, uint8_t *temporary, int64_t *temporary_length);
void glab_write_job_cancel(struct glab_write_job *job);
void glab_write_job_dispose(struct glab_write_job *job);
#endif
