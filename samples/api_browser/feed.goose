// Example domain boundary: validate a complete payload before adopting owned records.
namespace app_api_feed;
import std;
import lab.json.codec;
import lab.text.strings;
let OK: i32 = 0; let INVALID_JSON: i32 = 1; let SCHEMA: i32 = 2;
struct Item { id: i64, title: u8[..160] = [], body: u8[..2048] = [], completed: bool = false }
struct Feed { code: i32 = OK, error: u8[..256] = [], items: Item[..128] = [] }
fn index(feed: const Feed&, id: i64) -> i64 { for i in feed.items.len { if feed.items[i].id == id { return i; } } -1 }
fn decode(bytes: const u8[:]) -> Feed {
    let doc = lab_json_codec::parse(bytes);
    if doc.error.code != lab_json_codec::OK {
        let line, column = lab_json_codec::location(doc);
        return Feed { code: INVALID_JSON, error: str(lab_json_codec::message(doc.error), " at line ", line, ", column ", column, " (byte ", doc.error.offset, ")") };
    }
    decode_value(lab_json_codec::root(doc))
}
fn decode_value(root: lab_json_codec::Value) -> Feed {
    let rows = if lab_json_codec::kind(root) == lab_json_codec::OBJECT { lab_json_codec::get(root, "items") } else { root };
    if lab_json_codec::kind(rows) != lab_json_codec::ARRAY { return Feed { code: SCHEMA, error: "Expected an array, or an object containing an items array." }; }
    if lab_json_codec::count(rows) > 128 { return Feed { code: SCHEMA, error: "This viewer accepts at most 128 records." }; }
    var feed = Feed {}; var row: i64 = 0;
    lab_json_codec::each(rows) { value =>
        row++;
        if lab_json_codec::kind(value) != lab_json_codec::OBJECT { return Feed { code: SCHEMA, error: str("Record ", row, " must be an object.") }; }
        let id, id_ok = lab_json_codec::integer(lab_json_codec::get(value, "id"));
        let title, title_ok = lab_json_codec::text(lab_json_codec::get(value, "title"));
        if !id_ok || id <= 0 || index(feed, id) >= 0 { return Feed { code: SCHEMA, error: str("Record ", row, " needs a unique positive integer id.") }; }
        if !title_ok || title.len == 0 || title.len > 160 || !lab_text_strings::single_line(title) { return Feed { code: SCHEMA, error: str("Record ", row, " needs a single-line title of 1 to 160 UTF-8 bytes.") }; }
        var item = Item { id: id, title: title };
        let body_value = lab_json_codec::get(value, "body");
        if lab_json_codec::exists(body_value) {
            let body, ok = lab_json_codec::text(body_value);
            if !ok || body.len > 2048 { return Feed { code: SCHEMA, error: str("Record ", row, " body must be a string of at most 2048 UTF-8 bytes.") }; }
            item.body.append(body);
        }
        let done = lab_json_codec::get(value, "completed");
        if lab_json_codec::exists(done) {
            let completed, ok = lab_json_codec::boolean(done);
            if !ok { return Feed { code: SCHEMA, error: str("Record ", row, " completed must be a boolean.") }; } item.completed = completed;
        }
        feed.items.push(item);
    };
    feed
}
fn encode(feed: const Feed&) -> u8[>..], bool {
    // Worst case: every byte in all bounded text fields needs a six-byte escape.
    var writer = lab_json_codec::Writer { limit: 128 * (2208 * 6 + 128) };
    write_records(writer, feed); let output, ok = lab_json_codec::finish(writer); return output, ok;
}
fn write_records(writer: lab_json_codec::Writer&, feed: const Feed&) {
    lab_json_codec::begin_array(writer);
    for item in feed.items {
        lab_json_codec::begin_object(writer);
        lab_json_codec::key(writer, "id"); lab_json_codec::write_integer(writer, item.id);
        lab_json_codec::key(writer, "title"); lab_json_codec::write_string(writer, item.title);
        lab_json_codec::key(writer, "body"); lab_json_codec::write_string(writer, item.body);
        lab_json_codec::key(writer, "completed"); lab_json_codec::write_bool(writer, item.completed);
        lab_json_codec::end(writer);
    } lab_json_codec::end(writer);
}
fn example() -> Feed {
    decode("""
        [
          {"id":1,"title":"Explore real API data","body":"Paste a URL above and fetch an array of records. Each record has an id and title; body and completed are optional.","completed":true},
          {"id":2,"title":"A little Unicode: café, 日本語, 🚀","body":"日本語と English を同じ画面で表示します。検索欄に「日本語」を入力して、このレコードを選択できます。\n\nLong links remain readable:\nhttps://example.com/resources/abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789?language=ja&view=details\n\n結合文字も保持します: café / café / が。", "completed":false},
          {"id":3,"title":"Keep the UI responsive","body":"HTTP and JSON validation run on an isolated Goose worker. You can browse this list while a request is in progress.","completed":false},
          {"id":4,"title":"Change a record, then export","body":"Mark this item complete and copy the validated records as JSON. Changes stay local; the viewer does not write to the remote API.","completed":false},
          {"id":5,"title":"Make failures understandable","body":"Malformed JSON includes its line, column and byte position. Invalid records are rejected together, so a partial response never becomes your collection.","completed":false}
        ]
        """)
}
