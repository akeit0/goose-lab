#ifndef GOOSE_LAB_LAYOUT_GLUE_H
#define GOOSE_LAB_LAYOUT_GLUE_H
#include "ui/layout/layout.h"
#ifndef GS_TYPE_sl_u32
#define GS_TYPE_sl_u32
typedef struct { uint32_t *data; int64_t len; } sl_u32;
#endif
static int32_t glab_goose_layout_text_at(uint64_t c, sl_u8 text, sl_u32 breaks, uint32_t tag) {
    return glab_layout_text_at(c, text.data, text.len, breaks.data, breaks.len, tag);
}
static int32_t glab_goose_layout_open(uint64_t c, sl_u8 id, int32_t direction,
    int32_t wk, float wmin, float wmax, int32_t hk, float hmin, float hmax,
    uint16_t left, uint16_t right, uint16_t top, uint16_t bottom, uint16_t gap,
    int32_t ax, int32_t ay) {
    return glab_layout_open(c, id.data, id.len, direction, wk, wmin, wmax, hk, hmin, hmax,
        left, right, top, bottom, gap, ax, ay);
}
static int32_t glab_goose_layout_text(uint64_t c, sl_u8 text, int32_t wrap) {
    return glab_layout_text(c, text.data, text.len, wrap);
}
static int32_t glab_goose_layout_tagged_text(uint64_t c, sl_u8 text, int32_t wrap, uint32_t tag) {
    return glab_layout_tagged_text(c, text.data, text.len, wrap, tag);
}
static uint8_t glab_goose_layout_bounds(uint64_t c, sl_u8 id, float *x, float *y, float *w, float *h) {
    return glab_layout_bounds(c, id.data, id.len, x, y, w, h);
}
static uint8_t glab_goose_layout_line(uint64_t c, int64_t index, float *x, float *y,
    float *w, float *h, gs_rref out) {
    const uint8_t *text; int64_t length;
    uint8_t found = glab_layout_line(c, index, x, y, w, h, &text, &length);
    if (length) gs_bld_append(out, text, length);
    return found;
}
static void glab_goose_layout_error(uint64_t c, gs_rref out) {
    const char *error = glab_layout_error(c);
    gs_bld_append(out, error, (int64_t)strlen(error));
}
#endif
