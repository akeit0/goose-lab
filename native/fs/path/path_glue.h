#ifndef GOOSE_LAB_PATH_GLUE_H
#define GOOSE_LAB_PATH_GLUE_H
#include "fs/path/path.h"
static int32_t glab_goose_path_absolute(sl_u8 path, sl_u8 out, int64_t *count) {
    return glab_path_absolute(path.data, path.len, out.data, out.len, count);
}
#endif
