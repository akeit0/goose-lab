# Component Gallery

Try reusable controls and Clay layout without an application domain model.
The gallery demonstrates buttons, toggles, state changes, panels and responsive
layout; it is the smallest GUI entry point to read first.

From the repository root, after [configuring the build](../../README.md#build):

```text
cmake --build build --config Release --target component_gallery --parallel
python tools/run.py component_gallery
python tools/run.py component_gallery --width 560 --height 860 --headless --frames 3 --screenshot build/gallery.png
```

Resize the window, change tabs/toggles and use Create/Reset to exercise state.
`--scale` changes logical scaling and `--font PATH` selects the base font.
Headless captures still require a GPU/backend. Windows is tested; Linux/macOS
still need validation. Python is only an optional launcher.

Read [main.goose](main.goose), then the [UI composition guide](../../docs/ui/ui-composition.md).
