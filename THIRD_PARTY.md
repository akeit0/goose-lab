# Third-party sources and notices

Original project code uses the [Apache-2.0 license](LICENSE)
([reference text](https://www.apache.org/licenses/LICENSE-2.0)). Dependencies and
Unicode data retain their own licenses below.

Dependencies are Git submodules pinned by this repository. Their license files
remain in their source trees; original source notices must be preserved.

| Component | Source | License file |
| --- | --- | --- |
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

Goose and SDL are supplied by the separate toolchain checkout. Their notices
belong to that checkout and remain applicable to built programs.

No system font files are redistributed. The optional Twemoji Mozilla reference
font is fetched into an ignored build directory with its own attribution notice;
see [emoji font sources and licenses](docs/ui/emoji.md).
