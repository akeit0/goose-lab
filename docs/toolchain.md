# Goose toolchain requirements

Goose is maintained outside this repository. `GOOSE_SOURCE_DIR` must explicitly
name a compatible source checkout; a sibling directory or personal home path is
never inferred. Initialize its SDL submodule for GUI builds.

Routine validation uses one upstream-tracking compatible checkout of
[akeit0/goose, branch lab-toolchain](https://github.com/akeit0/goose/tree/lab-toolchain).
The validated published revision is `c2ecb4421facdc6476214606b67488df93eaa033`,
which merges upstream `ac77e1616542da1dcb3ebf54b1f43d9b32b6369c`, including
the merged implicit inline-return correction and subsequent compiler/runtime
improvements. The synchronization merge is `3e00736`.
Windows/MSVC Release passed the 26 main checks, five pool/storage checks and
15 focused return executions at Goose `-O0/-O1/-O2`.

The synchronization is pushed to `lab-toolchain`.
[Upstream PR #11](https://github.com/aardappel/goose/pull/11) was merged as
`e7792d7`; its correction and regression now come directly from upstream.
The typechecker, optimizer, inline-return code and slice-pool runtime have no
remaining fork differences. Module search, native adapter guards and opt-in gfx
integration remain the compatibility extensions. The fork's
[capability guide](https://github.com/akeit0/goose/blob/c2ecb4421facdc6476214606b67488df93eaa033/docs/fork.md)
describes its integration extensions.

Select the validated checkout explicitly:

```text
git clone --branch lab-toolchain --recurse-submodules git@github.com:akeit0/goose.git /path/to/goose
git -C /path/to/goose checkout c2ecb4421facdc6476214606b67488df93eaa033
cmake -S . -B build -DGOOSE_SOURCE_DIR=/path/to/goose
```

Merge upstream before qualifying the next baseline and review the remaining fork
delta for effects on the experiment. Keep its compiler, stdlib and native libraries
together. Run a second upstream checkout only for a focused reproduction of a
relevant difference; repeating identical suites on two checkouts is not routine work.

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
