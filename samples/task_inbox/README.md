# Task Inbox

A small record application for trying editable lists, commands, persistence and
save-failure recovery.

From the repository root, after [configuring the build](../../README.md#build):

```text
cmake --build build --config Release --target task_inbox --parallel
python tools/run.py task_inbox --demo --data build/task-demo.gxt
```

Create/edit tasks, toggle completion, filter and use Undo. Successful
mutations are saved; failed saves retain the edited state and offer Retry save.
`--demo` seeds three tasks only when the selected data file is missing.
`--data PATH` chooses a journal file whose parent directory already exists.

Use `--headless --frames 3 --screenshot build/task-inbox.png` for a finite GPU
capture. Windows is tested; Linux/macOS still need validation. Python is only
an optional launcher. See the [application guide](../../docs/apps/task-inbox.md)
for the journal format, recovery behavior, limits and source structure.
