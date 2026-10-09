#ifndef GOOSE_LAB_CONSOLE_GLUE_H
#define GOOSE_LAB_CONSOLE_GLUE_H
#include <stdint.h>
#include <stdio.h>
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif
static uint8_t glab_console_binary_output(void) {
    if (fflush(stdout) || fflush(stderr)) return 0;
#ifdef _WIN32
    if (_setmode(_fileno(stdout), _O_BINARY) == -1) return 0;
    if (_setmode(_fileno(stderr), _O_BINARY) == -1) return 0;
#endif
    return 1;
}
#endif
