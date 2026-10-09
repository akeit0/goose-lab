#ifndef GOOSE_LAB_SHORTCUTS_GLUE_H
#define GOOSE_LAB_SHORTCUTS_GLUE_H
#include <stdint.h>
/* Goose gfx modifier bits: Ctrl=2, GUI/Command=8. No window dependency. */
static inline uint8_t glab_ui_is_macos(void) {
#if defined(__APPLE__) && defined(__MACH__)
    return 1;
#else
    return 0;
#endif
}
static inline int32_t glab_ui_primary_mod(void) { return glab_ui_is_macos() ? 8 : 2; }
#endif
