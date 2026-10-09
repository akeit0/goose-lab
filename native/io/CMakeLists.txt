goose_lab_native_library(goose_lab_cancel CANCEL
  SOURCES cancel/cancel.c PRIVATE_LIBRARIES Threads::Threads)
goose_lab_native_library(goose_lab_process PROCESS
  SOURCES process/process.c LIBRARIES goose_lab_cancel)

# One owner-thread registry drives all libuv resources. Filesystem jobs have
# their own archive and portable types; they do not depend on this registry.
goose_lab_native_library(goose_lab_loop LOOP
  SOURCES loop/loop.c
  LIBRARIES goose_lab_process goose_lab_path
  PRIVATE_LIBRARIES uv_a goose_lab_fs_jobs)

add_library(goose_lab_console INTERFACE)
target_include_directories(goose_lab_console INTERFACE "${GOOSE_LAB_SOURCE_DIR}/native")
target_compile_definitions(goose_lab_console INTERFACE GOOSE_LAB_CONSOLE=1)
