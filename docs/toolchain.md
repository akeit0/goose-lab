# Goose toolchain requirements

`GOOSE_SOURCE_DIR` explicitly names the compatible compiler source checkout.
Routine validation uses one upstream-tracking [akeit0/goose lab-toolchain branch](https://github.com/akeit0/goose/tree/lab-toolchain),
validated at `71e848d732362a47ee7fe000a3e1601d0196259a`, synchronized with
upstream `4f23f22629a34d971adbd8c10017d203ab6bb2fa`. TinyCC is vendored and always built;
the compiler has no SDL dependency and builds with `GOOSE_BUILTIN_LIBS` empty.
The typechecker, optimizer and slice-pool runtime are upstream code. The implicit
inline-return correction from PR #11 is already upstream.

The remaining integration differences are ordered/repeated `--module-dir`,
guarded C slice declarations and package CMake paths for `add_subdirectory`
consumers, plus Visual Studio test-tooling discovery that reuses an existing
vcvars environment. The CMake correction resolves compiler-owned inputs relative to the compiler's
CMake module rather than the parent project's source directory.

```text
git clone --branch lab-toolchain git@github.com:akeit0/goose.git /path/to/goose
git submodule update --init --recursive
cmake -S . -B build -DGOOSE_SOURCE_DIR=/path/to/goose
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```

CMake 3.27+ is required by the upstream compiler. A second upstream checkout is
used only for a focused reproduction of a relevant fork difference, rather than
repeating the same suite on two compilers.

## Application graphics package

[packages/gfx](../packages/gfx) contains ordinary lab source derived from
[aardappel/goose_gfx](https://github.com/aardappel/goose_gfx) revision
`6cfa3dec2ef2a6cb19ee71548b38151094e947bd`. Lab input/presentation extensions
are implemented directly in these files. The package is not a submodule; the
build performs no patching or package-source copying.

SDL remains a pinned external dependency at `third_party/SDL`. The unused
upstream Nuklear UI layer is omitted; lab UI uses Clay and the lab text libraries. Core builds (`GOOSE_LAB_GUI=OFF`) do not configure or link
the graphics package. [GooseGfx.cmake](../cmake/GooseGfx.cmake) configures its native
targets only for GUI builds. Generated GUI roots declare the local package using
upstream `import gfx from "path"` syntax; applications link its matching
`goose_gfx` archive. The optional audio target stays excluded from the normal lab
build. The compiler itself links none of these targets.

The directly maintained package preserves existing lab features:

| Scope | Contract |
| --- | --- |
| Rendering | On-demand presentation, screen/content revisions and idle submission accounting |
| Text input | Atomic UTF-8 commit/preedit events, frame-local payload tokens and caret-area reporting |
| Lifecycle | Deferred close requests for save/discard/cancel |
| Fixtures | Ordered wheel, preedit and close injection through the event queue |

Token payloads must be copied before the next frame or close. Native code retains
no Goose references. The event representation is extended, so generated Goose C
and the native graphics archive must both be rebuilt when changing the package.
[Focused gfx contracts](../tests/gfx) now live in lab, alongside application tests.
GPU-backed checks use headless windows; native IME candidate placement and OS
expose/resize behavior still require manual window checks.

## Capability checks

The build runs core/GUI compile probes before generating applications. Text/UI
adapters require guarded `sl_f32` / `sl_u32` declarations; ordinary core programs
need only the module-root extension. Existing upstream `--stdlib`, `--standalone`
and `--include` options remain unchanged. Capability checks use compiler behavior,
not repository identity. See [validation](validation.md) and [libraries](libraries.md).
