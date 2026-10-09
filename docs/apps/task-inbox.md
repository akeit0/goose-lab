# Task Inbox

Task Inbox creates and renames tasks, tracks completion, filters/searches,
deletes, undoes changes and restores records after restarting. It uses the
Clay/Goose renderer and local persistence.

## Run

```text
cmake --build build --target task_inbox --config Release --parallel
python tools/run.py task_inbox
```

The default file is `task-inbox.gxt` in the working directory. It starts
empty, and creates the file on the first successful task mutation. Use
`--data path/to/inbox.gxt` to select another location. Parent directories
must exist. A missing file means a new inbox; an unreadable, corrupt, or
unsupported file blocks mutations and is never automatically replaced.

For an isolated demonstration with three initial tasks:

```text
python tools/run.py task_inbox --demo --data build/task-demo.gxt
python tools/run.py task_inbox --headless --frames 3 --demo --data build/task-demo.gxt --screenshot build/task-inbox.png
python tools/run.py task_inbox --width 560 --height 860 --data build/task-demo.gxt
```

`--demo` seeds only a new, missing document. It does not add tasks to an
existing inbox. Font and scale options match the component gallery:
`--font path.ttf`, `--scale 1.25`. Escape cancels an edit, or closes the app.

Enter submits a task. Edit loads its title into the composer; Save task
renames it, and Cancel discards the draft. The checkbox changes completion;
the × button deletes. Undo restores the previous document state. The three
filters and search derive a list without changing stored records. Search
folds ASCII case; non-ASCII text matches exactly. Search, drafts, filters,
scroll positions and undo history are transient; task records persist.

## Implementation

| Module | Contract and use |
| --- | --- |
| `lab.text.strings` | Strict single-line UTF-8 validation, scalar boundaries, ASCII-folded search |
| `lab.fs.storage` | Bounded reads, a versioned/checksummed document envelope, atomic writes and distinct errors |
| `task_inbox.model` | Pure commands, validation, stable IDs, bounded snapshots, encode/decode and derived views |
| `lab.ui.controls.field` | Caller-owned draft state, ordered event routing, clipboard, selection, caret and submit snapshots |
| `lab.ui.layout.scroll` | Clamped offsets and scrollbar geometry derived from viewport/content sizes |
| `lab.ui.view` | Shared component descriptions, ordered actions, clipping, field identity and final focus reconciliation |
| `task_inbox.inbox` | The application controller and UI assembly, kept separate from reusable domain/storage code |

`lab_ui_render_scene::stroke` draws small vector marks, including the checkbox tick,
without depending on a particular font's symbol coverage.

## Model and failure handling

Commands validate before recording Undo or mutating the model. Field drafts,
selection and scroll positions are transient. Task IDs survive filtering and
Undo; Undo preserves the highest allocated ID counter so later additions do not
reuse a removed task's identity during the session.

Successful mutations stay in memory if saving fails; the UI exposes Retry save.
A failed load blocks mutations and offers Retry load. Decode into a temporary
store and adopt only after every field and exact payload length passes. Invalid
UTF-8, duplicate IDs, flags/counters, trailing bytes and capacity violations are
rejected. Atomic replacement prevents partial snapshots; it does not provide
multi-process conflict detection.

## Storage and limits

The envelope is independent of Goose's memory layout: 8-byte application tag,
little-endian `u16` version, `u16` reserved flags, `u32` payload length,
`u32` CRC-32, then the payload. Task payload version 1 stores `next_id:u32`,
`count:u16`, then records of `id:u32`, completion byte, title byte length
`u16`, and UTF-8 bytes. Changing a struct's generated C name or padding does
not change this format. CRC detects accidental corruption, not malicious edits.

Reads are capped at 64 KiB before whole-file allocation, using a small native
file bridge with UTF-8 Windows paths. Writes use the fork's existing
`write_file_atomic` operation. The application allows 128 tasks, titles of
240 UTF-8 bytes, and 16 in-memory undo snapshots. Undo ends at process exit.
The field holds 512 bytes, defaults to a 240-byte editing limit, and records
at most 16 submits per frame. Clipboard input is bounded and validated.

The shared field supports [grapheme editing](../ui/text-foundation.md) and
[IME](../ui/ime.md) with LTR geometry. Paragraph bidi and multiline field editing
are unsupported. Files are small and saved synchronously after commands.
There is no file locking, conflict detection, background save queue or Redo.

## List interaction

Controls use [shared UI composition](../ui/ui-composition.md). The application declares
content height and stable identity, then describes only visible uniform rows.
Clipping, painting and hit testing share the resulting scroll translation.

Click a row or Tab into the list, then use arrows, Home/End or Page Up/Down to
select across visible and unrendered rows. Enter/Space opens editing. Selection
stores the task's stable ID; the list receives its filtered index. Selection
does not create Undo or save operations. Completion, Edit and Delete controls
also work by pointer. The scrollbar supports dragging and track paging,
preserves field focus and cancels on Escape or focus loss.

See [validation](../validation.md) for model, persistence and interaction checks.
