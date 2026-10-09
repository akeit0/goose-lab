# Local development and references

Tracked files describe reusable libraries, samples and reproducible checks.
Personal checkout/font paths and detailed local investigation logs belong outside
that public surface.

- `CMakeUserPresets.json` is ignored. Use it to inherit `gui` or `core` from
  `CMakePresets.json` and set `GOOSE_SOURCE_DIR` and optional font paths.
- `local/` is ignored. `local/references/` holds archived development notes and
  measured results from this checkout; keep new local investigation logs there.
- `build*/` and generated screenshots are ignored. Keep fetched reference fonts
  and their attribution beside each other in an ignored build directory.
- Goose source remains a separately configured repository. Its personal path
  does not belong in tracked build files or library imports.

Example user preset (replace the paths for your machine):

```json
{
  "version": 3,
  "configurePresets": [
    {
      "name": "local",
      "inherits": "gui",
      "cacheVariables": {"GOOSE_SOURCE_DIR": "/path/to/compatible/goose"}
    }
  ]
}
```

Run `cmake --preset local`, then build/test the preset's directory. Public guides
must stay usable without the contents of `local/` or any user preset.

## Portability

PowerShell is not a build/runtime dependency. `tools/run.py` and `tools/profile.py`
use Python stdlib and accept both CMake executable layouts. Keep platform details
in native backends and optional OS diagnostics, rather than Goose application
flows. Processes/files have Windows and POSIX implementations; event-driven I/O
uses libuv; UI uses SDL, FreeType and HarfBuzz. Non-Windows curl uses OpenSSL.

Installed font defaults are selected at configure time and can be overridden.
A headless GPU test still needs a graphics backend and fonts covering the tested
text. Only Windows has been exercised here; candidate macOS/Linux defaults and
source backends are not evidence of successful builds on those systems.
