#ifndef GOOSE_LAB_LOOP_GLUE_H
#define GOOSE_LAB_LOOP_GLUE_H
#include "io/loop/loop.h"
static int32_t glab_goose_loop_replace(uint64_t loop, sl_u8 path, sl_u8 bytes, uint8_t automatic, uint8_t sync_file, uint64_t *id) {
    return glab_loop_replace(loop, path.data, path.len, bytes.data, bytes.len, automatic, sync_file, id);
}
static int32_t glab_goose_write_poll(uint64_t id, uint8_t *ready, uint8_t *done, int32_t *result,
    uint8_t *committed, uint8_t *synced, int32_t *cleanup, int64_t *written, int64_t *size,
    uint64_t *digest, sl_u8 temporary, int64_t *length) {
    return glab_write_poll(id, ready, done, result, committed, synced, cleanup, written, size,
        digest, temporary.data, temporary.len, length);
}
static void glab_goose_read_sink(void *context, const uint8_t *bytes, int64_t length) {
    gs_bld_append(*(gs_rref *)context, bytes, length);
}
static int32_t glab_goose_loop_read(uint64_t loop, sl_u8 path, int64_t limit, uint64_t *id) {
    return glab_loop_read(loop, path.data, path.len, limit, id);
}
static int32_t glab_goose_loop_directory(uint64_t loop, sl_u8 path, int64_t limit, uint64_t *id) {
    return glab_loop_directory(loop, path.data, path.len, limit, id);
}
static int32_t glab_goose_read_poll(uint64_t id, uint8_t *done, int32_t *result, gs_rref bytes) {
    return glab_read_poll(id, done, result, glab_goose_read_sink, &bytes);
}
static int32_t glab_goose_directory_poll(uint64_t id, sl_u8 out, int64_t *length, uint8_t *done, int32_t *result) {
    return glab_directory_poll(id, out.data, out.len, length, done, result);
}
static int32_t glab_goose_loop_watch(uint64_t loop, sl_u8 path, uint8_t subtree, uint64_t *id) {
    return glab_loop_watch(loop, path.data, path.len, subtree, id);
}
static int32_t glab_goose_loop_process(uint64_t loop, sl_u8 program, sl_u8 cwd, sl_u8 args,
    int64_t timeout_ms, int64_t max_bytes, uint8_t input, int64_t pending, uint64_t *id) {
    return glab_loop_process(loop, program.data, program.len, cwd.data, cwd.len, args.data, args.len, timeout_ms, max_bytes, input, pending, id);
}
static int32_t glab_goose_stream_send(uint64_t id, sl_u8 bytes) { return glab_stream_send(id, bytes.data, bytes.len); }
static int32_t glab_goose_stream_poll(uint64_t id, sl_u8 out, int64_t *length,
    uint8_t *done, int32_t *result, int64_t *exit_code, uint8_t *enabled, uint8_t *eof, uint8_t *closed,
    int32_t *input_result, int64_t *pending, int64_t *accepted, int64_t *sent) {
    return glab_stream_poll(id, out.data, out.len, length, done, result, exit_code, enabled, eof, closed, input_result, pending, accepted, sent);
}
#endif
