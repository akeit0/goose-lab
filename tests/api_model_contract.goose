import std;
import lab.json.codec;
import api_browser.feed;
import api_browser.snapshot;
fn main() {
    let feed = app_api_feed::example(); assert(feed.code == app_api_feed::OK && feed.items.len == 5);
    let encoded, ok = app_api_feed::encode(feed); assert(ok); let decoded = app_api_feed::decode(encoded);
    assert(decoded.code == app_api_feed::OK && decoded.items.len == 5 && decoded.items[1].title == feed.items[1].title);
    let wrapped = app_api_feed::decode("{\"items\":[{\"id\":9007199254740993,\"title\":\"exact\"}],\"extra\":true}");
    assert(wrapped.code == app_api_feed::OK && wrapped.items[0].id == 9007199254740993);
    let broken = app_api_feed::decode("[{\"id\":1,\"title\":\"first\"},{\"id\":1,\"title\":\"duplicate\"}]");
    assert(broken.code == app_api_feed::SCHEMA && broken.items.len == 0);
    let missing = app_api_feed::decode("[{\"id\":1}]"); assert(missing.code == app_api_feed::SCHEMA && missing.items.len == 0);
    let wrong = app_api_feed::decode("[{\"id\":1,\"title\":\"a\",\"completed\":null}]"); assert(wrong.code == app_api_feed::SCHEMA);
    let bad = app_api_feed::decode("[\n{\"id\":1,}]"); assert(bad.code == app_api_feed::INVALID_JSON && lab_text_strings::contains_folded(bad.error, "line 2"));
    let multiline = app_api_feed::decode("[{\"id\":1,\"title\":\"a\\nb\"}]"); assert(multiline.code == app_api_feed::SCHEMA);
    // Export remains complete beyond the 64 KiB bound of an earlier UI draft.
    var large = app_api_feed::Feed {}; var body: u8[..2048] = []; for i in 2048 { body.push('x'); }
    for i in 40 { large.items.push(app_api_feed::Item { id: i + 1, title: "long", body: body }); }
    let output, written = app_api_feed::encode(large); assert(written && output.len > 65536);
    let restored = app_api_feed::decode(output); assert(restored.code == app_api_feed::OK && restored.items.len == 40 && restored.items[39].body == body);
    let snapshot = app_api_snapshot::Snapshot { feed: large, selected: 40, url: "https://example.com/items", query: "long", source: "remote", changed: true };
    let saved, saved_ok = app_api_snapshot::encode(snapshot); assert(saved_ok && saved.len > 65536);
    let loaded = app_api_snapshot::decode(saved); assert(loaded.code == 0 && loaded.snapshot == snapshot);
    assert(app_api_snapshot::decode("{broken").code == lab_json_file::INVALID_JSON);
    assert(app_api_snapshot::decode("{\"format\":\"goose-api-browser\",\"version\":2}").code == app_api_snapshot::VERSION);
    assert(app_api_snapshot::decode("{}").code == app_api_snapshot::SCHEMA);
    var invalid = copy(snapshot); invalid.selected = 900; let bad_snapshot, made = app_api_snapshot::encode(invalid); assert(made);
    assert(app_api_snapshot::decode(bad_snapshot).code == app_api_snapshot::SCHEMA);
    // Worst-case escaping must be restorable even above the default JSON byte bound.
    var escaped = app_api_feed::Feed {}; var controls: u8[..2048] = []; for i in 2048 { controls.push(1); }
    for i in 128 { escaped.items.push(app_api_feed::Item { id: i + 1, title: "escaped", body: controls }); }
    let biggest = app_api_snapshot::Snapshot { feed: escaped, selected: 128 };
    let largest, largest_ok = app_api_snapshot::encode(biggest); assert(largest_ok && largest.len > 1048576);
    let roundtrip = app_api_snapshot::decode(largest); assert(roundtrip.code == 0 && roundtrip.snapshot == biggest);
    print("API schema, owned strings, lossless IDs and atomic adoption passed");
}
