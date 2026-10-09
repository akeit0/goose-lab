# Application defaults only; libraries also accept explicit font paths.
# Select installed fonts without imposing one OS's directory layout. Explicit
# GOOSE_LAB_* paths always take precedence, including for cross compilation.
if(WIN32)
  set(default_font "$ENV{SystemRoot}/Fonts/segoeui.ttf")
  set(default_mono "$ENV{SystemRoot}/Fonts/consola.ttf")
elseif(APPLE)
  set(default_font "/System/Library/Fonts/Supplemental/Arial.ttf")
  set(default_mono "/System/Library/Fonts/Menlo.ttc")
else()
  find_file(default_font NAMES DejaVuSans.ttf LiberationSans-Regular.ttf NotoSans-Regular.ttf
    PATHS /usr/share/fonts /usr/local/share/fonts
    PATH_SUFFIXES truetype/dejavu dejavu truetype/liberation2 truetype/liberation liberation-sans truetype/noto noto NO_DEFAULT_PATH)
  find_file(default_mono NAMES DejaVuSansMono.ttf LiberationMono-Regular.ttf NotoSansMono-Regular.ttf
    PATHS /usr/share/fonts /usr/local/share/fonts
    PATH_SUFFIXES truetype/dejavu dejavu truetype/liberation2 truetype/liberation liberation-mono truetype/noto noto NO_DEFAULT_PATH)
endif()
set(GOOSE_LAB_FONT_PATH "${default_font}" CACHE FILEPATH "Font for modern UI samples")
set(GOOSE_LAB_MONO_PATH "${default_mono}" CACHE FILEPATH "Monospaced font for code views")
foreach(required GOOSE_LAB_FONT_PATH GOOSE_LAB_MONO_PATH)
  if(NOT CMAKE_CROSSCOMPILING AND (GOOSE_LAB_BUILD_SAMPLES OR GOOSE_LAB_BUILD_TESTS OR GOOSE_LAB_BUILD_TOOLS) AND NOT EXISTS "${${required}}")
    message(FATAL_ERROR "Set ${required} to an installed font file (TrueType/OpenType/TTC). Automatic font lookup found no usable path.")
  endif()
endforeach()
set(default_fallback "")
if(WIN32 AND EXISTS "$ENV{SystemRoot}/Fonts/YuGothM.ttc")
  set(default_fallback "$ENV{SystemRoot}/Fonts/YuGothM.ttc")
endif()
set(GOOSE_LAB_FALLBACK_PATH "${default_fallback}" CACHE FILEPATH "Optional Japanese fallback font for modern UI samples")
set(default_symbols "")
if(WIN32 AND EXISTS "$ENV{SystemRoot}/Fonts/seguisym.ttf")
  set(default_symbols "$ENV{SystemRoot}/Fonts/seguisym.ttf")
endif()
set(GOOSE_LAB_SYMBOL_PATH "${default_symbols}" CACHE FILEPATH "Optional text presentation symbol fallback")
set(default_emoji "")
if(WIN32 AND EXISTS "$ENV{SystemRoot}/Fonts/seguiemj.ttf")
  set(default_emoji "$ENV{SystemRoot}/Fonts/seguiemj.ttf")
endif()
set(GOOSE_LAB_EMOJI_PATH "${default_emoji}" CACHE FILEPATH "Optional emoji presentation font (COLR v0 or supported bitmap format)")
