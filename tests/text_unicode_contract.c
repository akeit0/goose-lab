/* Test bridge only: verify native run boundaries against the official corpus
   and Goose's streaming implementation without adding a second Unicode policy. */
#include "ui/text/internal/unicode.h"
uint8_t glab_test_text_boundary(uint32_t cp, uint8_t reset) {
    static text_grapheme state;
    if(reset) state=(text_grapheme){.previous=-1};
    return (uint8_t)text_feed(&state,cp);
}
