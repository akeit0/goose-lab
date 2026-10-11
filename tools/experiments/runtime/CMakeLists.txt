cmake_minimum_required(VERSION 3.20)
project(goose_pool_experiment LANGUAGES C CXX)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(GOOSE_SOURCE_DIR "" CACHE PATH "Explicit Goose checkout to test")
if(NOT EXISTS "${GOOSE_SOURCE_DIR}/src/main.cpp")
  message(FATAL_ERROR "Set GOOSE_SOURCE_DIR to the Goose checkout under test")
endif()
get_filename_component(GOOSE_SOURCE_DIR "${GOOSE_SOURCE_DIR}" ABSOLUTE)
set(GOOSE_SOURCE_DIR "${GOOSE_SOURCE_DIR}" CACHE PATH "Explicit Goose checkout to test" FORCE)
# This compiler/runtime experiment needs no optional native modules or lab fork APIs.
foreach(feature GFX AUDIO PHYSICS UI LIBTCC)
  set(GOOSE_${feature} OFF CACHE BOOL "" FORCE)
endforeach()
add_subdirectory("${GOOSE_SOURCE_DIR}" goose EXCLUDE_FROM_ALL)
set(source "${CMAKE_CURRENT_SOURCE_DIR}/pool_runtime.goose")
set(generated "${CMAKE_CURRENT_BINARY_DIR}/pool_runtime.c")
file(GLOB_RECURSE stdlib CONFIGURE_DEPENDS "${GOOSE_SOURCE_DIR}/stdlib/*.goose")
add_custom_command(OUTPUT "${generated}"
  COMMAND $<TARGET_FILE:goose> --stdlib "${GOOSE_SOURCE_DIR}/stdlib" --standalone -o "${generated}" "${source}"
  DEPENDS goose "${source}" ${stdlib} VERBATIM)
add_executable(pool_runtime "${generated}")
set(storage_c "${CMAKE_CURRENT_BINARY_DIR}/buffer_storage.c")
add_custom_command(OUTPUT "${storage_c}"
  COMMAND $<TARGET_FILE:goose> --stdlib "${GOOSE_SOURCE_DIR}/stdlib" --standalone -o "${storage_c}"
    "${CMAKE_CURRENT_SOURCE_DIR}/buffer_storage.goose"
  DEPENDS goose "${CMAKE_CURRENT_SOURCE_DIR}/buffer_storage.goose" ${stdlib} VERBATIM)
add_executable(buffer_storage "${storage_c}")
get_filename_component(lab_root "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(indexed_c "${CMAKE_CURRENT_BINARY_DIR}/indexed_buffer.c")
add_custom_command(OUTPUT "${indexed_c}"
  COMMAND $<TARGET_FILE:goose> --stdlib "${GOOSE_SOURCE_DIR}/stdlib" --module-dir "${lab_root}/lib"
    --standalone -o "${indexed_c}" "${CMAKE_CURRENT_SOURCE_DIR}/indexed_buffer.goose"
  DEPENDS goose "${CMAKE_CURRENT_SOURCE_DIR}/indexed_buffer.goose" "${lab_root}/lib/lab/buffer/indexed.goose" ${stdlib} VERBATIM)
add_executable(indexed_buffer "${indexed_c}")
set(exhaustion_c "${CMAKE_CURRENT_BINARY_DIR}/pool_exhaustion.c")
add_custom_command(OUTPUT "${exhaustion_c}"
  COMMAND $<TARGET_FILE:goose> --stdlib "${GOOSE_SOURCE_DIR}/stdlib" --standalone -o "${exhaustion_c}"
    "${CMAKE_CURRENT_SOURCE_DIR}/reservation_exhaustion.goose"
  DEPENDS goose "${CMAKE_CURRENT_SOURCE_DIR}/reservation_exhaustion.goose" ${stdlib} VERBATIM)
add_executable(pool_exhaustion "${exhaustion_c}")
target_compile_definitions(pool_exhaustion PRIVATE GS_STACK_RESERVE=1048576)
find_package(Threads REQUIRED)
target_link_libraries(pool_runtime PRIVATE Threads::Threads)
target_link_libraries(buffer_storage PRIVATE Threads::Threads)
target_link_libraries(indexed_buffer PRIVATE Threads::Threads)
target_link_libraries(pool_exhaustion PRIVATE Threads::Threads)
if(MSVC)
  target_compile_options(pool_runtime PRIVATE /utf-8)
  target_compile_options(buffer_storage PRIVATE /utf-8)
  target_compile_options(indexed_buffer PRIVATE /utf-8)
  target_compile_options(pool_exhaustion PRIVATE /utf-8)
  target_link_options(pool_runtime PRIVATE /STACK:67108864)
  target_link_options(buffer_storage PRIVATE /STACK:67108864)
  target_link_options(indexed_buffer PRIVATE /STACK:67108864)
elseif(WIN32)
  target_link_options(pool_runtime PRIVATE -Wl,--stack,67108864)
  target_link_options(buffer_storage PRIVATE -Wl,--stack,67108864)
  target_link_options(indexed_buffer PRIVATE -Wl,--stack,67108864)
else()
  target_link_libraries(pool_runtime PRIVATE m)
  target_link_libraries(buffer_storage PRIVATE m)
  target_link_libraries(indexed_buffer PRIVATE m)
  target_link_libraries(pool_exhaustion PRIVATE m)
endif()
enable_testing()
add_test(NAME pool_runtime_contract COMMAND pool_runtime contract 3 256 4)
find_package(Python3 COMPONENTS Interpreter REQUIRED)
add_test(NAME pool_reservation_exhaustion COMMAND "${Python3_EXECUTABLE}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../tests/pool_exhaustion_fixture.py" $<TARGET_FILE:pool_exhaustion>)
add_test(NAME pool_descriptor_diagnostic COMMAND "${Python3_EXECUTABLE}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../tests/pool_compiler_fixture.py"
  $<TARGET_FILE:goose> "${GOOSE_SOURCE_DIR}/stdlib" "${CMAKE_CURRENT_SOURCE_DIR}/index_of_descriptor.goose")
add_test(NAME pool_runtime_experiment_smoke COMMAND "${Python3_EXECUTABLE}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../tests/pool_runtime_experiment_fixture.py"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../pool_runtime_experiment.py" "${CMAKE_CURRENT_BINARY_DIR}" "$<CONFIG>")
add_test(NAME buffer_storage_experiment_smoke COMMAND "${Python3_EXECUTABLE}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../tests/buffer_storage_experiment_fixture.py"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../buffer_storage_experiment.py" "${CMAKE_CURRENT_BINARY_DIR}" "$<CONFIG>")
