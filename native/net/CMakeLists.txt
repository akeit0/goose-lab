goose_lab_native_library(goose_lab_http HTTP
  SOURCES http/http.c LIBRARIES goose_lab_cancel PRIVATE_LIBRARIES CURL::libcurl)
goose_lab_native_library(goose_lab_tcp TCP SOURCES tcp/tcp.c)
if(WIN32)
  target_link_libraries(goose_lab_tcp PRIVATE ws2_32)
endif()
