#ifndef GOOSE_LAB_TEXT_UNICODE_H
#define GOOSE_LAB_TEXT_UNICODE_H
#include <stdint.h>
#include <stddef.h>
#include "ui/text/internal/unicode_data.h"
/* Same Unicode 17 streaming GB1..GB999 rules as lab.text.grapheme. Constant state,
   no per-scalar allocation; keep shaping runs outside editing clusters. */
static uint16_t text_property(uint32_t cp) {
    if(cp<128) {
        if(cp==13) return 1; if(cp==10) return 2; if(cp<32 || cp==127) return 3;
        return cp=='#' || cp=='*' || (cp>='0' && cp<='9') ? 256 : 0;
    }
    if (cp>=0xAC00 && cp<=0xD7A3) return (cp-0xAC00)%28==0 ? 12 : 13;
    size_t lo=0, hi=sizeof text_unicode_ranges/sizeof *text_unicode_ranges;
    while(lo<hi) { size_t m=(lo+hi)/2; if(text_unicode_ranges[m].last<cp) lo=m+1; else hi=m; }
    return lo<sizeof text_unicode_ranges/sizeof *text_unicode_ranges && text_unicode_ranges[lo].first<=cp ? text_unicode_ranges[lo].flags : 0;
}
typedef struct { int previous; uint32_t regional; int emoji, zwj, consonant, linker; } text_grapheme;
static int text_control(int p) { p &= 15; return p==1 || p==2 || p==3; }
static int text_feed(text_grapheme *s, uint32_t cp) {
    int p=text_property(cp), l=s->previous & 15, r=p & 15, boundary=s->previous<0;
    if(s->previous>=0) {
        if(l==1 && r==2) boundary=0;
        else if(text_control(s->previous) || text_control(p)) boundary=1;
        else if(l==9 && (r==9 || r==10 || r==12 || r==13)) boundary=0;
        else if((l==12 || l==10) && (r==10 || r==11)) boundary=0;
        else if((l==13 || l==11) && r==11) boundary=0;
        else if(r==4 || r==5 || r==8 || l==7) boundary=0;
        else if((p & 32) && s->consonant && s->linker) boundary=0;
        else if((p & 16) && s->zwj) boundary=0;
        else if(l==6 && r==6) boundary=s->regional%2==0;
        else boundary=1;
    }
    s->regional=r==6 ? s->regional+1 : 0;
    s->zwj=r==5 && s->emoji;
    if(p & 16) s->emoji=1; else if(r!=4) s->emoji=0;
    if(p & 32) { s->consonant=1; s->linker=0; }
    else if(p & 64) s->linker |= s->consonant;
    else if(!(p & 128)) { s->consonant=0; s->linker=0; }
    s->previous=p; return boundary;
}
#endif
