# Samples

Build only samples with `-DGOOSE_LAB_BUILD_TESTS=OFF`. Each GUI application has
its entry point, model and controller in its own directory. Add `samples` as a
module root when importing those application modules; it is never a library root.

| Directory | Application | Purpose |
| --- | --- | --- |
| `workbench/` | `workbench` | Editable document, explorer, file search, Git changes and history in one window |
| `api_browser/` | `api_browser` | HTTP requests, asynchronous results and JSON snapshot editing |
| `task_inbox/` | `task_inbox` | Small persistent record application with recoverable storage failures |
| `component_gallery/` | `component_gallery` | Reference for reusable UI controls and responsive layout |
| `cli/` | Seven small commands | Direct HTTP, process, file, JSON, Git object/history and search usage without UI |
| `data/` | Text fixtures | Unicode and emoji input for the editor |

The separate editor, workspace and Git launchers were consolidated into
`workbench`. Component regression entry points live under `tests/support`.
Scrolling stress cases belong to tests; profiling belongs to `tools/ui` and is
built with `-DGOOSE_LAB_BUILD_TOOLS=ON`.

Libraries live under `lib/lab`, native adapters under `native`. Application
navigation, screen composition and task/API domain models stay here.
