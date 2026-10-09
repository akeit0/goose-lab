// Sample-specific, versioned persistence; no runtime handles or borrowed values.
namespace app_api_snapshot;
import std;
import lab.json.codec;
import lab.json.file;
import api_browser.feed;
import lab.text.strings;
import lab.fs.files;
let SCHEMA: i32 = 6; let VERSION: i32 = 7;
struct Snapshot {
    feed: app_api_feed::Feed = app_api_feed::Feed {}, url: u8[..512] = [],
    query: u8[..512] = [], source: u8[..512] = [], selected: i64 = -1, changed: bool = false,
}
struct Loaded { code: i32, snapshot: Snapshot = Snapshot {}, revision: lab_fs_files::Revision = lab_fs_files::Revision { code: lab_fs_files::MISSING } }
struct Saved { code: i32, revision: lab_fs_files::Revision = lab_fs_files::Revision { code: lab_fs_files::MISSING } }
fn decode(bytes: const u8[:]) -> Loaded {
    let doc = lab_json_codec::parse(bytes, lab_json_codec::Limits { bytes: lab_json_file::MAX_BYTES });
    if doc.error.code != lab_json_codec::OK { return Loaded { code: lab_json_file::INVALID_JSON }; }
    let root = lab_json_codec::root(doc);
    let format, format_ok = lab_json_codec::text(lab_json_codec::get(root, "format"));
    let version, version_ok = lab_json_codec::integer(lab_json_codec::get(root, "version"));
    if !format_ok || format != "goose-api-browser" || !version_ok { return Loaded { code: SCHEMA }; }
    if version != 1 { return Loaded { code: VERSION }; }
    let url, url_ok = lab_json_codec::text(lab_json_codec::get(root, "url"));
    let query, query_ok = lab_json_codec::text(lab_json_codec::get(root, "query"));
    let source, source_ok = lab_json_codec::text(lab_json_codec::get(root, "source"));
    let selected, selected_ok = lab_json_codec::integer(lab_json_codec::get(root, "selected"));
    let changed, changed_ok = lab_json_codec::boolean(lab_json_codec::get(root, "changed"));
    if !url_ok || !query_ok || !source_ok || url.len > 512 || query.len > 512 || source.len > 512 ||
        !lab_text_strings::single_line(url) || !lab_text_strings::single_line(query) || !lab_text_strings::single_line(source) ||
        !selected_ok || !changed_ok { return Loaded { code: SCHEMA }; }
    let feed = app_api_feed::decode_value(lab_json_codec::get(root, "records"));
    if feed.code != app_api_feed::OK || (selected != -1 && app_api_feed::index(feed, selected) < 0) { return Loaded { code: SCHEMA }; }
    Loaded { code: lab_json_file::OK, snapshot: Snapshot { feed, url, query, source, selected, changed } }
}
fn encode(snapshot: const Snapshot&) -> u8[>..], bool {
    var writer = lab_json_codec::Writer { limit: lab_json_file::MAX_BYTES };
    lab_json_codec::begin_object(writer);
    lab_json_codec::key(writer, "format"); lab_json_codec::write_string(writer, "goose-api-browser");
    lab_json_codec::key(writer, "version"); lab_json_codec::write_integer(writer, 1);
    lab_json_codec::key(writer, "url"); lab_json_codec::write_string(writer, snapshot.url);
    lab_json_codec::key(writer, "query"); lab_json_codec::write_string(writer, snapshot.query);
    lab_json_codec::key(writer, "source"); lab_json_codec::write_string(writer, snapshot.source);
    lab_json_codec::key(writer, "selected"); lab_json_codec::write_integer(writer, snapshot.selected);
    lab_json_codec::key(writer, "changed"); lab_json_codec::write_bool(writer, snapshot.changed);
    lab_json_codec::key(writer, "records"); app_api_feed::write_records(writer, snapshot.feed);
    lab_json_codec::end(writer); let bytes, ok = lab_json_codec::finish(writer); return bytes, ok;
}
fn load(path: const u8[:]) -> Loaded {
    let loaded = lab_json_file::load(path, lab_json_file::MAX_BYTES);
    if loaded.code != lab_json_file::OK { return Loaded { code: loaded.code }; }
    var result = decode(loaded.data); result.revision = lab_fs_files::Revision { code: lab_fs_files::OK, size: loaded.data.len, digest: lab_fs_files::digest(loaded.data) }; result
}
fn write(path: const u8[:], snapshot: const Snapshot&) -> Saved {
    if snapshot.feed.code != app_api_feed::OK { return Saved { code: SCHEMA }; }
    let bytes, ok = encode(snapshot); if !ok { return Saved { code: lab_json_file::LIMIT }; }
    let checked = decode(bytes); if checked.code != lab_json_file::OK { return Saved { code: checked.code }; }
    let code = lab_json_file::save(path, bytes, lab_json_file::MAX_BYTES);
    if code != lab_json_file::OK { return Saved { code: code }; }
    Saved { code: code, revision: lab_fs_files::Revision { code: lab_fs_files::OK, size: bytes.len, digest: lab_fs_files::digest(bytes) } }
}
fn save(path: const u8[:], snapshot: const Snapshot&) -> i32 { write(path, snapshot).code }
fn message(code: i32) -> const u8[:] {
    if code == SCHEMA { "Snapshot has invalid records or session fields" }
    else if code == VERSION { "Snapshot version is not supported" }
    else { lab_json_file::message(code) }
}
