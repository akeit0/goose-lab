#ifndef GOOSE_LAB_SCENE_GLUE_H
#define GOOSE_LAB_SCENE_GLUE_H
#include "ui/scene/scene.h"
static int32_t glab_goose_scene_changed(uint64_t id, sl_u8 vertices, sl_u8 batches, sl_u8 key, uint8_t force) { return glab_scene_changed(id, vertices.data, vertices.len, batches.data, batches.len, key.data, key.len, force); }
#endif
