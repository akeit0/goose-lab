#include "ui/layout/layout.h"
#include "ui/text/text.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#define CLAY_IMPLEMENTATION
#ifdef _MSC_VER
#pragma warning(push, 0)
#endif
#include "clay.h"
#ifdef _MSC_VER
#pragma warning(pop)
#endif

enum { GLAB_OK, GLAB_INVALID, GLAB_STATE, GLAB_CAPACITY, GLAB_DUPLICATE, GLAB_BALANCE, GLAB_CLAY };
enum { GLAB_CONTEXTS = 16, GLAB_ELEMENTS = 1024, GLAB_TEXT_BYTES = 262144 };
typedef struct { int32_t start, count; } glab_break_range;
typedef struct {
    uint32_t generation;
    void *arena;
    size_t arena_bytes;
    Clay_Context *clay;
    uint64_t token;
    glab_layout_metrics_fn metrics;
    glab_layout_measure_fn measure;
    float font_height;
    uint8_t font_backend, overflow_wrap[GLAB_ELEMENTS];
    glab_break_range break_ranges[GLAB_ELEMENTS];
    uint32_t *breaks;
    int32_t break_used;
    size_t break_capacity;
    uint8_t *text;
    size_t used;
    int32_t phase, depth, elements, texts, status;
    uint32_t ids[GLAB_ELEMENTS];
    char error[256];
    Clay_RenderCommandArray commands;
} glab_layout_context;
static glab_layout_context contexts[GLAB_CONTEXTS];
static glab_layout_context *building;

static glab_layout_context *context(uint64_t handle) {
    uint32_t slot = (uint32_t)handle;
    uint32_t generation = (uint32_t)(handle >> 32);
    if (!slot || slot > GLAB_CONTEXTS) return NULL;
    glab_layout_context *c = &contexts[slot - 1];
    return c->arena && c->generation == generation ? c : NULL;
}
static int32_t fail(glab_layout_context *c, int32_t status, const char *message) {
    if (c && !c->status) {
        c->status = status;
        size_t length = strlen(message);
        if (length >= sizeof c->error) length = sizeof c->error - 1;
        memcpy(c->error, message, length);
        c->error[length] = 0;
    }
    return c ? c->status : GLAB_INVALID;
}
static void clay_error(Clay_ErrorData error) {
    glab_layout_context *c = error.userData;
    if (c->status) return;
    c->status = error.errorType == CLAY_ERROR_TYPE_DUPLICATE_ID ? GLAB_DUPLICATE : GLAB_CLAY;
    size_t n = (size_t)error.errorText.length;
    if (n >= sizeof c->error) n = sizeof c->error - 1;
    memcpy(c->error, error.errorText.chars, n);
    c->error[n] = 0;
}
static Clay_Dimensions measure(Clay_StringSlice text, Clay_TextElementConfig *config, void *data) {
    (void)config;
    glab_layout_context *c = data;
    return (Clay_Dimensions){ c->measure(c->token, (const uint8_t *)text.chars, text.length), c->font_height };
}
static Clay_ElementId element_id(const uint8_t *bytes, int64_t length) {
    Clay_String s = { false, (int32_t)length, (const char *)bytes };
    Clay_ElementId id = Clay__HashString(s, 0, 0);
    /* Keep only the hash, not a caller-owned label in Clay's persistent map. */
    id.stringId = CLAY_STRING("");
    return id;
}
uint64_t glab_layout_create_backend(uint64_t token, glab_layout_metrics_fn metrics, glab_layout_measure_fn measure_text) {
    float height = 0;
    if (building || !metrics || !measure_text || !metrics(token, &height)) return 0;
    for (uint32_t i = 0; i < GLAB_CONTEXTS; ++i) {
        glab_layout_context *c = &contexts[i];
        if (c->arena) continue;
        uint32_t generation = c->generation + 1;
        if (!generation) generation = 1;
        memset(c, 0, sizeof *c);
        c->generation = generation;
        c->token = token; c->metrics = metrics; c->measure = measure_text;
        Clay_SetCurrentContext(NULL);
        Clay_SetMaxElementCount(GLAB_ELEMENTS * 2 + 16);
        Clay_SetMaxMeasureTextCacheWordCount(8192);
        size_t capacity = Clay_MinMemorySize();
        c->arena = malloc(capacity); c->arena_bytes=capacity;
        /* Clay inspects the preceding byte when trimming an empty first
           line. Keep a readable sentinel without changing the text budget. */
        c->text = calloc(GLAB_TEXT_BYTES + 1, 1);
        if (!c->arena || !c->text) {
            free(c->arena); free(c->text); free(c->breaks); c->arena = NULL; c->text = NULL; c->breaks = NULL;
            return 0;
        }
        Clay_ErrorHandler handler = { clay_error, c };
        c->clay = Clay_Initialize(Clay_CreateArenaWithCapacityAndMemory(capacity, c->arena),
            (Clay_Dimensions){ 1, 1 }, handler);
        if (c->status) { glab_layout_destroy(((uint64_t)generation << 32) | (i + 1)); return 0; }
        Clay_SetMeasureTextFunction(measure, c);
        return ((uint64_t)generation << 32) | (i + 1);
    }
    return 0;
}
static uint8_t font_metrics(uint64_t font, float *height) {
    float ascent, scale; return glab_text_metrics(font, height, &ascent, &scale);
}
uint64_t glab_layout_create_font(uint64_t font) {
    uint64_t handle = glab_layout_create_backend(font, font_metrics, glab_text_width);
    glab_layout_context *c = context(handle); if (c) c->font_backend = 1;
    return handle;
}
void glab_layout_destroy(uint64_t handle) {
    glab_layout_context *c = context(handle);
    if (!c) return;
    if (building == c) building = NULL;
    if (Clay_GetCurrentContext() == c->clay) Clay_SetCurrentContext(NULL);
    free(c->arena); free(c->text); free(c->breaks);
    c->arena = NULL; c->text = NULL; c->breaks = NULL; c->clay = NULL;
}
int32_t glab_layout_begin(uint64_t handle, float width, float height) {
    glab_layout_context *c = context(handle);
    if (!c) return GLAB_INVALID;
    if (building) return fail(c, GLAB_STATE, "Another layout is being built; finish it first");
    c->status = GLAB_OK; c->error[0] = 0;
    c->phase = 0; c->commands.length = 0;
    if (!isfinite(width) || !isfinite(height) || width <= 0 || height <= 0)
        return fail(c, GLAB_INVALID, "Layout dimensions must be finite and positive");
    if (!c->metrics(c->token, &c->font_height)) return fail(c, GLAB_INVALID, "Text provider was destroyed");
    Clay_SetCurrentContext(c->clay);
    /* Text storage is reused each frame. Clear measurements so no cached
       word retains old contents, including after font/DPI changes. */
    Clay_ResetMeasureTextCache();
    Clay_SetLayoutDimensions((Clay_Dimensions){ width, height });
    c->used = 1; c->depth = 0; c->elements = 0; c->texts = 0;
    memset(c->overflow_wrap, 0, sizeof c->overflow_wrap);
    c->break_used = 0; memset(c->break_ranges, 0, sizeof c->break_ranges);
    c->phase = 1; building = c;
    Clay_BeginLayout();
    return c->status;
}
static int32_t ready(glab_layout_context *c) {
    if (!c) return GLAB_INVALID;
    if (c->status) return c->status;
    if (c != building || c->phase != 1) return fail(c, GLAB_STATE, "Call begin before declaring layout elements");
    return GLAB_OK;
}
static int valid_axis(int32_t kind, float value, float max_value) {
    return kind >= 0 && kind <= 3 && isfinite(value) && isfinite(max_value) &&
        value >= 0 && max_value >= 0 && (kind != 2 || value <= 1) &&
        (kind == 2 || kind == 3 || !max_value || max_value >= value);
}
static Clay_SizingAxis axis(int32_t kind, float value, float max_value) {
    Clay_SizingAxis result = {0}; result.type = (Clay__SizingType)kind;
    if (kind == 2) result.size.percent = value;
    else { result.size.minMax.min = value; result.size.minMax.max = kind == 3 ? value : max_value; }
    return result;
}
int32_t glab_layout_open(uint64_t handle, const uint8_t *id, int64_t length,
    int32_t direction, int32_t wk, float wmin, float wmax, int32_t hk, float hmin, float hmax,
    uint16_t left, uint16_t right, uint16_t top, uint16_t bottom,
    uint16_t gap, int32_t align_x, int32_t align_y) {
    glab_layout_context *c = context(handle);
    int32_t status = ready(c); if (status) return status;
    if (!id || length <= 0 || length > INT32_MAX || direction < 0 || direction > 1 ||
        align_x < 0 || align_x > 2 || align_y < 0 || align_y > 2 ||
        !valid_axis(wk, wmin, wmax) || !valid_axis(hk, hmin, hmax))
        return fail(c, GLAB_INVALID, "Invalid ID, direction, alignment or sizing");
    if (c->elements == GLAB_ELEMENTS) return fail(c, GLAB_CAPACITY, "Layout element capacity (1024) exceeded");
    Clay_ElementId key = element_id(id, length);
    if (!key.id) return fail(c, GLAB_INVALID, "Element ID hashes to the reserved zero ID");
    for (int i = 0; i < c->elements; ++i)
        if (c->ids[i] == key.id) return fail(c, GLAB_DUPLICATE, "Duplicate element ID or hash collision");
    c->ids[c->elements++] = key.id;
    Clay_ElementDeclaration declaration = {0};
    declaration.id = key;
    declaration.layout.sizing.width = axis(wk, wmin, wmax);
    declaration.layout.sizing.height = axis(hk, hmin, hmax);
    declaration.layout.padding = (Clay_Padding){ left, right, top, bottom };
    declaration.layout.childGap = gap;
    declaration.layout.layoutDirection = (Clay_LayoutDirection)direction;
    declaration.layout.childAlignment = (Clay_ChildAlignment){ (Clay_LayoutAlignmentX)align_x, (Clay_LayoutAlignmentY)align_y };
    Clay__OpenElement();
    Clay__ConfigureOpenElement(declaration);
    c->depth++;
    return c->status;
}
int32_t glab_layout_close(uint64_t handle) {
    glab_layout_context *c = context(handle);
    int32_t status = ready(c); if (status) return status;
    if (!c->depth) return fail(c, GLAB_BALANCE, "close without a matching open");
    Clay__CloseElement(); c->depth--;
    return c->status;
}
int32_t glab_layout_tagged_text(uint64_t handle, const uint8_t *text, int64_t length, int32_t wrap, uint32_t tag) {
    glab_layout_context *c = context(handle);
    int32_t status = ready(c); if (status) return status;
    if (!c->depth || length < 0 || length > INT32_MAX || (length && !text) || wrap < 0 || wrap > 3 || (wrap == 3 && !c->font_backend))
        return fail(c, GLAB_INVALID, "Text needs an open container and valid slice/wrap mode");
    if ((uint64_t)length > GLAB_TEXT_BYTES + 1 - c->used)
        return fail(c, GLAB_CAPACITY, "Frame text capacity (256 KiB) exceeded");
    if (c->texts == GLAB_ELEMENTS) return fail(c, GLAB_CAPACITY, "Text element capacity (1024) exceeded");
    c->texts++;
    uint8_t *copy = c->text + c->used;
    if (length) memcpy(copy, text, (size_t)length);
    c->used += (size_t)length;
    Clay_TextElementConfig config = {0};
    config.userData = (void *)(uintptr_t)tag;
    config.fontSize = (uint16_t)ceilf(c->font_height);
    config.wrapMode = (Clay_TextElementConfigWrapMode)(wrap == 3 ? 0 : wrap);
    int32_t text_index = c->clay->textElementData.length;
    /* Frame-owned addresses stay stable until begin resets Clay's cache.
       Address keys keep identical text at different widths/policies from
       sharing the measured-word tape we subdivide during final layout. */
    Clay__OpenTextElement((Clay_String){ c->font_backend != 0, (int32_t)length, (const char *)copy },
        Clay__StoreTextElementConfig(config));
    if (wrap == 3 && !c->status) {
        c->overflow_wrap[text_index] = 1;
        /* Let horizontal sizing shrink a text leaf below its longest word.
           Its unwrapped preferred width is unchanged, so fit still fits. */
        Clay__TextElementData *data = Clay__TextElementDataArray_Get(&c->clay->textElementData, text_index);
        Clay_LayoutElementArray_Get(&c->clay->layoutElements, (int)data->elementIndex)->minDimensions.width = 0;
    }
    return c->status;
}
int32_t glab_layout_text(uint64_t handle, const uint8_t *text, int64_t length, int32_t wrap) {
    return glab_layout_tagged_text(handle, text, length, wrap, 0);
}
int32_t glab_layout_text_at(uint64_t handle, const uint8_t *text, int64_t length,
    const uint32_t *breaks, int64_t count, uint32_t tag) {
    glab_layout_context *c = context(handle);
    int32_t status = ready(c); if (status) return status;
    if (length < 0 || count < 0 || count > length || (count && !breaks))
        return fail(c, GLAB_INVALID, "Invalid text break slice");
    for (int64_t i = 0; i < count; ++i) if (!breaks[i] || breaks[i] > length || (i && breaks[i] <= breaks[i - 1]))
        return fail(c, GLAB_INVALID, "Break offsets must be increasing text byte positions");
    if (count > GLAB_TEXT_BYTES - c->break_used) return fail(c, GLAB_CAPACITY, "Frame break capacity exceeded");
    size_t needed=(size_t)(c->break_used+count);
    if(needed>c->break_capacity) {
        size_t capacity=c->break_capacity ? c->break_capacity : 64;
        while(capacity<needed) capacity*=2;
        uint32_t *owned=realloc(c->breaks,capacity*sizeof *owned);
        if(!owned) return fail(c,GLAB_CAPACITY,"Cannot allocate text policy offsets");
        c->breaks=owned; c->break_capacity=capacity;
    }
    int32_t index = c->clay->textElementData.length;
    status = glab_layout_tagged_text(handle, text, length, 3, tag); if (status) return status;
    if (count) memcpy(c->breaks + c->break_used, breaks, (size_t)count * sizeof *breaks);
    c->break_ranges[index] = (glab_break_range){ c->break_used, (int32_t)count };
    c->break_used += (int32_t)count;
    c->overflow_wrap[index] = 2;
    return c->status;
}
uint32_t glab_layout_line_tag(uint64_t handle, int64_t index) {
    glab_layout_context *c = context(handle);
    if (!c || c->phase != 2 || c->status || index < 0) return 0;
    for (int i = 0; i < c->commands.length; ++i) {
        Clay_RenderCommand *command = &c->commands.internalArray[i];
        if (command->commandType != CLAY_RENDER_COMMAND_TYPE_TEXT) continue;
        if (index--) continue;
        return (uint32_t)(uintptr_t)command->userData;
    }
    return 0;
}
/* Adapt Clay's measured-word tape after resolving responsive widths. Only
   oversized words are split; original bytes, tags and ordinary word breaks
   remain intact. No patched copy of the dependency is required. */
static void split_overflow_words(glab_layout_context *c) {
    Clay__SizeContainersAlongAxis(true);
    for (int32_t i = 0; i < c->clay->textElementData.length && !c->status; ++i) {
        if (!c->overflow_wrap[i]) continue;
        Clay__TextElementData *data = Clay__TextElementDataArray_Get(&c->clay->textElementData, i);
        Clay_LayoutElement *element = Clay_LayoutElementArray_Get(&c->clay->layoutElements, (int)data->elementIndex);
        Clay_TextElementConfig *config = Clay__FindElementConfigWithType(element, CLAY__ELEMENT_CONFIG_TYPE_TEXT).textElementConfig;
        Clay__MeasureTextCacheItem *measured = Clay__MeasureTextCached(&data->text, config);
        float width = fmaxf(0, element->dimensions.width);
        for (int32_t word_index = measured->measuredWordsStartIndex; word_index != -1;) {
            Clay__MeasuredWord *word = Clay__MeasuredWordArray_Get(&c->clay->measuredWords, word_index);
            int32_t next = word->next;
            if (word->length > 0 && word->width > width) {
                int32_t at = word->startOffset, end = at + word->length;
                Clay__MeasuredWord *previous = NULL;
                while (at < end) {
                    glab_break_range range = c->break_ranges[i];
                    int64_t n = c->overflow_wrap[i] == 2 ?
                        glab_text_fit_at(c->token, (const uint8_t *)data->text.chars + at, end - at, width,
                            c->breaks + range.start, range.count, (uint32_t)at) :
                        glab_text_fit(c->token, (const uint8_t *)data->text.chars + at, end - at, width);
                    if (n <= 0) { fail(c, GLAB_CLAY, glab_text_error()); return; }
                    Clay__MeasuredWord chunk = { .startOffset = at, .length = (int32_t)n,
                        .width = c->measure(c->token, (const uint8_t *)data->text.chars + at, n), .next = next };
                    if (!previous) { *word = chunk; previous = word; }
                    else {
                        if (c->clay->measuredWords.length >= c->clay->measuredWords.capacity - 1) {
                            fail(c, GLAB_CAPACITY, "Overflow wrapping exceeded measured word capacity"); return;
                        }
                        previous = Clay__AddMeasuredWord(chunk, previous);
                        previous->next = next;
                    }
                    at += (int32_t)n;
                }
            }
            word_index = next;
        }
    }
}
int32_t glab_layout_finish(uint64_t handle) {
    glab_layout_context *c = context(handle);
    if (!c) return GLAB_INVALID;
    if (c != building || c->phase != 1) return fail(c, GLAB_STATE, "finish without begin");
    if (c->depth && !c->status) fail(c, GLAB_BALANCE, "Unclosed layout containers");
    /* Unwind even on errors; the following frame can recover normally. */
    while (c->depth) { Clay__CloseElement(); c->depth--; }
    if (!c->status && c->font_backend) {
        /* Close Clay's implicit root before using its resolved tree. This
           is the normal EndLayout sequence with an overflow preparation
           pass inserted before CalculateFinalLayout. Debug UI is disabled. */
        Clay__CloseElement();
        split_overflow_words(c);
        if (!c->status) Clay__CalculateFinalLayout();
        c->commands = c->clay->renderCommands;
    } else c->commands = Clay_EndLayout();
    /* Clay sums word widths. Report the width of the actual shaped line,
       including kerning at joins; drawing uses that same substring. */
    if (!c->status && c->font_backend) for (int i = 0; i < c->commands.length; ++i) {
        Clay_RenderCommand *command = &c->commands.internalArray[i];
        if (command->commandType == CLAY_RENDER_COMMAND_TYPE_TEXT) {
            Clay_StringSlice text = command->renderData.text.stringContents;
            command->boundingBox.width = c->measure(c->token, (const uint8_t *)text.chars, text.length);
        }
    }
    building = NULL; c->phase = c->status ? 0 : 2;
    return c->status;
}
uint8_t glab_layout_bounds(uint64_t handle, const uint8_t *id, int64_t length,
    float *x, float *y, float *width, float *height) {
    glab_layout_context *c = context(handle);
    *x = *y = *width = *height = 0;
    if (!c || c->phase != 2 || c->status || !id || length <= 0 || length > INT32_MAX) return 0;
    Clay_ElementId key = element_id(id, length);
    /* Clay remembers IDs across frames. Reject IDs absent in this frame. */
    int found = 0;
    for (int i = 0; i < c->elements; ++i) if (c->ids[i] == key.id) { found = 1; break; }
    if (!found) return 0;
    Clay_Context *previous = Clay_GetCurrentContext();
    Clay_SetCurrentContext(c->clay);
    Clay_ElementData element = Clay_GetElementData(key);
    Clay_SetCurrentContext(previous);
    if (!element.found) return 0;
    *x = element.boundingBox.x; *y = element.boundingBox.y;
    *width = element.boundingBox.width; *height = element.boundingBox.height;
    return 1;
}
int64_t glab_layout_line_count(uint64_t handle) {
    glab_layout_context *c = context(handle);
    if (!c || c->phase != 2 || c->status) return 0;
    int64_t count = 0;
    for (int i = 0; i < c->commands.length; ++i)
        if (c->commands.internalArray[i].commandType == CLAY_RENDER_COMMAND_TYPE_TEXT) count++;
    return count;
}
uint8_t glab_layout_line(uint64_t handle, int64_t index, float *x, float *y,
    float *width, float *height, const uint8_t **text, int64_t *length) {
    glab_layout_context *c = context(handle);
    *x = *y = *width = *height = 0; *text = NULL; *length = 0;
    if (!c || c->phase != 2 || c->status || index < 0) return 0;
    for (int i = 0; i < c->commands.length; ++i) {
        Clay_RenderCommand *command = &c->commands.internalArray[i];
        if (command->commandType != CLAY_RENDER_COMMAND_TYPE_TEXT) continue;
        if (index--) continue;
        *x = command->boundingBox.x; *y = command->boundingBox.y;
        *width = command->boundingBox.width; *height = command->boundingBox.height;
        *text = (const uint8_t *)command->renderData.text.stringContents.chars;
        *length = command->renderData.text.stringContents.length;
        return 1;
    }
    return 0;
}
int32_t glab_layout_status(uint64_t handle) { glab_layout_context *c = context(handle); return c ? c->status : GLAB_INVALID; }
const char *glab_layout_error(uint64_t handle) { glab_layout_context *c = context(handle); return c ? c->error : "Invalid or stale layout context"; }

int64_t glab_layout_live_bytes(void) {
    int64_t bytes=0;
    for(int i=0;i<GLAB_CONTEXTS;++i) if(contexts[i].arena)
        bytes+=(int64_t)(contexts[i].arena_bytes+GLAB_TEXT_BYTES+1+contexts[i].break_capacity*sizeof(uint32_t));
    return bytes;
}
