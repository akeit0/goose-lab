# Samples

Small applications for trying Goose and the goose-lab libraries. Start with
[Workbench](workbench/README.md) for editing, project search and Git in one window.
These are experimental applications; they are also examples of explicit resource
ownership and asynchronous library usage.

## Build and run

Run commands from the repository root. Configure the compatible Goose checkout
first; see the [root build guide](../README.md#build) and
[toolchain requirements](../docs/toolchain.md).

```text
cmake --build build --config Release --target workbench --parallel
python tools/run.py workbench --root . --file README.md
```

The same launcher works with single- and multi-configuration CMake builds and
platform executable suffixes. Use `python3` if that is your Python 3 command.
Launcher options precede the target, for example:

```text
python tools/run.py --build build/gui --configuration Release workbench --root .
```

Python is optional for launching; the built applications can run directly.
Windows is currently tested. Linux/macOS need native validation; the build and
commands are intended to work without PowerShell. GUI samples require the Goose
SDL submodule and available fonts; non-Windows HTTPS also needs OpenSSL development
files. Build samples without contract tests with `-DGOOSE_LAB_BUILD_TESTS=OFF`.

## Choose a sample

| Sample | What to try | Guide |
| --- | --- | --- |
| Workbench | File tree, tabs, editing/IME/Undo, project search, Git diffs/history | [README](workbench/README.md) |
| API Browser | HTTP requests, asynchronous results, JSON records and explicit snapshot saving | [README](api_browser/README.md) |
| Task Inbox | Editable records, persistent storage and failed-save recovery | [README](task_inbox/README.md) |
| Component Gallery | Controls, state changes and responsive Clay layout | [README](component_gallery/README.md) |
| Arena | Authoritative ECS game server, CLI peers and optional graphics | [README](arena/README.md) |
| CLI samples | HTTP, process streams, files, JSON, Git and search without a GUI | [README](cli/README.md) |
| Data | Unicode/emoji input for the editor | [emoji.txt](data/emoji.txt) |

Build another application by substituting its target name in the build command.
The separate editor, workspace and Git launchers are consolidated into Workbench.
Component regression entry points live under `tests/support`. Scrolling stress
cases belong to tests; manual profiling belongs to `tools/ui` and is built with
`-DGOOSE_LAB_BUILD_TOOLS=ON`.

## Code boundaries

Each application directory owns its entry point, model and controller. Add `samples` as
a module root when importing these application modules; it is not a library root.
Libraries live under `lib/lab` and native adapters under `native`. Application
navigation, screen composition and task/API domain models stay in their sample.
See the [library map](../docs/libraries.md) for reusable APIs.
