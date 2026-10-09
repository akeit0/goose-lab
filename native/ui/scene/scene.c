#include "ui/scene/scene.h"
#include <stdlib.h>
#include <string.h>
enum { SCENES=16, MAX_BYTES=10922*72+2048*40+1024 };
typedef struct { uint32_t generation; uint8_t *bytes; size_t capacity, an, bn, kn; int live, valid; } scene;
static scene scenes[SCENES];
static scene *get(uint64_t id) { uint32_t i=(uint32_t)id; return i && i<=SCENES && scenes[i-1].live && scenes[i-1].generation==(uint32_t)(id>>32) ? &scenes[i-1] : NULL; }
uint64_t glab_scene_create(void) {
    for (uint32_t i=0;i<SCENES;++i) if (!scenes[i].live) { scene *s=&scenes[i]; uint32_t g=s->generation+1; if(!g) g=1; memset(s,0,sizeof *s); s->generation=g; s->live=1; return ((uint64_t)g<<32)|(i+1); } return 0;
}
void glab_scene_destroy(uint64_t id) { scene *s=get(id); if(s) { free(s->bytes); s->bytes=NULL; s->capacity=0; s->live=0; } }
int32_t glab_scene_changed(uint64_t id,const uint8_t *a,int64_t an,const uint8_t *b,int64_t bn,const uint8_t *key,int64_t kn,uint8_t force) {
    scene *s=get(id);
    if(!s || an<0 || bn<0 || kn<0 || an>MAX_BYTES || bn>MAX_BYTES-an || kn>MAX_BYTES-an-bn || (an&&!a) || (bn&&!b) || (kn&&!key)) return -1;
    size_t n=(size_t)(an+bn+kn);
    if(!force && s->valid && s->an==(size_t)an && s->bn==(size_t)bn && s->kn==(size_t)kn &&
       (!an || !memcmp(s->bytes,a,(size_t)an)) && (!bn || !memcmp(s->bytes+an,b,(size_t)bn)) && (!kn || !memcmp(s->bytes+an+bn,key,(size_t)kn))) return 0;
    if(n>s->capacity) { size_t cap=256; while(cap<n) cap*=2; uint8_t *p=realloc(s->bytes,cap); if(!p) return -1; s->bytes=p; s->capacity=cap; }
    if(an) memcpy(s->bytes,a,(size_t)an); if(bn) memcpy(s->bytes+an,b,(size_t)bn); if(kn) memcpy(s->bytes+an+bn,key,(size_t)kn);
    s->an=(size_t)an; s->bn=(size_t)bn; s->kn=(size_t)kn; s->valid=1; return 1;
}
int64_t glab_scene_live_bytes(void) { int64_t n=0; for(int i=0;i<SCENES;++i) if(scenes[i].live) n+=(int64_t)(sizeof(scene)+scenes[i].capacity); return n; }
