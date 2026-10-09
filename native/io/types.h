#ifndef GOOSE_LAB_IO_TYPES_H
#define GOOSE_LAB_IO_TYPES_H
#include <stdint.h>
/* Portable result codes and a synchronous byte sink, shared by loop/jobs. */
enum glab_io_code { GLAB_OK = 0, GLAB_MISSING = 1, GLAB_IO = 2, GLAB_LIMIT = 3, GLAB_INVALID = 4,
    GLAB_NOT_DIRECTORY = 5, GLAB_UNSUPPORTED = 6, GLAB_CLOSED = 7, GLAB_THREAD = 8,
    GLAB_MEMORY = 9, GLAB_CANCELLED = 10, GLAB_NOT_REGULAR = 11, GLAB_NOT_READY = 12,
    GLAB_WOULD_BLOCK = 13, GLAB_INPUT_CLOSED = 14 };
typedef void (*glab_file_sink)(void *context, const uint8_t *bytes, int64_t length);
#endif
