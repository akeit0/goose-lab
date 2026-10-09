#ifndef GOOSE_LAB_WATCH_H
#define GOOSE_LAB_WATCH_H
#include <stdint.h>
/* One owning thread per watch; generation-tagged IDs reject stale copies. */
int32_t glab_watch_open(const uint8_t *path, int64_t length, uint8_t recursive, uint64_t *id);
int32_t glab_watch_poll(uint64_t id, uint8_t *out, int64_t capacity, int64_t *count, int32_t *flags);
uint8_t glab_watch_close(uint64_t id);
#endif
