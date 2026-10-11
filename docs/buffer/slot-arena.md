# Variable-value slot arena

`import lab.buffer.slot_arena;` uses namespace `lab_buffer_slot_arena`. This pure
Goose library stores bounded variable-length byte values in caller-assigned slots
using one resizable byte tail. It suits short-lived mailboxes, replaceable binary
values and sparse pages whose removal should not move every surviving payload.
It has no native allocator, module-global owner or runtime pool name.

## Ownership and API

The caller owns one Store and the identities/lifetimes of its slots. Slots are
indices in `0..limits.slots`; they always exist and initially contain empty values.
There is no open/close operation or generation in this storage API. The stream
Service supplies generation/serial/receipt checks before accessing its slots.
Use a separate identity layer when callers need stale-handle rejection.

Treat fields and helper functions as implementation state. Do not retain slices
into the arena, copy the owner, or pass its own internal storage back as input.
Borrow input for a synchronous put; retain owned exports across mutation. Two
Stores are independent. A slot index has meaning only with the correct Store.

| Operation | Contract |
| --- | --- |
| `create(Limits)` | Validate bounds; check `store.code` before use |
| `size(store, slot)` | Byte length; `-1` for invalid Store/slot |
| `put(store, slot, bytes)` | Replace the complete value; whole-request preflight before mutation |
| `read(store, slot)` | Fresh owned bytes and code; an empty valid slot succeeds |
| `append_to(store, slot, output)` | Copy into a caller-owned growable output, retaining its existing prefix; invalid input leaves it unchanged |
| `clear(store, slot)` | Empty one slot, trim unused tail, preserve survivors without moving them |
| `compact(store)` | Pack live values and repair internal offsets; slot identity and bytes survive |
| `clear_all(store)` | Empty all slots and set arena length to zero |
| `stats(store)` | Logical/arena/hole/high-water bytes and work counters |

Codes are `OK=0`, `INVALID=1`, `LIMIT=2`. Invalid Store/slot and put quota refusal
preserve payload, layout and counters. Both the per-value bound and total logical
bound include the replacement's new size but exclude its old size. A valid put
that fits those bounds can compact to fit despite fragmentation. Runtime/OS OOM
can still abort; these are recoverable library limits.

`append_to` avoids an intermediate owned export when composing with a Packet's
byte tail. It still copies bytes into the destination. Owned output capacity is
the caller's responsibility and is outside the Store's quota.

## Representation and tradeoffs

Sixty-four fixed `(offset, bytes)` records precede counters and the single tail.
There is no chunk directory or separate freelist. Clear resets a record and finds
the highest live end to trim unused trailing bytes. Put searches gaps in physical
order, reuses the first sufficient gap, then uses remaining tail space. Only when
neither fits within the arena bound does it compact survivors before insertion.
Empty values have zero offset and consume no payload.

Limits allow 1..64 slots, 0..128 MiB total arena bytes and 0..2 MiB per value.
Defaults are 64 slots, 4 MiB total and 65536 bytes per value. Configuring fewer
slots does not shrink the fixed table. Arena length includes holes; logical bytes
do not. Clear need not decrease length when a later live value remains. Explicit
compaction trades copying for removal of those holes.

Gap search and compaction use bounded scans of the slot table: addressing work
can be quadratic in the configured slot count. Clear scans the table once and
copies no surviving bytes; compaction copies each moved live value once. This
favors a small bounded population, not thousands of values or a general allocator.
Compare the additional descriptor work and hole retention with eager compaction
or [indexed chunks](indexed.md) for the actual workload.

Counters separate `logical`, `arena`, `holes`, maximum observed `high_water`, put
bytes `written`, export bytes `exported`, bytes written into already retained
arena ranges `reused`, compaction calls, moved live bytes and `visits` during
gap/compaction scans. Visits exclude clear's scan and payload loops. Reused bytes
do not count runtime allocator reuse after a tail trim. Zeroing, implicit runtime
relocation, output growth/copies, allocator backing capacity and RSS are excluded.
Shrinking the tail does not prove memory was returned to the OS.

## Verification and stream composition

The [contract](../../tests/slot_arena_contract.goose) checks overlapping leftward
compaction, exact hole reuse, quota refusal preserving every counter, empty/zero
limits, invalid slots, two independent Stores, prefixed output and owned exports.
It fills all default slots to 4 MiB and runs 64 non-LIFO clear/refill cycles with
no survivor relocation. Three seeds at 3/16/64 slots produce 27000 mixed puts,
clears and explicit compactions. After every operation, complete bytes match
fixed flat arrays; live spans are disjoint and accounting stays bounded.
An [independent Python model](../../tests/slot_arena_fixture.py) verifies 270
checkpoints' sizes, written bytes, refusals and weighted payload checksums, and
rejects corrupted/incomplete traces. It does not reproduce gap placement.

The [stream Service](../io/streams.md) maps generation-checked logical clients to
these slots. Its 64-varied-page take permutation previously shifted 285768 bytes;
slot removal shifts none. A pressure contract retains two 65536-byte survivors,
then replaces a consumed 32768-byte page with 65536 bytes. Neither the hole nor
the remaining tail fits, so one compaction moves 131072 bytes and the new page
fits the exact 196608-byte three-client bound. Owned exports and survivors remain
correct, and shutdown empties the arena. Search retains its compact queue codec.

```text
cmake --build build-core --config Release --target slot_arena_contract stream_contract search_stream_contract --parallel
ctest --test-dir build-core -C Release -R "^(slot_arena_contract|search_stream_contract)$" --output-on-failure
python tools/stream_qualification.py --build build-core --output local/references/stream/slot-arena-run
```

The qualification runner snapshots the new library/contract/oracle as well as
stream/native sources, builds all three contracts at Goose O0/O1/O2 and runs
three repeats per level on one selected fork. It measures the generated Store
and Service layouts. This is bounded correctness and representation evidence;
it does not establish throughput, fair scheduling or long-session RSS behavior.
