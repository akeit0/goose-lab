goose_lab_program(document_profile tools/experiments/document_profile.goose MODULE_DIRS "${GOOSE_LAB_SOURCE_DIR}/tools")
if(GOOSE_LAB_BUILD_TESTS)
  add_test(NAME document_experiment_smoke COMMAND "${Python3_EXECUTABLE}"
    "${GOOSE_LAB_SOURCE_DIR}/tests/document_experiment_fixture.py"
    "${GOOSE_LAB_SOURCE_DIR}/tools/document_experiment.py" "${CMAKE_CURRENT_BINARY_DIR}" "$<CONFIG>")
endif()
if(GOOSE_LAB_GUI)
  goose_lab_gui_program(ui_profile tools/ui/profile.goose LIBRARIES goose_lab_watch MODULE_DIRS "${GOOSE_LAB_SOURCE_DIR}/samples")
endif()
