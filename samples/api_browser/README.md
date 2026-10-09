# API Browser

Try HTTP(S), asynchronous request results, editable JSON records and saved
snapshots. The UI can inspect the original response separately from the records.

From the repository root, after [configuring the build](../../README.md#build):

```text
cmake --build build --config Release --target api_browser --parallel
python tools/run.py api_browser --no-data
python tools/run.py api_browser --data build/api-browser.json
```

Enter an endpoint with the supported JSON record shape, then choose **Fetch**.
Requests can be cancelled. **Save** explicitly writes the snapshot; edits and
closing the window do not save automatically. A missing snapshot starts normally;
failed loads/saves and external replacements have recovery actions in the UI.
`--no-data` disables persistence. `--url URL` sets the URL and `--fetch` starts
its request at launch. Application shortcuts use Ctrl on Windows/Linux or Cmd on
macOS; **Commands** lists the currently available actions and bindings.

Use `--headless --frames 3 --screenshot build/api-browser.png` for a finite GPU
capture. Windows is tested; Linux/macOS still need validation. Python is only
an optional launcher. See the [application guide](../../docs/apps/api-browser.md)
for the JSON shape, storage behavior, bounds and source structure.
