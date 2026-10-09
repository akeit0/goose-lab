# goose-lab

A personal experimental playground for libraries and small applications in the
[Goose language](https://github.com/aardappel/goose).
This is a place to try ideas and learn what fits Goose's value semantics,
isolated workers and explicit resource lifetimes. The APIs and examples are
experimental and can change. It currently uses
[akeit0/goose's lab-toolchain branch](https://github.com/akeit0/goose/tree/lab-toolchain);
see [toolchain requirements](docs/toolchain.md) before building.

Development and testing currently focus on Windows. The libraries and build
should remain portable: CMake, native libraries and optional Python tools do not
require PowerShell. Linux and macOS have not yet been validated.
See the [documentation index](docs/README.md) for guides by area.

## What's here

| Library area | Capabilities | Guide |
| --- | --- | --- |
| Core | UTF-8/graphemes, buffers, JSON, paths, trees, state and commands | [Library map](docs/libraries.md) |
| I/O | HTTP(S), cancellation, libuv event loop, processes, stdin/stdout, files, watchers, atomic saves | [I/O foundation](docs/io/io-core.md) |
| Documents | Piece tree, bounded Undo/Redo, editing, shared close decisions, document workspace | [Text editor](docs/apps/text-editor.md) |
| Git/search | Status, diffs, history, batch object reads, file search, lazy file trees | [Git viewer](docs/apps/git-viewer.md) |
| UI | Clay layout, GPU scene, shaped text, color emoji, fields, IME, virtual lists, modals | [UI composition](docs/ui/ui-composition.md) |

Reusable Goose code is grouped under `lib/lab`: `text`, `collections`, `json`,
`io`, `fs`, `net`, `git`, `document` and `ui`. UI has separate layout, input,
render, controls, views and overlays. Import paths mirror files:
`import lab.net.http;` uses namespace `lab_net_http`.

Application entry points, models and controllers are grouped under
`samples/workbench`, `api_browser`, `task_inbox` and `component_gallery`.
Small commands live under `samples/cli`; see the [sample guide](samples/README.md). Native services are grouped under `native/io`, `fs`,
`net` and `ui`; generated C uses `native/goose_lab.h`.
See [the module map](docs/libraries.md) and [architecture](docs/architecture.md).

## Build

Prerequisites: CMake 3.20+, a C/C++ toolchain, Git, and the compatible Goose
source checkout with its SDL submodule initialized for GUI builds. Python 3 is
needed for contract tests. Presets require CMake 3.21+.

```text
git submodule update --init --recursive
cmake -S . -B build -DGOOSE_SOURCE_DIR=/path/to/compatible/goose -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
```

On Windows, use Visual Studio's x64 compiler (for example add
`-G "Visual Studio 17 2022" -A x64` to configure). Multi-configuration executables
are in `build/Release`; single-configuration generators use `build`.

For libraries without the renderer, configure `-DGOOSE_LAB_GUI=OFF` in a
separate build directory. `GOOSE_LAB_BUILD_SAMPLES` and `GOOSE_LAB_BUILD_TESTS`
can independently disable applications and contract tests. Manual profiling tools
are separate and disabled by default (`GOOSE_LAB_BUILD_TOOLS=OFF`). Disabling samples
also omits tests that drive those applications.

You can use `cmake --preset gui -DGOOSE_SOURCE_DIR=/path/to/compatible/goose`,
then `cmake --build --preset gui` and `ctest --preset gui`. Personal source and
font paths belong in ignored `CMakeUserPresets.json`; see
[local development](docs/local-development.md).

## Try the applications

```text
python tools/run.py workbench --root . --file samples/data/emoji.txt
python tools/run.py workbench --root . --git
python tools/run.py api_browser
python tools/run.py task_inbox
python tools/run.py component_gallery
python tools/run.py http_get https://example.com/
```

The optional Python launcher locates single- and multi-configuration CMake
outputs and the platform executable suffix. Use your Python 3 command (`python`
or `python3`). You can also run the built executables directly; the applications
do not require Python. `--build` and `--configuration` must precede the target.

`io_runner`, `files_cli`, `json_cli`, `git_objects`, `git_history` and `find_files`
also exercise the same libraries without a UI. Run them without arguments for usage information. `ui_profile`, built with `-DGOOSE_LAB_BUILD_TOOLS=ON`, measures
scene/cache retention and idle work. The [workbench guide](docs/apps/workbench.md)
describes the integrated editing, search and Git workflow.

Windows uses installed Segoe UI, Consolas and available Japanese/symbol/emoji
fallbacks. Linux probes installed DejaVu/Liberation/Noto fonts; macOS uses installed Arial
and Menlo. Set `GOOSE_LAB_FONT_PATH` and `GOOSE_LAB_MONO_PATH` if lookup fails.
Non-Windows HTTP builds need OpenSSL development files. Optional Japanese, symbol
and compatible emoji fallback fonts can be supplied on every platform.
Fonts are not redistributed. See [color emoji](docs/ui/emoji.md) for an optional,
digest-verified reference font and known format limitations.

## Use from another project

```cmake
set(GOOSE_SOURCE_DIR "/path/to/compatible/goose" CACHE PATH "")
set(GOOSE_LAB_BUILD_SAMPLES OFF CACHE BOOL "")
set(GOOSE_LAB_BUILD_TESTS OFF CACHE BOOL "")
set(GOOSE_LAB_GUI OFF CACHE BOOL "")
add_subdirectory(vendor/goose-lab)
goose_lab_program(my_app main.goose LIBRARIES goose_lab_http)
```

Import `lab.net.http` in `main.goose`. The helper supplies the module search path,
runtime adapter and linked library's feature definitions. HTTP is an explicit
dependency. For a GUI program, enable `GOOSE_LAB_GUI` and use
`goose_lab_gui_program`; add other native dependencies with `LIBRARIES`.
`MODULE_DIRS` adds your own Goose module roots.

The helpers build Goose from the configured source checkout; see
[toolchain requirements](docs/toolchain.md) for required capabilities.

## Dependencies and status

Pinned submodules provide curl, libuv, Clay, FreeType and HarfBuzz. SDL and the
platform `gfx` layer belong to the separately configured Goose toolchain.
See [third-party notices](THIRD_PARTY.md) for licenses and source locations.

Resource cleanup is explicit: copied native handles are borrowed aliases, workers
must finish before their owning context closes, and dependent UI resources must
close before fonts/scenes. The individual guides document ownership and limits.
See [design](docs/design.md), [Goose feedback](docs/goose-feedback.md) and
[validation](docs/validation.md) for the patterns and checks behind these APIs.

Original code is licensed under [Apache-2.0](LICENSE). Dependencies and generated
Unicode data retain their own licenses; see [third-party notices](THIRD_PARTY.md).
