# Tree model and view

`lab.collections.tree` is an owned bounded forest. `lab.ui.views.tree` composes virtual rows on the
shared `lab.ui.view` list protocol. Neither knows Git. `lab.git.tree` adapts changed
file paths into this model and maps leaf data back to the original file index.
The Git viewer shows changed and non-ignored untracked files, not the complete
filesystem. There is no recursive directory enumeration or lazy IO in the tree.

## Model, state and projection

```goose
var model = lab_collections_tree::Tree {};
let source = lab_collections_tree::add(model, "src/", "src", -1, true);
let file = lab_collections_tree::add(model, "src/main", "main.goose", source, false, 42);
assert(model.code == lab_collections_tree::OK && file >= 0);
var state = lab_collections_tree::State { current: "src/main" };
let rows = lab_collections_tree::project(model, state);
```

Nodes own a unique byte key, a single-line UTF-8 label, parent/depth, branch
flag and optional i64 domain data. Parents must already exist and be branches,
which excludes cycles and dangling references. Child/sibling links use indices.
Insertion orders branches before leaves, then labels with ASCII case folding;
ties use the exact key. Non-ASCII bytes retain their ordinal order. Tree keys
need not be paths, labels or hashes; equal basenames in different parents have
different keys. The Git adapter uses full paths, with a trailing `/` for folders.

`State` stores the current row's key and closed branch keys. Branches start open.
Rebuilding a model can change every node index without changing those identities.
Call `prune(new_model, state)` to discard closed keys no longer present, then
`normalize(new_model, state, rows)` to reconcile the current row: a hidden child
falls back to its visible ancestor, a removed key to the first visible row.
The Git app separately retains its selected file and displayed patch, so moving
to or closing a folder does not clear an otherwise valid diff.

`project(model, state)` flattens only expanded branches. To filter, supply a
bool mask with one entry per node. The projection includes matches and all their
ancestors and forces those ancestors open, without changing saved expansion.
An all-false mask returns no rows. If a matching branch's descendants should
also appear, mark those descendants in the consumer's mask. The Git adapter
matches full file paths, not just displayed basenames. Clearing its query
restores the saved expansion. A new selected file follows visible tree order.

Traversal uses parent/sibling indices rather than recursive calls. The model
is built on refresh; a projection is transient, owned metadata for a frame.
No callback, slice into a temporary, OS handle or worker reference is stored.

## Shared UI composition and behavior

After solving layout, call `lab_ui_views_tree::at_tree(view, bounds, config, model,
state, rows) { node, row, rect => ... }`. The block is invoked immediately for
each rendered row to add domain decorations, such as the Git status column.
`Config.trailing` reserves width for them. Labels align left with depth-based
indentation; Git status letters align right. `at_tree` uses the same clipped,
translated viewport for drawing and hit testing, and describes only visible
rows plus a small overscan. All projected rows remain keyboard navigable.
Tree rows have no border, rounding or inter-row gaps; selection and hover use
a flat background. The disclosure chevron uses geometry, so missing font glyphs
do not affect it.

Choose distinct nonzero list/scroll IDs and a `row_base` range large enough for
all 2,048 node indices and disjoint from other interactive IDs. The Git viewer
uses 50,000, beyond its code-row identities. Its default row stride is 28 pixels.

Pass tree events to `lab_ui_views_tree::reduce(model, state, rows, event)`. It changes
only tree state and returns the current leaf's domain data (`-1` for a branch),
which the application can use to select a file. It never starts processes or
edits application data. Reproject after an expansion change; use `reveal` with
the fresh rows to scroll the current key into view for keyboard events.

| Input | Behavior |
| --- | --- |
| Click folder row | Select and toggle its expansion |
| Click file row | Select the file |
| Up/Down, Home/End, Page Up/Down | Navigate projected rows and reveal selection |
| Right | Open a closed branch; otherwise move to its first visible child |
| Left | Close an open branch; otherwise move to its parent |
| Enter/Space | Toggle a branch or activate the current leaf |

While filtering, expansion is forced by the projection and toggles are ignored;
Left/Right still move between included parents and children. Refresh retains
the current file, surviving folder keys and tree scroll offset in the same
repository/mode. Changing repository resets tree state. Changing Working/Staged
mode prunes keys absent from that mode and resets scroll; switching modes is
not a separate saved view. Failed refreshes retain the previous model/state.

`lab.ui.view` adds opt-in `ListConfig.hierarchical` and `EXPAND`/`COLLAPSE` events.
Regular lists keep their existing keyboard behavior. Pointer selection is
identified in the owned event, so a key selection never toggles a folder.
Composition, input routing, tree state reduction and application actions remain
separate immediately invoked operations.

## Bounds

The model holds up to 2,048 nodes, including branches; keys/labels hold up to
512 bytes and depths run from 0 through 32. A failed builder has `code != OK`
and must not be adopted. The Git adapter returns an empty error model on failure
and the app keeps its last successful collection. Its independent 512-file and
diff/process bounds still apply. Fixed metadata arrays make memory use bounded,
but reserve several MiB regardless of node count. Lookup and sibling insertion
are linear; large sustained workloads have not been profiled. Deep indentation
and long labels clip to the available width; horizontal tree scrolling,
multiple selection, drag/drop, node editing and accessibility are not implemented.

See [validation](../validation.md) for model, expansion and input checks.
