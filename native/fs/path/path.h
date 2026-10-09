#ifndef GOOSE_LAB_PATH_H
#define GOOSE_LAB_PATH_H
#include <stdint.h>
int32_t glab_path_absolute(const uint8_t *path, int64_t length, uint8_t *out, int64_t capacity, int64_t *count);
#endif
