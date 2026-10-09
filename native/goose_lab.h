#ifndef GOOSE_LAB_H
#define GOOSE_LAB_H
/* Feature definitions come from linked goose_lab_* CMake targets. */
#ifdef GOOSE_LAB_LAYOUT
#include "ui/layout/layout_glue.h"
#endif
#ifdef GOOSE_LAB_SCENE
#include "ui/scene/scene_glue.h"
#endif
#ifdef GOOSE_LAB_TEXT
#include "ui/input/shortcuts_glue.h"
#include "ui/text/text_glue.h"
#endif
#ifdef GOOSE_LAB_PROCESS
#include "io/process/process_glue.h"
#endif
#ifdef GOOSE_LAB_PATH
#include "fs/path/path_glue.h"
#endif
#ifdef GOOSE_LAB_FILES
#include "fs/sync/files_glue.h"
#endif
#ifdef GOOSE_LAB_WATCH
#include "fs/watch/watch_glue.h"
#endif
#ifdef GOOSE_LAB_LOOP
#include "io/loop/loop_glue.h"
#endif
#ifdef GOOSE_LAB_CONSOLE
#include "io/console/console_glue.h"
#endif
#ifdef GOOSE_LAB_CANCEL
#include "io/cancel/cancel.h"
#endif
#ifdef GOOSE_LAB_HTTP
#include "net/http/http_glue.h"
#endif
#endif
