#ifndef GOOSE_LAB_CANCEL_H
#define GOOSE_LAB_CANCEL_H
#include <stdint.h>

/* Copyable, generation-checked IDs. One owner destroys; other threads signal. */
uint64_t glab_cancel_create(void);
uint8_t glab_cancel_valid(uint64_t id);
uint8_t glab_cancel_request(uint64_t id);
uint8_t glab_cancel_requested(uint64_t id);
uint8_t glab_cancel_destroy(uint64_t id);

/* Native operations pin a slot so destroying its owner cannot reuse it while
   a callback is reading it. Leases never cross the Goose ABI. */
typedef struct glab_cancel_entry *glab_cancel_lease;
uint8_t glab_cancel_acquire(uint64_t id, glab_cancel_lease *lease);
uint8_t glab_cancel_check(glab_cancel_lease lease);
void glab_cancel_release(glab_cancel_lease lease);
#endif
