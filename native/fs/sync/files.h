#ifndef GOOSE_LAB_FILES_H
#define GOOSE_LAB_FILES_H
#include <stdint.h>
int32_t glab_file_read(const uint8_t *path, int64_t length, uint8_t *out, int64_t capacity, int64_t *count);
int32_t glab_file_info(const uint8_t *path, int64_t length, int64_t *size);
int32_t glab_file_revision(const uint8_t *path, int64_t length, int64_t *size, uint64_t *digest);
#endif
