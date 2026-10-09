#include "fs/sync/files.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/stat.h>
#endif
/* Metadata only: reject directories, links/reparse points and special files. */
int32_t glab_file_info(const uint8_t *path, int64_t length, int64_t *size) {
    *size = 0;
    if (!path || length <= 0 || length > 32768 || memchr(path, 0, (size_t)length)) return 4;
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, NULL, 0);
    if (!n) return 4;
    wchar_t *name = calloc((size_t)n + 1, sizeof *name);
    if (!name) return 2;
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, name, n);
    WIN32_FILE_ATTRIBUTE_DATA info;
    int ok = GetFileAttributesExW(name, GetFileExInfoStandard, &info);
    DWORD error = ok ? 0 : GetLastError(); free(name);
    if (!ok) return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ? 1 : 2;
    if (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE)) return 6;
    uint64_t bytes = ((uint64_t)info.nFileSizeHigh << 32) | info.nFileSizeLow;
    if (bytes > INT64_MAX) return 3;
    *size = (int64_t)bytes;
#else
    char *name = malloc((size_t)length + 1);
    if (!name) return 2;
    memcpy(name, path, (size_t)length); name[length] = 0;
    struct stat info; int ok = lstat(name, &info); int error = errno; free(name);
    if (ok) return error == ENOENT || error == ENOTDIR ? 1 : 2;
    if (!S_ISREG(info.st_mode)) return 6;
    if (info.st_size < 0 || (uintmax_t)info.st_size > INT64_MAX) return 3;
    *size = (int64_t)info.st_size;
#endif
    return 0;
}
/* Stream a bounded content revision without a whole-file allocation. */
int32_t glab_file_revision(const uint8_t *path, int64_t length, int64_t *size, uint64_t *digest) {
    *digest = 0;
    int32_t result = glab_file_info(path, length, size);
    if (result) return result;
    if (*size > 2097152) return 3;
    FILE *stream = NULL;
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, NULL, 0);
    wchar_t *name = calloc((size_t)n + 1, sizeof *name);
    if (!name) return 2;
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, name, n);
    stream = _wfopen(name, L"rb"); free(name);
#else
    char *name = malloc((size_t)length + 1); if (!name) return 2;
    memcpy(name, path, (size_t)length); name[length] = 0;
    stream = fopen(name, "rb"); free(name);
#endif
    if (!stream) return errno == ENOENT ? 1 : 2;
    uint8_t bytes[4096]; int64_t count = 0; uint64_t hash = UINT64_C(14695981039346656037);
    size_t nread;
    while ((nread = fread(bytes, 1, sizeof bytes, stream)) > 0) {
        count += (int64_t)nread;
        if (count > 2097152) { fclose(stream); return 3; }
        for (size_t i = 0; i < nread; ++i) { hash ^= bytes[i]; hash *= UINT64_C(1099511628211); }
    }
    int bad = ferror(stream); int closed = fclose(stream);
    if (bad || closed) return 2;
    *size = count; *digest = hash; return 0;
}
int32_t glab_file_read(const uint8_t *path, int64_t length, uint8_t *out, int64_t capacity, int64_t *count) {
    *count = 0;
    if (!path || length <= 0 || length > 32768 || memchr(path, 0, (size_t)length) ||
        !out || capacity < 0 || capacity > 2097152) return 4;
    FILE *stream = NULL;
#ifdef _WIN32
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, NULL, 0);
    if (!n) return 4;
    wchar_t *name = calloc((size_t)n + 1, sizeof *name);
    if (!name) return 2;
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, name, n);
    stream = _wfopen(name, L"rb"); free(name);
#else
    char *name = malloc((size_t)length + 1);
    if (!name) return 2;
    memcpy(name, path, (size_t)length); name[length] = 0;
    stream = fopen(name, "rb"); free(name);
#endif
    if (!stream) return errno == ENOENT ? 1 : 2;
    size_t nread = fread(out, 1, (size_t)capacity, stream);
    int extra = fgetc(stream), bad = ferror(stream);
    int closed = fclose(stream);
    if (bad || closed) return 2;
    if (extra != EOF) return 3;
    *count = (int64_t)nread; return 0;
}
