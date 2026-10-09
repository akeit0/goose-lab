#ifndef GOOSE_LAB_SCENE_H
#define GOOSE_LAB_SCENE_H
#include <stdint.h>
uint64_t glab_scene_create(void);
void glab_scene_destroy(uint64_t id);
/* Exact frame comparison; 1 changed, 0 identical, -1 invalid/allocation failure.
   Owned snapshots grow with actual vertex/batch counts; no borrowed bytes survive. */
int32_t glab_scene_changed(uint64_t id, const uint8_t *a, int64_t an, const uint8_t *b, int64_t bn, const uint8_t *key, int64_t kn, uint8_t force);
int64_t glab_scene_live_bytes(void);
#endif
