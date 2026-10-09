# Goose toolchain requirements

Goose is maintained outside this repository. `GOOSE_SOURCE_DIR` must explicitly
name a compatible source checkout; a sibling directory or personal home path is
never inferred. Initialize its SDL submodule for GUI builds.

Use [akeit0/goose, branch lab-toolchain](https://github.com/akeit0/goose/tree/lab-toolchain),
revision `a6e8543a1017724d8da784585927264f9e324aa2`. This revision is published.
The fork's [capability guide](https://github.com/akeit0/goose/blob/a6e8543a1017724d8da784585927264f9e324aa2/docs/fork.md)
describes its separate feature commits and checks.

```text
git clone --branch lab-toolchain --recurse-submodules git@github.com:akeit0/goose.git /path/to/goose
git -C /path/to/goose checkout a6e8543a1017724d8da784585927264f9e324aa2
cmake -S . -B build -DGOOSE_SOURCE_DIR=/path/to/goose
```

## Required capabilities

| Scope | Fork dependency | Why |
| --- | --- | --- |
| Goose programs | Ordered/repeated `--module-dir` | Libraries and sample application modules have separate import roots |
| Text/UI | Guarded `sl_f32` / `sl_u32` declarations | Optional native adapters can supply slice types not emitted by reachable Goose code without conflicting with emitted types |
| UI rendering | On-demand presentation and screen/content revisions | Idle scenes skip GPU work and external screen writers invalidate cached scenes |
| UI input | Atomic UTF-8 commit/preedit events and caret-area reporting | IME stays transient until an accepted commit; candidate placement follows the caret |
| Editor lifecycle | Deferred native close requests | Save/discard/cancel can finish before the app exits |
| Interaction fixtures | Ordered wheel/preedit/close injection | Tests use the platform event queue without operating OS input dialogs |

`--stdlib`, `--standalone` and `--include` already exist upstream. The build supplies
stdlib explicitly and does not depend on fork-specific automatic discovery.

Core programs do not require gfx extensions or text-adapter guards. Native C-only
consumers do not use the Goose generation step. The current upstream checkout is
not compatible with this build's module roots; GUI use additionally needs the
capabilities above. See the [library map](libraries.md) for native dependencies.

The build runs compile-only core/GUI probes before application generation and
reports missing capabilities with compiler diagnostics. It checks capabilities,
not the repository URL or an exact Git revision, so a future compatible upstream
checkout can be selected through the same `GOOSE_SOURCE_DIR` setting.

The current CMake integration builds the compiler and selected native Goose
libraries from that source checkout. The application helper always supplies the
stdlib and module roots explicitly.

Keep fork development/review notes in ignored local references. Public API and
lifetime contracts belong in the library guides. See [local development](local-development.md).
