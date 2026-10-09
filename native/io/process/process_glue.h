#ifndef GOOSE_LAB_PROCESS_GLUE_H
#define GOOSE_LAB_PROCESS_GLUE_H
#include "io/process/process.h"
static void glab_goose_process_sink(void *context, const uint8_t *bytes, size_t len) {
    gs_bld_append(*(gs_rref *)context, bytes, (int64_t)len);
}
static int32_t glab_goose_process_run(sl_u8 program, sl_u8 cwd, sl_u8 argv,
    int64_t timeout, int64_t limit, uint64_t cancel, gs_rref out, gs_rref err, int64_t *exit_code) {
    return glab_process_run(program.data, program.len, cwd.data, cwd.len, argv.data, argv.len,
        timeout, limit, cancel, glab_goose_process_sink, &out, glab_goose_process_sink, &err, exit_code);
}
#endif
