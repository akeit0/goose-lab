file(MAKE_DIRECTORY "${CHECK_DIR}")
set(probes core)
if(CHECK_GUI)
  list(APPEND probes gui)
endif()
foreach(probe IN LISTS probes)
  set(entry "${LAB_SOURCE_DIR}/tools/toolchain/${probe}.goose")
  if(probe STREQUAL "gui")
    set(entry "${CHECK_DIR}/gui.goose")
    file(READ "${LAB_SOURCE_DIR}/tools/toolchain/gui.goose" body)
    file(WRITE "${entry}" "import gfx from \"${GFX_SOURCE_DIR}\";\n${body}")
  endif()
  execute_process(
    COMMAND "${COMPILER}" --stdlib "${GOOSE_SOURCE_DIR}/stdlib"
      --module-dir "${LAB_SOURCE_DIR}/lib" --standalone
      -o "${CHECK_DIR}/${probe}.c" "${entry}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR
      "The selected Goose toolchain lacks required ${probe} capabilities.\n"
      "Use the revision documented in docs/toolchain.md, or a compatible toolchain.\n"
      "${output}${error}")
  endif()
endforeach()
if(CHECK_GUI)
  file(READ "${CHECK_DIR}/gui.c" generated)
  foreach(type sl_f32 sl_u32)
    string(FIND "${generated}" "#ifndef GS_TYPE_${type}" position)
    if(position LESS 0)
      message(FATAL_ERROR
        "The selected Goose compiler lacks guarded ${type} declarations needed by text adapters.\n"
        "See docs/toolchain.md.")
    endif()
  endforeach()
endif()
file(WRITE "${CHECK_DIR}/checked" "core=${COMPILER}\ngui=${CHECK_GUI}\n")
