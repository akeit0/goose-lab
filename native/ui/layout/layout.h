#ifndef GOOSE_LAB_LAYOUT_H
#define GOOSE_LAB_LAYOUT_H
#include <stdint.h>
#include <stddef.h>

/* Main-thread only. Contexts own all native memory; no borrowed Goose value
   or function survives an API call. Geometry uses logical units. Native text
   providers implement these callbacks; Goose callbacks never cross this ABI. */
typedef uint8_t (*glab_layout_metrics_fn)(uint64_t token, float *height);
typedef float (*glab_layout_measure_fn)(uint64_t token, const uint8_t *text, int64_t length);
uint64_t glab_layout_create_backend(uint64_t token, glab_layout_metrics_fn metrics, glab_layout_measure_fn measure);
uint64_t glab_layout_create_font(uint64_t font);
void glab_layout_destroy(uint64_t handle);
int32_t glab_layout_begin(uint64_t handle, float width, float height);
int32_t glab_layout_open(uint64_t handle, const uint8_t *id, int64_t length,
    int32_t direction, int32_t width_kind, float width_min, float width_max,
    int32_t height_kind, float height_min, float height_max,
    uint16_t left, uint16_t right, uint16_t top, uint16_t bottom,
    uint16_t gap, int32_t align_x, int32_t align_y);
int32_t glab_layout_close(uint64_t handle);
int32_t glab_layout_text(uint64_t handle, const uint8_t *text, int64_t length, int32_t wrap);
int32_t glab_layout_tagged_text(uint64_t handle, const uint8_t *text, int64_t length, int32_t wrap, uint32_t tag);
int32_t glab_layout_text_at(uint64_t handle, const uint8_t *text, int64_t length,
    const uint32_t *breaks, int64_t count, uint32_t tag);
uint32_t glab_layout_line_tag(uint64_t handle, int64_t index);
int32_t glab_layout_finish(uint64_t handle);
uint8_t glab_layout_bounds(uint64_t handle, const uint8_t *id, int64_t length,
    float *x, float *y, float *width, float *height);
int64_t glab_layout_line_count(uint64_t handle);
uint8_t glab_layout_line(uint64_t handle, int64_t index, float *x, float *y,
    float *width, float *height, const uint8_t **text, int64_t *length);
int32_t glab_layout_status(uint64_t handle);
const char *glab_layout_error(uint64_t handle);
int64_t glab_layout_live_bytes(void);
#endif
