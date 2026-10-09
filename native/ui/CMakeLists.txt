include("${GOOSE_LAB_SOURCE_DIR}/cmake/Fonts.cmake")

goose_lab_native_library(goose_lab_text TEXT
  SOURCES text/text.c PRIVATE_LIBRARIES freetype harfbuzz)
target_compile_definitions(goose_lab_text INTERFACE
  GOOSE_LAB_FONT_PATH="${GOOSE_LAB_FONT_PATH}"
  GOOSE_LAB_MONO_PATH="${GOOSE_LAB_MONO_PATH}"
  GOOSE_LAB_FALLBACK_PATH="${GOOSE_LAB_FALLBACK_PATH}"
  GOOSE_LAB_SYMBOL_PATH="${GOOSE_LAB_SYMBOL_PATH}"
  GOOSE_LAB_EMOJI_PATH="${GOOSE_LAB_EMOJI_PATH}")

# Byte comparison/cache storage is independent of font rasterization and SDL.
goose_lab_native_library(goose_lab_scene SCENE SOURCES scene/scene.c)
goose_lab_native_library(goose_lab_layout LAYOUT
  SOURCES layout/layout.c LIBRARIES goose_lab_text)
target_include_directories(goose_lab_layout PRIVATE "${GOOSE_LAB_SOURCE_DIR}/third_party/clay")
