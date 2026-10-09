#include "ui/text/text.h"
#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb.h>
#include <hb-ft.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <float.h>
#include "ui/text/internal/unicode.h"
#ifdef _WIN32
#include <windows.h>
#endif

enum { FONTS = 16, FACES = 8, ATLAS = 1024, GLYPHS = 4096 };
/* Immutable source snapshots shared across sizes/faces while at least one family lives.
   Face metrics/HarfBuzz and raster atlases remain family-owned. Main-thread only. */
typedef struct { uint8_t *bytes; char *path; int64_t length; uint32_t refs; } font_blob;
static font_blob blobs[FONTS*FACES];
static font_blob *blob_find(const uint8_t *path, int64_t n) {
    for(int i=0;i<FONTS*FACES;++i) if(blobs[i].refs && strlen(blobs[i].path)==(size_t)n && !memcmp(blobs[i].path,path,(size_t)n)) { blobs[i].refs++; return &blobs[i]; } return NULL;
}
static void blob_release(font_blob *b) { if(b && --b->refs==0) { free(b->bytes); free(b->path); memset(b,0,sizeof *b); } }
typedef struct { FT_Face face; hb_font_t *hb; font_blob *blob; int emoji; } font_face;
typedef struct { uint32_t id; int face, x, y, w, h, left, top, plain, colored; } cached_glyph;
typedef struct {
    uint32_t generation;
    font_face faces[FACES];
    int face_count, sealed;
    uint8_t *pixels;
    float size, scale, height, ascent, descent;
    int x, y, row_height, count;
    uint64_t revision;
    cached_glyph glyphs[GLYPHS];
} font_state;
static font_state fonts[FONTS];
static FT_Library library;
static char last_error[128];
static void error(const char *message) { size_t n = strlen(message); if (n > 127) n = 127; memcpy(last_error, message, n); last_error[n] = 0; }
const char *glab_text_error(void) { return last_error; }
static font_state *font(uint64_t handle) {
    uint32_t slot = (uint32_t)handle;
    if (!slot || slot > FONTS) return NULL;
    font_state *f = &fonts[slot - 1];
    return f->face_count && f->generation == (uint32_t)(handle >> 32) ? f : NULL;
}
static void release_library_if_idle(void) {
    for (int i = 0; i < FONTS; ++i) if (fonts[i].face_count) return;
    if (library) { FT_Done_FreeType(library); library = NULL; }
}
static int load_face(font_state *f, const uint8_t *path, int64_t length, int32_t index) {
    if (!path || length <= 0 || length > 32768 || memchr(path, 0, (size_t)length) || index < 0 || index > 32767) {
        error("Invalid font path or collection face index"); return 0;
    }
    font_blob *blob=blob_find(path,length);
    if (!blob) {
    FILE *stream = NULL;
#ifdef _WIN32
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, NULL, 0);
    wchar_t *wide = calloc((size_t)count + 1, sizeof *wide);
    if (count && wide) { MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, (int)length, wide, count); stream = _wfopen(wide, L"rb"); }
    free(wide);
#else
    char *name = malloc((size_t)length + 1);
    if (name) { memcpy(name, path, (size_t)length); name[length] = 0; stream = fopen(name, "rb"); free(name); }
#endif
    if (!stream) { error("Cannot open font file"); return 0; }
    fseek(stream, 0, SEEK_END); long bytes = ftell(stream); rewind(stream);
    if (bytes <= 0 || bytes > 64 * 1024 * 1024) { fclose(stream); error("Invalid font file length"); return 0; }
    for(int i=0;i<FONTS*FACES;++i) if(!blobs[i].refs) { blob=&blobs[i]; break; }
    if(!blob) { fclose(stream); error("Font source capacity exceeded"); return 0; }
    blob->bytes=malloc((size_t)bytes); blob->path=malloc((size_t)length+1);
    if(!blob->bytes || !blob->path || fread(blob->bytes,1,(size_t)bytes,stream)!=(size_t)bytes) {
        fclose(stream); free(blob->bytes); free(blob->path); memset(blob,0,sizeof *blob); error("Cannot allocate/read font"); return 0;
    }
    fclose(stream); memcpy(blob->path,path,(size_t)length); blob->path[length]=0; blob->length=bytes; blob->refs=1;
    }
    font_face face = {0}; face.blob=blob;
    if (!library && FT_Init_FreeType(&library)) {
        blob_release(face.blob);
        error("FreeType initialization failed"); return 0;
    }
    if (FT_New_Memory_Face(library, blob->bytes, (FT_Long)blob->length, index, &face.face) ||
        FT_Select_Charmap(face.face, FT_ENCODING_UNICODE) ||
        FT_Set_Char_Size(face.face, 0, (FT_F26Dot6)lroundf(f->size * f->scale * 64), 72, 72)) {
        if (face.face) FT_Done_Face(face.face);
        blob_release(face.blob);
        release_library_if_idle(); error("Unsupported font"); return 0;
    }
    face.hb = hb_ft_font_create_referenced(face.face);
    if (face.hb == hb_font_get_empty()) {
        FT_Done_Face(face.face); blob_release(face.blob); release_library_if_idle();
        error("Cannot allocate HarfBuzz font"); return 0;
    }
    hb_ft_font_set_load_flags(face.hb, FT_LOAD_DEFAULT);
    f->faces[f->face_count++] = face;
    f->ascent = fmaxf(f->ascent, (float)face.face->size->metrics.ascender / (64 * f->scale));
    f->descent = fmaxf(f->descent, -(float)face.face->size->metrics.descender / (64 * f->scale));
    f->height = fmaxf(fmaxf(f->height, (float)face.face->size->metrics.height / (64 * f->scale)), f->ascent + f->descent);
    return 1;
}
uint64_t glab_text_create(const uint8_t *path, int64_t length, float size, float scale) {
    last_error[0] = 0;
    if (!isfinite(size) || size < 6 || size > 128 || !isfinite(scale) || scale < 0.5f || scale > 4) {
        error("Invalid font size (6..128) or scale (0.5..4)"); return 0;
    }
    font_state *f = NULL; uint32_t slot = 0;
    for (; slot < FONTS; ++slot) if (!fonts[slot].face_count) { f = &fonts[slot]; break; }
    if (!f) { error("Font family capacity (16) exceeded"); return 0; }
    uint32_t generation = f->generation + 1; if (!generation) generation = 1;
    memset(f, 0, sizeof *f); f->generation = generation; f->size = size; f->scale = scale;
    if (!load_face(f, path, length, 0)) return 0;
    f->pixels = calloc(ATLAS * ATLAS, 4);
    if (!f->pixels) { glab_text_destroy(((uint64_t)generation << 32) | (slot + 1)); error("Cannot allocate atlas"); return 0; }
    f->x = f->y = 1; f->revision = 1;
    return ((uint64_t)generation << 32) | (slot + 1);
}
uint8_t glab_text_add_fallback(uint64_t handle, const uint8_t *path, int64_t length, int32_t index) {
    last_error[0] = 0;
    font_state *f = font(handle);
    if (!f || f->sealed) { error("Configure fallback faces before measuring or shaping the family"); return 0; }
    if (f->face_count == FACES) { error("Font family face capacity (8) exceeded"); return 0; }
    return (uint8_t)load_face(f, path, length, index);
}
uint8_t glab_text_add_emoji(uint64_t handle, const uint8_t *path, int64_t length, int32_t index) {
    if (!glab_text_add_fallback(handle,path,length,index)) return 0;
    font_state *f=font(handle); f->faces[f->face_count-1].emoji=1; return 1;
}
uint8_t glab_text_has_glyph(uint64_t handle, uint32_t cp) {
    font_state *f = font(handle); if (!f || cp > 0x10ffff) return 0;
    for (int i = 0; i < f->face_count; ++i) if (FT_Get_Char_Index(f->faces[i].face, cp)) return 1;
    return 0;
}
void glab_text_destroy(uint64_t handle) {
    font_state *f = font(handle); if (!f) return;
    for (int i = 0; i < f->face_count; ++i) {
        hb_font_destroy(f->faces[i].hb); FT_Done_Face(f->faces[i].face); blob_release(f->faces[i].blob);
    }
    free(f->pixels); f->pixels = NULL; f->face_count = 0;
    release_library_if_idle();
}
uint8_t glab_text_metrics(uint64_t handle, float *height, float *ascent, float *scale) {
    font_state *f = font(handle); *height = *ascent = *scale = 0;
    if (!f) return 0; f->sealed = 1; *height = f->height; *ascent = f->ascent; *scale = f->scale; return 1;
}
static cached_glyph *cache(font_state *f, int face, uint32_t id, int plain) {
    for (int i = 0; i < f->count; ++i) if (f->glyphs[i].id == id && f->glyphs[i].face == face && f->glyphs[i].plain==plain) return &f->glyphs[i];
    if (f->count == GLYPHS) { error("Glyph capacity exceeded"); return NULL; }
    FT_Face ft = f->faces[face].face;
    if (FT_Load_Glyph(ft, id, FT_LOAD_DEFAULT | (plain ? 0 : FT_LOAD_COLOR)) || FT_Render_Glyph(ft->glyph, FT_RENDER_MODE_NORMAL)) {
        error("Glyph rasterization failed"); return NULL;
    }
    FT_GlyphSlot g = ft->glyph;
    int colored=g->bitmap.pixel_mode==FT_PIXEL_MODE_BGRA;
    if (!colored && g->bitmap.pixel_mode != FT_PIXEL_MODE_GRAY && g->bitmap.pixel_mode != FT_PIXEL_MODE_MONO) {
        error("Unsupported glyph bitmap format"); return NULL;
    }
    int w = (int)g->bitmap.width, h = (int)g->bitmap.rows;
    if (w + 2 > ATLAS || h + 2 > ATLAS) { error("Glyph larger than atlas"); return NULL; }
    if (f->x + w + 1 >= ATLAS) { f->x = 1; f->y += f->row_height + 2; f->row_height = 0; }
    if (f->y + h + 1 >= ATLAS) { error("Glyph atlas full"); return NULL; }
    cached_glyph *c = &f->glyphs[f->count++];
    *c = (cached_glyph){ id, face, f->x, f->y, w, h, g->bitmap_left, g->bitmap_top, plain, colored };
    for (int y = 0; y < h; ++y) {
        const uint8_t *row = g->bitmap.buffer + (g->bitmap.pitch >= 0 ? y : h - 1 - y) * abs(g->bitmap.pitch);
        for (int x = 0; x < w; ++x) {
            uint8_t *p = f->pixels + ((f->y + y) * ATLAS + f->x + x) * 4;
            if(colored) {
                /* Retain premultiplication for correct filtered edges. The
                   scene converts the filtered sample for straight-alpha blending. */
                p[0]=row[x*4+2]; p[1]=row[x*4+1]; p[2]=row[x*4]; p[3]=row[x*4+3];
            } else {
                uint8_t alpha = g->bitmap.pixel_mode == FT_PIXEL_MODE_MONO ? ((row[x >> 3] & (128 >> (x & 7))) ? 255 : 0) : row[x];
                p[0] = p[1] = p[2] = 255; p[3] = alpha;
            }
        }
    }
    f->x += w + 2; if (h > f->row_height) f->row_height = h;
    f->revision++;
    return c;
}
static uint32_t scalar(const uint8_t *text, int end, int *at) {
    uint32_t cp = text[(*at)++]; int more = 0;
    if (cp < 128) return cp;
    if (cp >= 0xc2 && cp <= 0xdf) { cp &= 31; more = 1; }
    else if (cp >= 0xe0 && cp <= 0xef) { cp &= 15; more = 2; }
    else if (cp >= 0xf0 && cp <= 0xf4) { cp &= 7; more = 3; }
    else return 0xfffd;
    if (end - *at < more) return 0xfffd;
    for (int i = 0; i < more; ++i) {
        if ((text[*at] & 0xc0) != 0x80) return 0xfffd;
        cp = (cp << 6) | (text[(*at)++] & 63);
    }
    if (cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff) ||
        (more == 1 && cp < 128) || (more == 2 && cp < 2048) || (more == 3 && cp < 65536)) return 0xfffd;
    return cp;
}
static int ignored_for_coverage(uint32_t cp) {
    return cp == 0x200c || cp == 0x200d || (cp >= 0xfe00 && cp <= 0xfe0f) ||
        (cp >= 0xe0100 && cp <= 0xe01ef) || (cp>=0xe0020 && cp<=0xe007f) || cp < 32 || cp == 127;
}
/* Select a face for the entire extended grapheme cluster, including marks.
   Never send a base and its combining marks to unrelated fonts. */
static int cluster_face(font_state *f, const uint8_t *text, int begin, int end, int *plain) {
    int emoji=0, selector=0, at=begin;
    while(at<end) { uint32_t cp=scalar(text,end,&at); unsigned int p=text_property(cp);
        if(cp==0xfe0e) selector=-1; else if(cp==0xfe0f) selector=1;
        if(p & 512) emoji=1;
        if(cp==0x20e3) emoji=1; // Keycap sequence.
    }
    *plain=selector<0; if(selector) emoji=selector>0;
    /* Explicit emoji families win only for emoji presentation. Ordinary text
       remains in its selected face even if an emoji font also covers it. */
    for (int pass=0;pass<(emoji ? 2 : 1);++pass) for (int face = 0; face < f->face_count; ++face) {
        if(emoji && f->faces[face].emoji != (pass==0)) continue;
        int pos = begin, supported = 1;
        while (pos < end) {
            uint32_t cp = scalar(text, end, &pos);
            if(ignored_for_coverage(cp)) continue;
            FT_UInt glyph=FT_Get_Char_Index(f->faces[face].face,cp);
            if(!glyph) { supported=0; break; }
            if(*plain && f->faces[face].emoji && cp!=32 &&
                (FT_Load_Glyph(f->faces[face].face,glyph,FT_LOAD_DEFAULT) ||
                 (f->faces[face].face->glyph->format==FT_GLYPH_FORMAT_OUTLINE && !f->faces[face].face->glyph->outline.n_contours))) {
                supported=0; break; // Color-only base outlines must not silently erase text presentation.
            }
        }
        if (supported) return face;
    }
    return 0; /* Missing coverage stays visible as the primary .notdef. */
}
typedef struct { uint32_t id, cluster; int face, plain; float x, y, pen, advance, left, right; } layout_glyph;
typedef struct { uint32_t byte; float x; } layout_stop;
typedef struct { layout_glyph *glyphs; size_t count, capacity, budget; } layout_capture;
typedef struct {
    uint32_t generation; uint64_t font;
    layout_capture captured; layout_stop *stops; size_t stop_count, bytes;
    float width; float *blocks; size_t block_count;
} layout_state;
enum { LAYOUTS = 1024, LAYOUT_SOURCE = 2097152, LAYOUT_MEMORY = 134217728, LAYOUT_BLOCK = 256 };
static layout_state *layouts[LAYOUTS];
static uint32_t layout_generations[LAYOUTS];
static size_t layout_bytes;
static layout_state *layout(uint64_t id) {
    uint32_t slot = (uint32_t)id;
    if (!slot || slot > LAYOUTS || !layouts[slot-1] || layouts[slot-1]->generation != (uint32_t)(id >> 32) || !font(layouts[slot-1]->font)) return NULL;
    return layouts[slot-1];
}
static int capture_glyph(layout_capture *c, layout_glyph g) {
    if (c->count == c->capacity) {
        size_t n = c->capacity ? c->capacity*2 : 64;
        if (n > c->budget / sizeof g) { error("Text layout memory limit"); return 0; }
        layout_glyph *p = realloc(c->glyphs, n*sizeof g); if (!p) { error("Cannot allocate text layout"); return 0; }
        c->glyphs=p; c->capacity=n;
    }
    c->glyphs[c->count++]=g; return 1;
}
typedef struct { int begin, end, face, plain; hb_script_t script; } text_run;
static int append_run(font_state *f, const uint8_t *text, int begin, int end, text_run **runs, int *count, int *capacity, hb_script_t *inherited) {
    int plain=0, face=cluster_face(f,text,begin,end,&plain), at=begin;
    hb_script_t script=hb_unicode_script(hb_unicode_funcs_get_default(),scalar(text,end,&at));
    if(script==HB_SCRIPT_COMMON || script==HB_SCRIPT_INHERITED || script==HB_SCRIPT_UNKNOWN) script=*inherited;
    else *inherited=script;
    if(*count && (*runs)[*count-1].face==face && (*runs)[*count-1].plain==plain &&
        ((*runs)[*count-1].script==script || script==HB_SCRIPT_UNKNOWN)) { (*runs)[*count-1].end=end; return 1; }
    if(*count==*capacity) {
        if(*capacity>INT_MAX/2) return 0;
        int n=*capacity ? *capacity*2 : 16;
        text_run *p=realloc(*runs,(size_t)n*sizeof *p); if(!p) return 0; *runs=p; *capacity=n;
    }
    (*runs)[(*count)++]=(text_run){begin,end,face,plain,script}; return 1;
}
static int64_t shape_text(uint64_t handle, const uint8_t *text, int64_t length,
    float *out, uint32_t *clusters, int64_t capacity, float *width,
    int rasterize, int windowed, float left, float right, layout_capture *captured) {
    font_state *f = font(handle); *width = 0;
    if (!f || length < 0 || length > INT_MAX || (length && !text) || capacity < 0) { error("Invalid font or text slice"); return -1; }
    f->sealed = 1;
    if (!length) return 0;
    hb_buffer_t *buffer = hb_buffer_create();
    hb_buffer_add_utf8(buffer, (const char *)text, (int)length, 0, (int)length);
    hb_buffer_guess_segment_properties(buffer);
    hb_direction_t direction = hb_buffer_get_direction(buffer);
    if (!hb_buffer_allocation_successful(buffer)) {
        hb_buffer_destroy(buffer); error("Cannot allocate text shaping buffer"); return -1;
    }
    unsigned int count = 0;
    hb_glyph_info_t *infos;
    text_run *runs = NULL;
    int run_count = 0, run_capacity=0, cluster_begin=0, at=0;
    hb_script_t inherited = HB_SCRIPT_UNKNOWN;
    text_grapheme boundaries={.previous=-1};
    while(at<length) {
        int start=at; uint32_t cp=scalar(text,(int)length,&at);
        if(text_feed(&boundaries,cp) && start>cluster_begin) {
            if(!append_run(f,text,cluster_begin,start,&runs,&run_count,&run_capacity,&inherited)) goto run_error;
            cluster_begin=start;
        }
    }
    if(!append_run(f,text,cluster_begin,(int)length,&runs,&run_count,&run_capacity,&inherited)) goto run_error;
    float pen_x = 0, pen_y = 0;
    int64_t total = 0;
    for (int r = 0; r < run_count; ++r) {
        text_run run = runs[HB_DIRECTION_IS_BACKWARD(direction) ? run_count - r - 1 : r];
        hb_buffer_clear_contents(buffer);
        hb_buffer_add_utf8(buffer, (const char *)text, (int)length, (unsigned int)run.begin, run.end - run.begin);
        hb_buffer_set_direction(buffer, direction);
        if (run.script != HB_SCRIPT_UNKNOWN) hb_buffer_set_script(buffer, run.script);
        hb_buffer_guess_segment_properties(buffer);
        hb_shape(f->faces[run.face].hb, buffer, NULL, 0);
        if (!hb_buffer_allocation_successful(buffer)) { free(runs); hb_buffer_destroy(buffer); error("Cannot allocate shaped font run"); return -1; }
        infos = hb_buffer_get_glyph_infos(buffer, &count);
        hb_glyph_position_t *positions = hb_buffer_get_glyph_positions(buffer, NULL);
        for (unsigned int i = 0; i < count; ++i) {
            hb_glyph_position_t p = positions[i];
            if (captured) {
                float x = (pen_x + (float)p.x_offset / 64) / f->scale;
                float y = (f->ascent * f->scale - pen_y - (float)p.y_offset / 64) / f->scale;
                float begin = -FLT_MAX, end = FLT_MAX; hb_glyph_extents_t extents;
                if (hb_font_get_glyph_extents(f->faces[run.face].hb, infos[i].codepoint, &extents)) {
                    begin = x + (float)extents.x_bearing / (64*f->scale); end = begin + (float)extents.width / (64*f->scale);
                }
                if (!capture_glyph(captured, (layout_glyph){ infos[i].codepoint, infos[i].cluster, run.face, run.plain, x, y, pen_x/f->scale, (float)p.x_advance/(64*f->scale), fminf(begin,end), fmaxf(begin,end) })) { free(runs); hb_buffer_destroy(buffer); return -1; }
            }
            if (windowed) {
                hb_glyph_extents_t extents;
                if (hb_font_get_glyph_extents(f->faces[run.face].hb, infos[i].codepoint, &extents)) {
                    float x = (pen_x + (float)(p.x_offset + extents.x_bearing) / 64) / f->scale;
                    float end = x + (float)extents.width / (64 * f->scale);
                    if (fmaxf(x, end) < left - 1 || fminf(x, end) > right + 1) {
                        pen_x += (float)p.x_advance / 64; pen_y += (float)p.y_advance / 64;
                        continue;
                    }
                }
            }
            if (clusters && total < capacity) clusters[total] = infos[i].cluster;
            if (out && total < capacity) {
                if (rasterize) {
                    cached_glyph *g = cache(f, run.face, infos[i].codepoint, run.plain);
                    if (!g) { free(runs); hb_buffer_destroy(buffer); return -1; }
                    const float geometry[8] = {
                    floorf((pen_x + (float)p.x_offset / 64 + g->left) + 0.5f) / f->scale,
                    floorf((f->ascent * f->scale - pen_y - (float)p.y_offset / 64 - g->top) + 0.5f) / f->scale,
                    (float)g->w / f->scale, (float)g->h / f->scale,
                    (float)g->x / ATLAS, (float)g->y / ATLAS,
                    (float)(g->x + g->w) / ATLAS, (float)(g->y + g->h) / ATLAS,
                    };
                    memcpy(out + total * 11, geometry, sizeof geometry);
                    out[total*11+10]=(float)g->colored;
                } else { memset(out + total * 11, 0, sizeof(float) * 8); out[total*11+10]=0; }
                out[total * 11 + 8] = pen_x / f->scale;
                out[total * 11 + 9] = (float)p.x_advance / (64 * f->scale);
            }
            pen_x += (float)p.x_advance / 64; pen_y += (float)p.y_advance / 64;
            ++total;
        }
    }
    *width = fabsf(pen_x) / f->scale;
    free(runs); hb_buffer_destroy(buffer);
    return total;
run_error:
    free(runs); hb_buffer_destroy(buffer); error("Cannot allocate font runs"); return -1;
}
int64_t glab_text_shape(uint64_t f, const uint8_t *t, int64_t n,
    float *out, uint32_t *clusters, int64_t capacity, float *width) {
    return shape_text(f, t, n, out, clusters, capacity, width, 1, 0, 0, 0, NULL);
}
int64_t glab_text_geometry(uint64_t f, const uint8_t *t, int64_t n,
    float *out, uint32_t *clusters, int64_t capacity, float *width) {
    return shape_text(f, t, n, out, clusters, capacity, width, 0, 0, 0, 0, NULL);
}
int64_t glab_text_window(uint64_t f, const uint8_t *t, int64_t n, float left, float right,
    float *out, uint32_t *clusters, int64_t capacity, float *width) {
    if (!isfinite(left) || !isfinite(right) || right < left) { error("Invalid text window"); return -1; }
    return shape_text(f, t, n, out, clusters, capacity, width, 1, 1, left, right, NULL);
}
float glab_text_width(uint64_t f, const uint8_t *t, int64_t n) { float width = 0; glab_text_shape(f, t, n, NULL, NULL, 0, &width); return width; }
static int compare_offsets(const void *a, const void *b) {
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b; return x > y ? 1 : x < y ? -1 : 0;
}
static int permitted(const uint32_t *breaks, int64_t count, uint32_t offset) {
    int64_t lo = 0, hi = count;
    while (lo < hi) { int64_t mid = lo + (hi - lo) / 2; if (breaks[mid] < offset) lo = mid + 1; else hi = mid; }
    return lo < count && breaks[lo] == offset;
}
static int64_t fit_at(uint64_t handle, const uint8_t *text, int64_t length, float limit,
    const uint32_t *breaks, int64_t allowed_count, uint32_t origin) {
    if (!isfinite(limit) || limit < 0) { error("Invalid text fitting width"); return -1; }
    float width;
    int64_t count = glab_text_shape(handle, text, length, NULL, NULL, 0, &width);
    if (count < 0 || !length) return count < 0 ? -1 : 0;
    if (width <= limit) return length;
    uint32_t *offsets = malloc(((size_t)count + 1) * sizeof *offsets);
    if (!offsets) { error("Cannot allocate text break offsets"); return -1; }
    if (glab_text_shape(handle, text, length, NULL, offsets, count, &width) != count) { free(offsets); return -1; }
    offsets[count] = (uint32_t)length;
    qsort(offsets, (size_t)count + 1, sizeof *offsets, compare_offsets);
    int64_t n = 0;
    for (int64_t i = 0; i <= count; ++i) if (offsets[i] && (!n || offsets[i] != offsets[n - 1]) &&
        (allowed_count < 0 || offsets[i] == length || permitted(breaks, allowed_count, origin + offsets[i]))) offsets[n++] = offsets[i];
    /* A font may expose several shaped clusters for one unsupported emoji
       sequence. Wrapping must still keep that editing unit intact. Intersect
       candidates in one streaming pass without another per-scalar array. */
    int at=0; int64_t candidate=0, kept=0; text_grapheme boundaries={.previous=-1};
    while(at<length && candidate<n) {
        int start=at; int boundary=text_feed(&boundaries,scalar(text,(int)length,&at));
        while(candidate<n && offsets[candidate]<(uint32_t)start) ++candidate;
        if(candidate<n && offsets[candidate]==(uint32_t)start) {
            if(boundary) offsets[kept++]=offsets[candidate]; ++candidate;
        }
    }
    offsets[kept++]=(uint32_t)length; n=kept;
    /* Prefixes are reshaped at the actual break, so contextual substitutions
       and kerning do not borrow advances from the unbroken string. */
    int64_t lo = 0, hi = n;
    while (lo < hi) {
        int64_t mid = lo + (hi - lo) / 2;
        if (glab_text_width(handle, text, offsets[mid]) <= limit) lo = mid + 1; else hi = mid;
    }
    int64_t result = n ? offsets[lo ? lo - 1 : 0] : length;
    free(offsets); return result; /* One indivisible cluster may exceed limit. */
}
int64_t glab_text_fit(uint64_t handle, const uint8_t *text, int64_t length, float limit) {
    return fit_at(handle, text, length, limit, NULL, -1, 0);
}
int64_t glab_text_fit_at(uint64_t handle, const uint8_t *text, int64_t length, float limit,
    const uint32_t *breaks, int64_t count, uint32_t origin) {
    if (count < 0 || (count && !breaks) || length < 0 || origin > INT_MAX || length > INT_MAX - origin) {
        error("Invalid text break slice or origin"); return -1;
    }
    for (int64_t i = 0; i < count; ++i) if (!breaks[i] || breaks[i] > INT_MAX ||
        (i && breaks[i] <= breaks[i - 1])) {
        error("Text break offsets must be ordered UTF-8 byte positions"); return -1;
    }
    return fit_at(handle, text, length, limit, breaks, count, origin);
}
uint64_t glab_text_revision(uint64_t handle) { font_state *f = font(handle); return f ? f->revision : 0; }
int64_t glab_text_pixels(uint64_t handle, uint8_t *out, int64_t capacity) {
    font_state *f = font(handle); if (!f || capacity < 0) return 0;
    int64_t size = ATLAS * ATLAS * 4;
    if (out) memcpy(out, f->pixels, (size_t)(capacity < size ? capacity : size));
    return size;
}

/* Owned, full-line shaping; source-byte carets and viewport-only rasterization.
   Borrowed font must outlive this resource. Existing immediate APIs stay unchanged. */
uint64_t glab_text_layout_create(uint64_t font_id, const uint8_t *source, int64_t length, const uint32_t *carets, int64_t caret_count) {
    last_error[0]=0;
    if (!font(font_id) || length < 0 || length > LAYOUT_SOURCE || (length && !source)) { error("Invalid text layout input"); return 0; }
    if(!carets || caret_count<1 || caret_count>length+1 || carets[0]!=0 || carets[caret_count-1]!=(uint32_t)length) { error("Invalid grapheme carets"); return 0; }
    for(int64_t i=1;i<caret_count;++i) if(carets[i]<=carets[i-1] || carets[i]>(uint32_t)length || (carets[i]<(uint32_t)length && (source[carets[i]] & 0xc0)==0x80)) { error("Invalid grapheme boundary"); return 0; }
    uint32_t slot=0; while (slot<LAYOUTS && layouts[slot]) ++slot;
    if (slot==LAYOUTS) { error("Text layout capacity exceeded"); return 0; }
    size_t shown_length=0, stop_count=1; int at=0;
    while (at<length) {
        int first=at; uint32_t cp=scalar(source,(int)length,&at);
        if (cp==0xfffd && !(at-first==3 && source[first]==0xef && source[first+1]==0xbf && source[first+2]==0xbd)) { error("Invalid UTF-8 text layout"); return 0; }
        shown_length += cp==9 ? 4 : (cp<32 || (cp>=127 && cp<=159) || cp==0x2028 || cp==0x2029 ? 1 : (size_t)(at-first)); ++stop_count;
    }
    size_t stop_bytes=stop_count*sizeof(layout_stop), working=stop_bytes + stop_count*sizeof(uint32_t) + shown_length;
    size_t capacity=64; while (capacity<shown_length) capacity*=2;
    if (working + sizeof(layout_state) > LAYOUT_MEMORY || layout_bytes > LAYOUT_MEMORY-working-sizeof(layout_state) ||
        capacity*sizeof(layout_glyph) > LAYOUT_MEMORY-layout_bytes-working-sizeof(layout_state)) { error("Text layout memory limit"); return 0; }
    layout_state *l=calloc(1,sizeof *l); uint8_t *shown=malloc(shown_length ? shown_length : 1); uint32_t *offsets=malloc(stop_count*sizeof *offsets);
    if (!l || !shown || !offsets) { free(l); free(shown); free(offsets); error("Cannot allocate text layout"); return 0; }
    l->stops=malloc(stop_bytes); if (!l->stops) { free(l); free(shown); free(offsets); error("Cannot allocate text layout stops"); return 0; }
    l->captured.budget=LAYOUT_MEMORY-layout_bytes-working-sizeof(layout_state);
    l->font=font_id; l->stop_count=stop_count; l->stops[0]=(layout_stop){0,0}; offsets[0]=0;
    at=0; size_t count=1, pos=0; int64_t caret=1;
    while (at<length) {
        int first=at; uint32_t cp=scalar(source,(int)length,&at);
        if (cp==9) { memset(shown+pos,' ',4); pos+=4; }
        else if (cp<32 || (cp>=127 && cp<=159) || cp==0x2028 || cp==0x2029) shown[pos++]='.';
        else { memcpy(shown+pos,source+first,(size_t)(at-first)); pos+=(size_t)(at-first); }
        while(caret<caret_count && carets[caret]<(uint32_t)at) ++caret;
        uint32_t byte=(uint32_t)at;
        if(caret==caret_count || carets[caret]!=byte) byte |= 0x80000000u;
        l->stops[count]=(layout_stop){byte,0}; offsets[count++]=(uint32_t)pos;
    }
    int64_t n=shape_text(font_id,shown,(int64_t)shown_length,NULL,NULL,0,&l->width,0,0,0,0,&l->captured);
    if (n<0) { free(l->captured.glyphs); free(l->stops); free(l); free(shown); free(offsets); return 0; }
    // Same scalar interpolation as lab.ui.controls.field, with sparse cluster endpoints.
    size_t k=0, stop=1;
    while (k<l->captured.count) {
        layout_glyph g=l->captured.glyphs[k]; float end=g.pen;
        size_t j=k; while (j<l->captured.count && l->captured.glyphs[j].cluster==g.cluster) { end=l->captured.glyphs[j].pen+l->captured.glyphs[j].advance; ++j; }
        uint32_t next=j<l->captured.count ? l->captured.glyphs[j].cluster : (uint32_t)shown_length;
        if (next>g.cluster) {
            // Count displayed scalars, including the four spaces of a source Tab.
            int b=(int)g.cluster; size_t scalars=0; while (b<(int)next) { scalar(shown,(int)next,&b); ++scalars; }
            b=(int)g.cluster; size_t ordinal=0;
            while (b<(int)next) { scalar(shown,(int)next,&b); ++ordinal;
                while (stop<stop_count && offsets[stop]<=(uint32_t)b) { l->stops[stop++].x=g.pen+(end-g.pen)*(float)ordinal/(float)scalars; }
            }
        }
        k=j;
    }
    while (stop<stop_count) l->stops[stop++].x=l->width;
    l->block_count=(l->captured.count+LAYOUT_BLOCK-1)/LAYOUT_BLOCK;
    l->blocks=malloc((l->block_count ? l->block_count : 1)*2*sizeof(float));
    l->bytes=sizeof *l+stop_bytes+l->captured.capacity*sizeof(layout_glyph)+(l->block_count ? l->block_count : 1)*2*sizeof(float);
    if (!l->blocks || layout_bytes+l->bytes>LAYOUT_MEMORY) { free(l->blocks); free(l->captured.glyphs); free(l->stops); free(l); free(shown); free(offsets); error("Text layout memory limit"); return 0; }
    for (size_t block=0; block<l->block_count; ++block) {
        float left=FLT_MAX,right=-FLT_MAX;
        for (size_t i=block*LAYOUT_BLOCK;i<l->captured.count && i<(block+1)*LAYOUT_BLOCK;++i) { left=fminf(left,l->captured.glyphs[i].left); right=fmaxf(right,l->captured.glyphs[i].right); }
        l->blocks[block*2]=left; l->blocks[block*2+1]=right;
    }
    free(shown); free(offsets); uint32_t generation=++layout_generations[slot]; if (!generation) generation=++layout_generations[slot];
    l->generation=generation; layouts[slot]=l; layout_bytes+=l->bytes; return ((uint64_t)generation<<32)|(slot+1);
}
void glab_text_layout_destroy(uint64_t id) {
    uint32_t slot=(uint32_t)id;
    if (!slot || slot>LAYOUTS || !layouts[slot-1] || layouts[slot-1]->generation!=(uint32_t)(id>>32)) return;
    layout_state *l=layouts[slot-1]; layout_bytes-=l->bytes; free(l->blocks); free(l->captured.glyphs); free(l->stops); free(l); layouts[slot-1]=NULL;
}
float glab_text_layout_width(uint64_t id) { layout_state *l=layout(id); return l ? l->width : 0; }
int64_t glab_text_layout_bytes(uint64_t id) { layout_state *l=layout(id); return l ? (int64_t)l->bytes : 0; }
float glab_text_layout_position(uint64_t id, int64_t byte) {
    layout_state *l=layout(id); if (!l || byte<0) return 0;
    size_t first=0,end=l->stop_count; while(first<end) { size_t m=first+(end-first)/2; if((l->stops[m].byte & 0x7fffffffu)<(uint64_t)byte) first=m+1; else end=m; }
    return first<l->stop_count && (l->stops[first].byte & 0x7fffffffu)==(uint64_t)byte ? l->stops[first].x : 0;
}
int64_t glab_text_layout_hit(uint64_t id, float x) {
    layout_state *l=layout(id); if (!l || !isfinite(x)) return 0;
    // LTR editor policy; the retained caret positions also handle ligature interiors.
    size_t first=0,end=l->stop_count; while(first<end) { size_t m=first+(end-first)/2; if(l->stops[m].x<x) first=m+1; else end=m; }
    size_t right=first; while(right<l->stop_count && (l->stops[right].byte & 0x80000000u)) ++right;
    size_t left=first; int has_left=0;
    while(left>0) { --left; if(!(l->stops[left].byte & 0x80000000u)) { has_left=1; break; } }
    size_t choice= !has_left ? right : right==l->stop_count || x-l->stops[left].x<=l->stops[right].x-x ? left : right;
    float chosen=l->stops[choice].x;
    for(size_t i=choice;i>0 && l->stops[i-1].x==chosen;) { --i; if(!(l->stops[i].byte & 0x80000000u)) choice=i; }
    return l->stops[choice].byte & 0x7fffffffu;
}
int64_t glab_text_layout_window(uint64_t id, float left, float right, float *out, uint32_t *clusters, int64_t capacity) {
    layout_state *l=layout(id); if (!l || !isfinite(left) || !isfinite(right) || right<left || capacity<0) return -1;
    font_state *f=font(l->font); int64_t count=0;
    for (size_t block=0;block<l->block_count;++block) {
        if (l->blocks[block*2]>right+1 || l->blocks[block*2+1]<left-1) continue;
        for (size_t i=block*LAYOUT_BLOCK;i<l->captured.count && i<(block+1)*LAYOUT_BLOCK;++i) {
            layout_glyph g=l->captured.glyphs[i]; if(g.left>right+1 || g.right<left-1) continue;
            if(clusters && count<capacity) clusters[count]=g.cluster;
            if(out && count<capacity) {
                cached_glyph *r=cache(f,g.face,g.id,g.plain); if(!r) return -1;
                out[count*11]=floorf(g.x*f->scale+r->left+0.5f)/f->scale; out[count*11+1]=floorf(g.y*f->scale-r->top+0.5f)/f->scale;
                out[count*11+2]=(float)r->w/f->scale; out[count*11+3]=(float)r->h/f->scale;
                out[count*11+4]=(float)r->x/ATLAS; out[count*11+5]=(float)r->y/ATLAS;
                out[count*11+6]=(float)(r->x+r->w)/ATLAS; out[count*11+7]=(float)(r->y+r->h)/ATLAS;
                out[count*11+8]=g.pen; out[count*11+9]=g.advance; out[count*11+10]=(float)r->colored;
            }
            ++count;
        }
    }
    return count;
}
int64_t glab_text_layout_live_bytes(void) { return (int64_t)layout_bytes; }

int64_t glab_text_source_bytes(void) { int64_t n=0; for(int i=0;i<FONTS*FACES;++i) if(blobs[i].refs) n+=blobs[i].length; return n; }
int64_t glab_text_atlas_bytes(void) { int64_t n=0; for(int i=0;i<FONTS;++i) if(fonts[i].face_count) n+=ATLAS*ATLAS*4; return n; }
