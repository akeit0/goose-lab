#ifndef GOOSE_LAB_LOOP_H
#define GOOSE_LAB_LOOP_H
#include "io/types.h"

/* IDs identify a kind and generation, never a movable libuv handle. */
int32_t glab_loop_open(uint64_t *id);
int32_t glab_loop_step(uint64_t id, int64_t wait_ms);
int32_t glab_loop_info(uint64_t id, int64_t *resources);
uint8_t glab_loop_close(uint64_t id);
int32_t glab_loop_watch(uint64_t loop, const uint8_t *path, int64_t length, uint8_t subtree, uint64_t *id);
int32_t glab_loop_timer(uint64_t loop, int64_t delay_ms, int64_t repeat_ms, uint64_t *id);
int32_t glab_timer_start(uint64_t id, int64_t delay_ms, int64_t repeat_ms);
int32_t glab_timer_stop(uint64_t id);
int32_t glab_timer_poll(uint64_t id, int64_t *count);
uint8_t glab_loop_resource_close(uint64_t id, int32_t kind);
int32_t glab_loop_process(uint64_t loop, const uint8_t *program, int64_t plen,
    const uint8_t *cwd, int64_t clen, const uint8_t *args, int64_t alen,
    int64_t timeout_ms, int64_t max_bytes, uint8_t input, int64_t max_pending, uint64_t *id);
int32_t glab_stream_send(uint64_t id, const uint8_t *bytes, int64_t length);
int32_t glab_stream_eof(uint64_t id);
int32_t glab_stream_cancel(uint64_t id);
int32_t glab_stream_poll(uint64_t id, uint8_t *out, int64_t capacity,
    int64_t *length, uint8_t *done, int32_t *result, int64_t *exit_code,
    uint8_t *input_enabled, uint8_t *input_eof, uint8_t *input_closed, int32_t *input_result,
    int64_t *input_pending, int64_t *input_accepted, int64_t *input_sent);
int32_t glab_loop_read(uint64_t loop, const uint8_t *path, int64_t length, int64_t max_bytes, uint64_t *id);
int32_t glab_loop_directory(uint64_t loop, const uint8_t *path, int64_t length, int64_t max_entries, uint64_t *id);
int32_t glab_read_poll(uint64_t id, uint8_t *done, int32_t *result, glab_file_sink sink, void *context);
int32_t glab_directory_poll(uint64_t id, uint8_t *out, int64_t capacity, int64_t *length, uint8_t *done, int32_t *result);
int32_t glab_file_cancel(uint64_t id, int32_t kind);
int32_t glab_loop_replace(uint64_t loop, const uint8_t *path, int64_t path_length,
    const uint8_t *bytes, int64_t length, uint8_t automatic, uint8_t sync_file, uint64_t *id);
int32_t glab_write_commit(uint64_t id);
int32_t glab_write_poll(uint64_t id, uint8_t *ready, uint8_t *done, int32_t *result,
    uint8_t *committed, uint8_t *synced, int32_t *cleanup, int64_t *written, int64_t *size,
    uint64_t *digest, uint8_t *temporary, int64_t capacity, int64_t *temporary_length);
#endif
