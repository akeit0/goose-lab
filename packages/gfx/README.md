# Lab graphics package

This directory is ordinary goose-lab source derived from aardappel/goose_gfx
revision `6cfa3dec2ef2a6cb19ee71548b38151094e947bd` (2026-10-11 import).
The source and the Goose API are edited directly here. There is no goose_gfx
submodule and no patch applied by the build. Original Apache-2.0 notices remain.

`gfx.goose`, `audio.goose` and `gfx.build` form a Goose package.
`src/` supplies the native layers. Lab applications declare this local package
and link its CMake targets; the Goose compiler has no native graphics dependency.
SDL is a pinned lab submodule under `../../third_party/SDL`. The unused upstream
Nuklear UI layer is omitted; lab UI uses Clay, FreeType and HarfBuzz.

Lab additions include on-demand presentation, screen/content revisions, atomic
UTF-8 preedit/commit transactions, deferred close and ordered input injection.
See [toolchain requirements](../../docs/toolchain.md), [IME](../../docs/ui/ime.md)
and [focused regressions](../../tests/gfx). Package updates are source changes
reviewed against upstream; update the recorded source revision when integrating
upstream changes.
