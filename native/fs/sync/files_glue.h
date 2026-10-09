#ifndef GOOSE_LAB_FILES_GLUE_H
#define GOOSE_LAB_FILES_GLUE_H
#include "fs/sync/files.h"
static int32_t glab_goose_file_info(sl_u8 path, int64_t *size) {
    return glab_file_info(path.data, path.len, size);
}
static int32_t glab_goose_file_read(sl_u8 path, sl_u8 out, int64_t *count) {
    return glab_file_read(path.data, path.len, out.data, out.len, count);
}
static int32_t glab_goose_file_revision(sl_u8 path, int64_t *size, uint64_t *digest) {
    return glab_file_revision(path.data, path.len, size, digest);
}
#endif
