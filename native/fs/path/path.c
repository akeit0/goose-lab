#include "fs/path/path.h"
#include <uv.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#endif
/* Lexical absolute path only: no filesystem access or symlink resolution. */
int32_t glab_path_absolute(const uint8_t *path, int64_t length, uint8_t *out, int64_t capacity, int64_t *count) {
    *count = 0;
    if (!path || length < 1 || length > 32768 || memchr(path, 0, (size_t)length) || !out || capacity < 1 || capacity > 32768) return 4;
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, NULL, 0);
    if (!n) return 4;
    wchar_t *input = calloc((size_t)n + 1, sizeof *input);
    if (!input) return 2;
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, input, n);
    DWORD needed = GetFullPathNameW(input, 0, NULL, NULL);
    if (!needed) { free(input); return 2; }
    if (needed > 32769) { free(input); return 3; }
    wchar_t *full = calloc(needed, sizeof *full);
    if (!full) { free(input); return 2; }
    DWORD written = GetFullPathNameW(input, needed, full, NULL); free(input);
    if (!written || written >= needed) { free(full); return 2; }
    int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, full, (int)written, NULL, 0, NULL, NULL);
    if (!bytes) { free(full); return 4; }
    if (bytes > capacity) { free(full); return 3; }
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, full, (int)written, (char *)out, bytes, NULL, NULL); free(full);
    for (int i = 0; i < bytes; ++i) if (out[i] == '\\') out[i] = '/';
    /* Keep drive/UNC roots; remove harmless trailing separators for identity. */
    while (bytes > 3 && out[bytes - 1] == '/') --bytes;
    *count = bytes;
#else
    char *input = malloc(65538);
    if (!input) return 2;
    size_t prefix = 0;
    if (path[0] != '/') {
        size_t size = 32769;
        int code = uv_cwd(input, &size);
        if (code) { free(input); return code == UV_ENOBUFS ? 3 : 2; }
        prefix = strlen(input); input[prefix++] = '/';
    }
    memcpy(input + prefix, path, (size_t)length); size_t end = prefix + (size_t)length;
    size_t at = 0, used = 1; out[0] = '/';
    while (at < end) {
        while (at < end && input[at] == '/') ++at;
        size_t first = at; while (at < end && input[at] != '/') ++at;
        size_t size = at - first;
        if (!size || (size == 1 && input[first] == '.')) continue;
        if (size == 2 && input[first] == '.' && input[first + 1] == '.') {
            while (used > 1 && out[used - 1] != '/') --used;
            if (used > 1) --used;
        } else {
            size_t separator = used > 1;
            if (used + separator + size > (size_t)capacity) { free(input); return 3; }
            if (separator) out[used++] = '/';
            memcpy(out + used, input + first, size); used += size;
        }
    }
    free(input); *count = (int64_t)used;
#endif
    return 0;
}
