# Indexed byte buffers in Goose

`import lab.buffer.indexed;` uses namespace `lab_buffer_indexed`. This experimental
library provides independently lived byte buffers without a native allocator or
module-global resource. Each caller owns a `Store` with a single grow-only byte
arena, fixed chunk directories and a library freelist. Different Stores are
independent. The module imports only `std`.

```goose
import lab.buffer.indexed;
fn main() {
    var store = lab_buffer_indexed::create();
    assert(store.code == lab_buffer_indexed::OK);
    let a, code = lab_buffer_indexed::open(store);
    assert(code == lab_buffer_indexed::OK);
    assert(lab_buffer_indexed::append(store, a, "hello") == lab_buffer_indexed::OK);
    let bytes, read_code = lab_buffer_indexed::read(store, a, 0, 5);
    assert(read_code == lab_buffer_indexed::OK && bytes == "hello");
    assert(lab_buffer_indexed::close(store, a) == lab_buffer_indexed::OK);
}
```

## Ownership and API

Treat Store fields as implementation state and use its functions. A Store is a
resizable owner, passed by reference; it cannot be embedded in a fixed-size array
of owners. IDs belong to that Store's lifetime and must be used with the same
Store. They are not process-wide IDs or proof of cross-Store identity. Copies of
an ID alias one buffer. Closing it makes every copy stale; reopening a slot uses
a new generation. A slot whose generation would wrap is retired.

The API returns bytes or fresh owned arrays, never references/slices into the
arena. A previously exported owned array survives close/reuse and can be changed
independently. Queue consumers must route IDs to the correct owner; an ID alone
does not transfer storage to another worker. `close_all` closes buffers, retaining
arena/metadata for reuse. The Store's lexical lifetime owns the arena.

| Operation | Contract |
| --- | --- |
| `create(Limits)` | Check `store.code`; validate every bound before use |
| `open(store)` | Return `Id, code`; opening an empty buffer allocates no payload |
| `valid`, `size`, `capacity` | `size`/`capacity` return `-1` for a stale ID |
| `append`, `append_fill` | Validate the whole request and chunk quota before changing bytes or counters |
| `read_at(store, id, offset)` | Return `u8, code`; one chunk-directory lookup per successful read |
| `read(store, id, start, end)` | Return fresh owned bytes and code; end is exclusive |
| `write` | Overwrite an existing range without changing length; crossing chunk boundaries is supported |
| `truncate` | Shrink only; release complete trailing chunks and clear the retained chunk's spare bytes |
| `close`, `close_all` | Return chunks to the Store's freelist; survivors retain their bytes |
| `stats` | Logical/capacity/high-water bytes, chunk and operation counters, reserved metadata entry counts |

`OK`, `INVALID`, `LIMIT` and `STALE` distinguish success, invalid bounds/arguments,
quota refusal and unknown/closed generations. A quota refusal leaves the entire
buffer and allocation/write counters unchanged. This is a bounded library
contract; a runtime/OS allocation failure can still abort.

## Representation costs

Limits are at most 64 buffers, 512 chunk indices per buffer, 4,096 chunks total,
2 MiB logical bytes per buffer and a 128 MiB payload arena. Chunk size is
configurable from 1 to 65,536 bytes. The byte limit must also fit 512 chunks;
when selecting small chunks, lower `Limits.bytes` accordingly. Defaults use
4,096-byte chunks and a 16 MiB maximum arena. Unused chunks are reused before
arena growth; growth and reuse never relocate previously stored payload.

The fixed metadata reserves 32,768 directory entries and 4,096 freelist entries,
all `i32`: 147,456 raw entry bytes per Store, even for one empty buffer. This
excludes buffer fields, array length headers and native padding. `capacity` counts
live payload chunks, `high_water` counts retained arena bytes, and `peak_chunks`
counts maximum live chunk slots; none includes that fixed metadata. Retained
arena/free slots are not evidence of memory returned to the OS.

The generated C layout on Windows x64/MSVC has `sizeof(Store) == 148861`,
including scalar fields, array lengths and the 16-byte tail header. The tail
header starts at byte 148845; the buffers and freelist fields occupy 132289 and
16384 bytes respectively. Goose's generated layout is packed. This is the fixed
representation size, not runtime allocation granularity, committed pages or RSS.
The qualification runner measures it for each optimization level instead of
assuming that raw directory entry bytes are the whole Store cost.

Appending, overwriting and exporting a range walk chunk spans; they do not scan
a chain from its start for every byte. Scalar reads index directly. Owned export
still copies every returned byte. The library has no insert/delete splice,
UTF-8 policy, persistent sharing, Undo/Redo or saved baseline; these belong above
byte storage. A pooled Piece Tree remains a separate representation experiment.

The explicit owner avoids leaking runtime pool names through APIs, but requires
a library freelist: Goose's pool references cannot be retained as struct fields.
It deliberately compares this alternative to the existing `reusable[]` prototype
instead of introducing a language or allocator change.

## Validation

The [contract](../../tests/indexed_buffer_contract.goose) compares 900 deterministic
append/multi-byte-write/truncate/close/reopen/refusal operations at each of 3/16/64
buffers against independent flat arrays. It checks boundary-crossing payloads,
stale IDs, owned exports, two independent Stores and whole-request refusal with
all mutable counters unchanged. Periodic accounting checks derive logical bytes,
live chunks and capacity from the flat arrays. It opens all 64 IDs and fills eight
buffers to their 512-entry/2 MiB limits, exhausting all 4096 default chunks. Sixty-four
non-LIFO close/reopen and truncate/refill cycles preserve the 16 MiB high-water,
survivors and a previously exported 2 MiB copy. The contract runs in the main
core/GUI configurations; their registered check counts are unchanged.

For longer qualification, use the same compatible fork once:

```text
python tools/indexed_buffer_qualification.py --build build --output local/references/indexed-buffer/boundary-library-run
```

The [runner](../../tools/indexed_buffer_qualification.py) builds source snapshots
at Goose `-O0/-O1/-O2`, keeping native C optimization at level 2. Each level runs
three seeds with 30000 operations per buffer count: 810000 model operations total.
It independently calculates expected close/reopen and refusal counts in Python.
All nine Windows/MSVC runs passed, including the maximum-capacity test in each
process. The ignored record above includes revisions/diffs, source snapshots and
hashes, compiler/binary hashes, raw output, operation coverage and generated
layout measurements. Failure leaves an incomplete manifest and logs; existing
output directories are refused. `--rounds`, repeated `--seed` and `--level` allow
focused reproductions. This is bounded operation-count qualification, not a claim
about hours of uptime or OS memory stability.

The [storage experiment](../experiments/buffer-storage.md) compares the library
with geometric runs and linked pool chunks on equal append/read/lifetime traces.
Its independent Python oracle checks every row, including chunk counts and
directory visits. Distinct timing operations prevent library append time from
being mislabeled as a native allocator measurement.
