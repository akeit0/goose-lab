#ifndef GOOSE_LAB_FILE_JOB_H
#define GOOSE_LAB_FILE_JOB_H
/* Internal owner-thread state. No Goose runtime, registry or UI dependency. */
#include "io/types.h"
#include <uv.h>
#define GLAB_DIRECTORY_PACKET (32 * (1024 + 3))
struct glab_file_job;
int32_t glab_file_error(int64_t error);
struct glab_file_job *glab_file_job_create(uv_loop_t *loop, const uint8_t *path, int64_t length, int directory, int64_t limit);
void glab_file_job_start(struct glab_file_job *job);
int glab_file_job_pending(const struct glab_file_job *job);
void glab_file_job_read(struct glab_file_job *job, uint8_t *done, int32_t *result, glab_file_sink sink, void *context);
void glab_file_job_directory(struct glab_file_job *job, uint8_t *out, int64_t *length, uint8_t *done, int32_t *result);
void glab_file_job_cancel(struct glab_file_job *job);
void glab_file_job_dispose(struct glab_file_job *job);
#endif
