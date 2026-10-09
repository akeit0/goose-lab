#ifndef GOOSE_LAB_TEXT_H
#define GOOSE_LAB_TEXT_H
#include <stdint.h>
#include <stddef.h>
uint64_t glab_text_create(const uint8_t *path, int64_t length, float size, float scale);
/* Family owns all faces and a shared atlas. Configure before metrics/shape. */
uint8_t glab_text_add_fallback(uint64_t font, const uint8_t *path, int64_t length, int32_t face_index);
/* Prefer this face for Unicode emoji presentation, keeping ordinary text primary. */
uint8_t glab_text_add_emoji(uint64_t font, const uint8_t *path, int64_t length, int32_t face_index);
uint8_t glab_text_has_glyph(uint64_t font, uint32_t codepoint);
/* Largest fitting cluster prefix; at least one whole cluster for progress. */
int64_t glab_text_fit(uint64_t font, const uint8_t *text, int64_t length, float width);
/* Allowed offsets are ordered absolute byte positions; origin locates text
   within their original paragraph. The slice end is always a hard boundary. */
int64_t glab_text_fit_at(uint64_t font, const uint8_t *text, int64_t length, float width,
    const uint32_t *breaks, int64_t count, uint32_t origin);
void glab_text_destroy(uint64_t font);
uint8_t glab_text_metrics(uint64_t font, float *height, float *ascent, float *scale);
/* positions holds eleven floats per glyph: x,y,w,h,u0,v0,u1,v1,pen,advance,colored. */
int64_t glab_text_shape(uint64_t font, const uint8_t *text, int64_t length,
    float *positions, uint32_t *clusters, int64_t capacity, float *width);
/* Same shaping/advance geometry without rasterizing into the atlas. */
int64_t glab_text_geometry(uint64_t font, const uint8_t *text, int64_t length,
    float *positions, uint32_t *clusters, int64_t capacity, float *width);
/* Shape the whole line, but rasterize/return only glyphs intersecting its window. */
int64_t glab_text_window(uint64_t font, const uint8_t *text, int64_t length, float left, float right,
    float *positions, uint32_t *clusters, int64_t capacity, float *width);
float glab_text_width(uint64_t font, const uint8_t *text, int64_t length);
uint64_t glab_text_revision(uint64_t font);
int64_t glab_text_pixels(uint64_t font, uint8_t *out, int64_t capacity);
/* Explicitly owned LTR editor line; borrowed font must outlive it. */
uint64_t glab_text_layout_create(uint64_t font, const uint8_t *source, int64_t length, const uint32_t *carets, int64_t caret_count);
void glab_text_layout_destroy(uint64_t layout);
float glab_text_layout_width(uint64_t layout);
int64_t glab_text_layout_bytes(uint64_t layout);
float glab_text_layout_position(uint64_t layout, int64_t source_byte);
int64_t glab_text_layout_hit(uint64_t layout, float x);
int64_t glab_text_layout_window(uint64_t layout, float left, float right, float *positions, uint32_t *clusters, int64_t capacity);
int64_t glab_text_layout_live_bytes(void);
int64_t glab_text_source_bytes(void);
int64_t glab_text_atlas_bytes(void);
const char *glab_text_error(void);
#endif
