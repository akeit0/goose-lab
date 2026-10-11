# Third-party sources and notices

Original project code uses the [Apache-2.0 license](LICENSE)
([reference text](https://www.apache.org/licenses/LICENSE-2.0)). Dependencies and
Unicode data retain their own licenses below.

External dependencies are Git submodules pinned by this repository. Their license files
remain in their source trees; original source notices must be preserved.

| Component | Source | License file |
| --- | --- | --- |
| gfx sources | Derived from [aardappel/goose_gfx](https://github.com/aardappel/goose_gfx) at `6cfa3dec2ef2a6cb19ee71548b38151094e947bd`, with direct lab changes | [LICENSE](packages/gfx/LICENSE), source notices retained |
| SDL | [libsdl-org/SDL](https://github.com/libsdl-org/SDL) | [LICENSE.txt](third_party/SDL/LICENSE.txt) |
| curl | [curl/curl](https://github.com/curl/curl) | [COPYING](third_party/curl/COPYING) |
| libuv | [libuv/libuv](https://github.com/libuv/libuv) | [LICENSE](third_party/libuv/LICENSE), additional notices in that tree |
| Clay | [nicbarker/clay](https://github.com/nicbarker/clay) | [LICENSE.md](third_party/clay/LICENSE.md) |
| FreeType | [freetype/freetype](https://github.com/freetype/freetype) | [LICENSE.TXT](third_party/freetype/LICENSE.TXT), [FreeType License](third_party/freetype/docs/FTL.TXT) |
| HarfBuzz | [harfbuzz/harfbuzz](https://github.com/harfbuzz/harfbuzz) | [COPYING](third_party/harfbuzz/COPYING), per-directory notices |

This software uses the FreeType project to render fonts. FreeType is maintained
by the FreeType authors and contributors. The project selects the FreeType
License option for this dependency; its full notice is in the submodule.

Generated Unicode tables and the grapheme contract corpus derive from Unicode
17.0.0 data, with [Unicode License V3](tools/unicode/LICENSE.txt). The generator
records the pinned input hashes; generated files retain the attribution pointer.

Goose (including its vendored TinyCC and shader compiler) is supplied by the
separate toolchain checkout. Its notices remain applicable to built programs.
Graphics and audio sources live directly in `packages/gfx`, derived from
upstream goose_gfx with lab extensions. They are ordinary lab source, rather than
a submodule or a build-time patch. Upstream license headers are retained.

No system font files are redistributed. The optional Twemoji Mozilla reference
font is fetched into an ignored build directory with its own attribution notice;
see [emoji font sources and licenses](docs/ui/emoji.md).
