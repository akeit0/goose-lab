#include "io/cancel/cancel.h"
#include <stdio.h>
#include <stdlib.h>
#define CHECK(expr) do { if (!(expr)) { fprintf(stderr, "cancel contract line %d: %s\n", __LINE__, #expr); abort(); } } while (0)

int main(void) {
    uint64_t id = glab_cancel_create(); CHECK(id && glab_cancel_valid(id));
    glab_cancel_lease lease = NULL; CHECK(glab_cancel_acquire(id, &lease));
    CHECK(!glab_cancel_check(lease)); CHECK(glab_cancel_request(id));
    CHECK(glab_cancel_request(id) && glab_cancel_requested(id) && glab_cancel_check(lease));
    CHECK(glab_cancel_destroy(id)); CHECK(!glab_cancel_valid(id));
    CHECK(!glab_cancel_destroy(id) && !glab_cancel_request(id) && !glab_cancel_requested(id));
    CHECK(glab_cancel_check(lease));
    uint64_t next = glab_cancel_create(); CHECK(next && (uint32_t)next != (uint32_t)id);
    glab_cancel_release(lease);
    uint64_t reused = glab_cancel_create(); CHECK(reused && (uint32_t)reused == (uint32_t)id && reused != id);
    CHECK(!glab_cancel_request(id) && !glab_cancel_requested(reused));
    CHECK(glab_cancel_destroy(next) && glab_cancel_destroy(reused));
    uint64_t slots[64];
    for (int i = 0; i < 64; ++i) { slots[i] = glab_cancel_create(); CHECK(slots[i]); }
    CHECK(!glab_cancel_create());
    for (int i = 0; i < 64; ++i) CHECK(glab_cancel_destroy(slots[i]));
    for (int i = 0; i < 200; ++i) {
        uint64_t token = glab_cancel_create(); CHECK(token && glab_cancel_destroy(token));
    }
    puts("Cancellation ownership, sticky signals, pinned slots, generations and capacity passed");
    return 0;
}
