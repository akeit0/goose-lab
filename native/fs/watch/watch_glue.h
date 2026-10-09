#ifndef GOOSE_LAB_WATCH_GLUE_H
#define GOOSE_LAB_WATCH_GLUE_H
#include "fs/watch/watch.h"
static int32_t glab_goose_watch_open(sl_u8 path, uint8_t recursive, uint64_t *id) {
    return glab_watch_open(path.data, path.len, recursive, id);
}
static int32_t glab_goose_watch_poll(uint64_t id, sl_u8 out, int64_t *count, int32_t *flags) {
    return glab_watch_poll(id, out.data, out.len, count, flags);
}
#endif
