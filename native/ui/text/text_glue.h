#ifndef GOOSE_LAB_TEXT_GLUE_H
#define GOOSE_LAB_TEXT_GLUE_H
#include "ui/text/text.h"
/* Match the compiler's guarded primitive slice ABI. A shape-only sample may
   never instantiate shape_raw; its adapter still needs these declarations. */
#ifndef GS_TYPE_sl_f32
#define GS_TYPE_sl_f32
typedef struct { float *data; int64_t len; } sl_f32;
#endif
#ifndef GS_TYPE_sl_u32
#define GS_TYPE_sl_u32
typedef struct { uint32_t *data; int64_t len; } sl_u32;
#endif
static uint64_t glab_goose_text_create(sl_u8 path, float size, float scale) { return glab_text_create(path.data, path.len, size, scale); }
static uint8_t glab_goose_text_add_fallback(uint64_t font, sl_u8 path, int32_t index) { return glab_text_add_fallback(font, path.data, path.len, index); }
static uint8_t glab_goose_text_add_emoji(uint64_t font, sl_u8 path, int32_t index) { return glab_text_add_emoji(font, path.data, path.len, index); }
static int64_t glab_goose_text_fit(uint64_t font, sl_u8 text, float width) { return glab_text_fit(font, text.data, text.len, width); }
static int64_t glab_goose_text_fit_at(uint64_t font, sl_u8 text, float width, sl_u32 breaks) {
    return glab_text_fit_at(font, text.data, text.len, width, breaks.data, breaks.len, 0);
}
static int64_t glab_goose_text_shape(uint64_t font, sl_u8 text, sl_f32 positions, sl_u32 clusters, float *width) {
    if (positions.len < 0 || positions.len % 11 || clusters.len != positions.len / 11) return -1;
    return glab_text_shape(font, text.data, text.len, positions.data, clusters.data, clusters.len, width);
}
static int64_t glab_goose_text_geometry(uint64_t font, sl_u8 text, sl_f32 positions, sl_u32 clusters, float *width) {
    if (positions.len < 0 || positions.len % 11 || clusters.len != positions.len / 11) return -1;
    return glab_text_geometry(font, text.data, text.len, positions.data, clusters.data, clusters.len, width);
}
static int64_t glab_goose_text_window(uint64_t font, sl_u8 text, float left, float right, sl_f32 positions, sl_u32 clusters, float *width) {
    if (positions.len < 0 || positions.len % 11 || clusters.len != positions.len / 11) return -1;
    return glab_text_window(font, text.data, text.len, left, right, positions.data, clusters.data, clusters.len, width);
}
static uint64_t glab_goose_text_layout_create(uint64_t font, sl_u8 text, sl_u32 carets) { return glab_text_layout_create(font, text.data, text.len, carets.data, carets.len); }
static int64_t glab_goose_text_layout_window(uint64_t layout, float left, float right, sl_f32 positions, sl_u32 clusters) {
    if (positions.len < 0 || positions.len % 11 || clusters.len != positions.len / 11) return -1;
    return glab_text_layout_window(layout, left, right, positions.data, clusters.data, clusters.len);
}
static float glab_goose_text_width(uint64_t font, sl_u8 text) { return glab_text_width(font, text.data, text.len); }
static int64_t glab_goose_text_pixels(uint64_t font, sl_u8 out) { return glab_text_pixels(font, out.data, out.len); }
static void glab_goose_text_error(gs_rref out) { const char *s = glab_text_error(); gs_bld_append(out, s, (int64_t)strlen(s)); }
static void glab_goose_text_default_font(gs_rref out) {
    gs_bld_append(out, GOOSE_LAB_FONT_PATH, sizeof(GOOSE_LAB_FONT_PATH) - 1);
}
static void glab_goose_text_default_mono(gs_rref out) {
    gs_bld_append(out, GOOSE_LAB_MONO_PATH, sizeof(GOOSE_LAB_MONO_PATH) - 1);
}
static void glab_goose_text_default_fallback(gs_rref out) {
    gs_bld_append(out, GOOSE_LAB_FALLBACK_PATH, sizeof(GOOSE_LAB_FALLBACK_PATH) - 1);
}
static void glab_goose_text_default_emoji(gs_rref out) {
    gs_bld_append(out, GOOSE_LAB_EMOJI_PATH, sizeof(GOOSE_LAB_EMOJI_PATH) - 1);
}
static void glab_goose_text_default_symbol(gs_rref out) {
    gs_bld_append(out, GOOSE_LAB_SYMBOL_PATH, sizeof(GOOSE_LAB_SYMBOL_PATH) - 1);
}
#endif
