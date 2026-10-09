# JSON in Goose

`lab.json.codec` is a pure Goose parser and structured writer. It has no C dependency.
`lab.text.utf8` supplies strict Unicode scalar decoding, also shared by `lab.text.strings`.
The [API Browser](../apps/api-browser.md) exercises these libraries with HTTP and the
modern UI, rather than leaving JSON as an isolated utility.

## Ownership and value access

`parse` borrows its input and owns a flat preorder token array. Each container
records the first token after its subtree, so traversal skips nested values
without recursion. There is no allocation for every node and no recursive
tree type. The token array grows as needed; decoded strings allocate only
when requested. Treat `Document.source` and `Document.tokens` as read-only
implementation data after parsing.

`Value` borrows the document. Keep both the document and input alive while
using values or `raw` slices. `text` returns an owned, unescaped UTF-8 builder;
its result can be copied into an application model and outlive the document.
Copy at that boundary, rather than sending a document that borrows an HTTP
response to another thread.

```goose
import std;
import lab.json.codec;

fn main() {
    let doc = lab_json_codec::parse("{\"id\":9007199254740993,\"title\":\"café\"}");
    assert(doc.error.code == lab_json_codec::OK);
    let root = lab_json_codec::root(doc);
    let id, id_ok = lab_json_codec::integer(lab_json_codec::get(root, "id"));
    let title, title_ok = lab_json_codec::text(lab_json_codec::get(root, "title"));
    assert(id_ok && title_ok);
    print(id, " ", title);
}
```

`kind` distinguishes `OBJECT`, `ARRAY`, `STRING`, `NUMBER`, `BOOL`, `NULL`,
and `MISSING`. An absent member is different from a present JSON null.
`get` looks up object members by decoded name. `at` selects an array element,
returning missing for a negative or out-of-range index. `count` returns the
number of members/elements; it is zero for scalars.

For iteration, prefer `each(array) { value => ... };` and
`members(object) { key, value => ... };`. They walk the tape once. Repeated
`at` calls over an entire array are quadratic, since individual lookup scans
preceding subtrees. Object lookup is linear and currently decodes each key;
there is no object index/cache.

## Parsing policy

The grammar follows [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259).
Top-level scalars are supported. Comments, trailing commas, leading-zero
numbers, NaN, Infinity, a UTF-8 BOM, extra roots and non-JSON whitespace are
rejected. Literal UTF-8 is validated. Escaped surrogate pairs become one
scalar; unpaired surrogates are rejected as an explicit interoperability
policy, stricter than the RFC's permissive escape grammar.

Duplicate member names are preserved in iteration. `get` selects the
**first decoded match**, including escaped spellings of the same name. The
RFC describes duplicate names as an interoperability problem; applications
requiring unique names should enforce that in their schema. This policy is
not interchangeable with Python/Go's usual last-value behavior.

Default limits are 1 MiB of input, 65,536 tokens (keys count too), and 128
simultaneously open containers. Pass `Limits` to reduce the bounds or change
byte/token allowances. Depth cannot exceed the fixed 128-entry parser stack.
Parsing is iterative, so nested input does not consume the native call stack.
Invalid limits fail explicitly. Any error clears the token tape, and `root`
then returns missing: a partially validated document is never exposed.

`doc.error` contains a code and zero-based byte offset. `location(doc)` returns
one-based line and **byte column**, not a Unicode character column. Codes
distinguish syntax, Unicode, byte, token and depth failures. `message` supplies
a short description; the application decides how to display it.

## Numbers

Numbers keep their original decimal lexeme. `raw` and `write_value` preserve
large integers, decimal precision, negative zero and exponent spelling.
`integer` accepts integer spelling in the full signed i64 range, detecting
overflow before arithmetic; it rejects fractions/exponents rather than
silently truncating. An ID above 2^53 remains exact.

`number` returns an approximate f64 and a success flag. It normalizes leading
zeroes before using Goose's decimal conversion and rejects non-finite output.
Tiny values may underflow to zero. This is not a correctly rounded decimal
library: Goose's `parse_flt` may differ by an ulp for long mantissas/exponents.
Use raw decimal text for money or other exact quantities.

## Structured output

`Writer` owns its output and a fixed container stack. Begin a container, write
members/elements, then end it. `key` is valid only in an object and must be
followed by a value. Strings validate UTF-8 and escape quotes, backslashes
and all JSON control bytes. Errors are sticky; `finish` returns an owned
builder and false with empty output if the result is incomplete or failed.

```goose
var writer = lab_json_codec::Writer {};
lab_json_codec::begin_object(writer);
lab_json_codec::key(writer, "id"); lab_json_codec::write_integer(writer, 9007199254740993);
lab_json_codec::key(writer, "price"); lab_json_codec::write_number(writer, "12.50");
lab_json_codec::key(writer, "title"); lab_json_codec::write_string(writer, "café");
lab_json_codec::key(writer, "completed"); lab_json_codec::write_bool(writer, false);
lab_json_codec::end(writer);
let output, ok = lab_json_codec::finish(writer);
assert(ok);
```

Other operations are `begin_array`, `write_null`, and `write_value` for a
validated subtree. `write_number` validates an exact decimal/exponent lexeme;
it requires no floating-point conversion. There is deliberately no automatic
arbitrary-struct codec or f64 formatter yet. The domain encoder shows explicit
field mapping. The default output limit is 1 MiB and nesting is bounded at 128,
including copied subtrees. Set `Writer.limit` before writing if a bounded
application model needs a larger output allowance.

Design references include [Go encoding/json](https://pkg.go.dev/encoding/json)
and [Rust serde_json](https://docs.rs/serde_json/latest/serde_json/): distinguish
syntax from conversion, make ownership visible, and avoid routing exact IDs
through f64. This implementation chooses a borrowed token tape instead of
their generic dynamic tree/codec APIs to fit Goose's current type and lifetime
model. It does not claim performance parity; no benchmark has been made.

See [validation](../validation.md) for contract and integration checks.
