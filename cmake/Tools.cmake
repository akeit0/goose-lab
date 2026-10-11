goose_lab_program(document_profile tools/experiments/document_profile.goose MODULE_DIRS "${GOOSE_LAB_SOURCE_DIR}/tools")
goose_lab_program(document_store_profile tools/experiments/document_store_profile.goose MODULE_DIRS "${GOOSE_LAB_SOURCE_DIR}/tools")
set(workloads "${GOOSE_LAB_SOURCE_DIR}/tools/experiments/workloads")
goose_lab_program(regex_experiment "${workloads}/regex_probe.goose" MODULE_DIRS "${workloads}" "${GOOSE_LAB_SOURCE_DIR}/samples")
goose_lab_program(ecs_game_experiment "${workloads}/ecs_game.goose" MODULE_DIRS "${workloads}" "${GOOSE_LAB_SOURCE_DIR}/samples")
goose_lab_program(server_experiment "${workloads}/server.goose" MODULE_DIRS "${workloads}" "${GOOSE_LAB_SOURCE_DIR}/samples")
target_link_libraries(server_experiment PRIVATE goose_lab_tcp)
if(GOOSE_LAB_BUILD_TESTS)
  add_test(NAME regex_experiment COMMAND "${Python3_EXECUTABLE}"
    "${GOOSE_LAB_SOURCE_DIR}/tests/regex_experiment_fixture.py" $<TARGET_FILE:regex_experiment>)
  add_test(NAME ecs_game_experiment COMMAND "${Python3_EXECUTABLE}"
    "${GOOSE_LAB_SOURCE_DIR}/tests/ecs_game_fixture.py" $<TARGET_FILE:ecs_game_experiment>)
  add_test(NAME server_experiment COMMAND "${Python3_EXECUTABLE}"
    "${GOOSE_LAB_SOURCE_DIR}/tests/server_experiment_fixture.py" $<TARGET_FILE:server_experiment>)
  add_test(NAME document_experiment_smoke COMMAND "${Python3_EXECUTABLE}"
    "${GOOSE_LAB_SOURCE_DIR}/tests/document_experiment_fixture.py"
    "${GOOSE_LAB_SOURCE_DIR}/tools/document_experiment.py" "${CMAKE_CURRENT_BINARY_DIR}" "$<CONFIG>")
  add_test(NAME document_store_experiment_smoke COMMAND "${Python3_EXECUTABLE}"
    "${GOOSE_LAB_SOURCE_DIR}/tests/document_store_experiment_fixture.py"
    "${GOOSE_LAB_SOURCE_DIR}/tools/document_store_experiment.py" "${CMAKE_CURRENT_BINARY_DIR}" "$<CONFIG>")
endif()
if(GOOSE_LAB_GUI)
  goose_lab_gui_program(ui_profile tools/ui/profile.goose LIBRARIES goose_lab_watch MODULE_DIRS "${GOOSE_LAB_SOURCE_DIR}/samples")
endif()
