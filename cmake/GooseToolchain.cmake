# Goose is a separately maintained toolchain. Never guess a sibling checkout.
set(GOOSE_SOURCE_DIR "" CACHE PATH "Compatible Goose fork source checkout; see docs/toolchain.md")
if(NOT GOOSE_SOURCE_DIR)
  message(FATAL_ERROR "Set GOOSE_SOURCE_DIR to a compatible Goose source checkout (see docs/toolchain.md).")
endif()
get_filename_component(GOOSE_SOURCE_DIR "${GOOSE_SOURCE_DIR}" ABSOLUTE)
if(NOT EXISTS "${GOOSE_SOURCE_DIR}/src/main.cpp")
  message(FATAL_ERROR "GOOSE_SOURCE_DIR is not a Goose source checkout: ${GOOSE_SOURCE_DIR}")
endif()
# Native packages belong to the consuming application, not the compiler.
set(GOOSE_BUILTIN_LIBS "")
if(NOT TARGET goose)
  add_subdirectory("${GOOSE_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/goose" EXCLUDE_FROM_ALL)
endif()

# Check capabilities once per compiler/probe revision, before generating apps.
# A future upstream checkout can satisfy the same contracts without fork identity.
set(toolchain_check_dir "${CMAKE_CURRENT_BINARY_DIR}/toolchain-check")
file(GLOB_RECURSE toolchain_stdlib CONFIGURE_DEPENDS "${GOOSE_SOURCE_DIR}/stdlib/*.goose")
set(toolchain_gui_inputs)
if(GOOSE_LAB_GUI)
  list(APPEND toolchain_gui_inputs
    "${GOOSE_LAB_SOURCE_DIR}/packages/gfx/gfx.goose"
    "${GOOSE_LAB_SOURCE_DIR}/cmake/GooseGfx.cmake"
    "${GOOSE_LAB_SOURCE_DIR}/tools/toolchain/gui.goose")
endif()
add_custom_command(OUTPUT "${toolchain_check_dir}/checked"
  COMMAND "${CMAKE_COMMAND}"
    "-DCOMPILER=$<TARGET_FILE:goose>"
    "-DGOOSE_SOURCE_DIR=${GOOSE_SOURCE_DIR}"
    "-DLAB_SOURCE_DIR=${GOOSE_LAB_SOURCE_DIR}"
    "-DCHECK_DIR=${toolchain_check_dir}"
    "-DCHECK_GUI=${GOOSE_LAB_GUI}"
    "-DGFX_SOURCE_DIR=${GOOSE_LAB_SOURCE_DIR}/packages/gfx"
    -P "${GOOSE_LAB_SOURCE_DIR}/cmake/CheckToolchain.cmake"
  DEPENDS goose ${toolchain_stdlib} ${toolchain_gui_inputs}
    "${GOOSE_LAB_SOURCE_DIR}/cmake/CheckToolchain.cmake"
    "${GOOSE_LAB_SOURCE_DIR}/tools/toolchain/core.goose"
    "${GOOSE_LAB_SOURCE_DIR}/lib/lab/text/utf8.goose"
  VERBATIM)
add_custom_target(goose_lab_toolchain_check DEPENDS "${toolchain_check_dir}/checked")
