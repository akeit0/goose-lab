goose_lab_native_library(goose_lab_http HTTP
  SOURCES http/http.c LIBRARIES goose_lab_cancel PRIVATE_LIBRARIES CURL::libcurl)
