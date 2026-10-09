goose_lab_native_library(goose_lab_files FILES SOURCES sync/files.c)
goose_lab_native_library(goose_lab_path PATH SOURCES path/path.c PRIVATE_LIBRARIES uv_a)

# Implementation-only asynchronous state machines; no generated-Goose adapter.
goose_lab_native_library(goose_lab_fs_jobs ""
  SOURCES internal/file_job.c internal/write_job.c PRIVATE_LIBRARIES uv_a)

# Watch handles share the loop's generation registry and lifetime rules.
add_library(goose_lab_watch INTERFACE)
target_link_libraries(goose_lab_watch INTERFACE goose_lab_loop)
target_compile_definitions(goose_lab_watch INTERFACE GOOSE_LAB_WATCH=1)
