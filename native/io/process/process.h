#ifndef GOOSE_LAB_PROCESS_H
#define GOOSE_LAB_PROCESS_H
#include <stdint.h>
#include <stddef.h>
typedef void (*glab_process_sink)(void *, const uint8_t *, size_t);
/* Native-owned input hooks. peek: 0 wait, 1 data, 2 EOF. ack is OS-written bytes,
   not child-consumed bytes. closed can precede process/output completion;
   receivers retain the first close outcome (completion can notify again).
   Close results use the glab_process_run status domain. */
typedef struct glab_process_input {
    void *context;
    int (*peek)(void *, uint8_t *, size_t, size_t *);
    void (*ack)(void *, size_t);
    void (*closed)(void *, int32_t);
} glab_process_input;
/* argv is a sequence of NUL-terminated UTF-8 arguments, excluding argv[0].
   One combined stdout/stderr budget. No shell or inherited stdin. */
int32_t glab_process_run(const uint8_t *program, int64_t program_len,
    const uint8_t *cwd, int64_t cwd_len, const uint8_t *argv, int64_t argv_len,
    int64_t timeout_ms, int64_t limit, uint64_t cancel,
    glab_process_sink out, void *out_ctx, glab_process_sink err, void *err_ctx,
    int64_t *exit_code);
int32_t glab_process_run_input(const uint8_t *program, int64_t program_len,
    const uint8_t *cwd, int64_t cwd_len, const uint8_t *argv, int64_t argv_len,
    int64_t timeout_ms, int64_t limit, uint64_t cancel,
    glab_process_sink out, void *out_ctx, glab_process_sink err, void *err_ctx,
    glab_process_input *input, int64_t *exit_code);
#endif
