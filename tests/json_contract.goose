import std;
import lab.json.codec;
import lab.text.utf8;
import lab.json.edit;
fn main() {
    let doc = lab_json_codec::parse("{\"title\":\"Goose \\uD83D\\uDE80\",\"items\":[1,true,null,{\"a\":2}],\"exact\":9007199254740993}");
    assert(doc.error.code == lab_json_codec::OK);
    let root = lab_json_codec::root(doc); assert(lab_json_codec::kind(root) == lab_json_codec::OBJECT && lab_json_codec::count(root) == 3);
    let title, text_ok = lab_json_codec::text(lab_json_codec::get(root, "title")); assert(text_ok && title == "Goose 🚀");
    let items = lab_json_codec::get(root, "items"); assert(lab_json_codec::count(items) == 4);
    let first, integer_ok = lab_json_codec::integer(lab_json_codec::at(items, 0)); assert(integer_ok && first == 1);
    let yes, bool_ok = lab_json_codec::boolean(lab_json_codec::at(items, 1)); assert(yes && bool_ok);
    assert(lab_json_codec::kind(lab_json_codec::at(items, 2)) == lab_json_codec::NULL);
    assert(!lab_json_codec::exists(lab_json_codec::get(root, "missing")) && !lab_json_codec::exists(lab_json_codec::at(items, 4)));
    let exact, exact_ok = lab_json_codec::integer(lab_json_codec::get(root, "exact")); assert(exact_ok && exact == 9007199254740993);
    var seen: i64 = 0; lab_json_codec::each(items) { v => seen++; }; assert(seen == 4);
    var members: i64 = 0; lab_json_codec::members(root) { k, v => members++; }; assert(members == 3);
    let invalid: const u8[:][12] = ["", "[1,]", "{\"a\":1,}", "01", "1.", "1e", "+1", "true false", "[", "{\"a\" 1}", "\"\\x\"", "\"\\uD800\""];
    for bytes in invalid { let bad = lab_json_codec::parse(bytes); assert(bad.error.code != lab_json_codec::OK && bad.tokens.len == 0 && !lab_json_codec::exists(lab_json_codec::root(bad))); }
    let min_doc = lab_json_codec::parse("-9223372036854775808"); let minimum, min_ok = lab_json_codec::integer(lab_json_codec::root(min_doc)); assert(min_ok && minimum == -9223372036854775807 - 1);
    let overflow = lab_json_codec::parse("9223372036854775808"); let n, ok = lab_json_codec::integer(lab_json_codec::root(overflow)); assert(!ok);
    let deep = lab_json_codec::parse("[[0]]", lab_json_codec::Limits { depth: 1 }); assert(deep.error.code == lab_json_codec::DEPTH_LIMIT);
    let limited = lab_json_codec::parse("[0,1]", lab_json_codec::Limits { tokens: 2 }); assert(limited.error.code == lab_json_codec::TOKEN_LIMIT);
    var writer = lab_json_codec::Writer {}; lab_json_codec::begin_object(writer); lab_json_codec::key(writer, "title"); lab_json_codec::write_string(writer, title);
    lab_json_codec::key(writer, "items"); lab_json_codec::write_value(writer, items); lab_json_codec::key(writer, "exact"); lab_json_codec::write_integer(writer, exact); lab_json_codec::end(writer);
    let output, written = lab_json_codec::finish(writer); assert(written); let again = lab_json_codec::parse(output); assert(again.error.code == lab_json_codec::OK);
    let title_again, t = lab_json_codec::text(lab_json_codec::get(lab_json_codec::root(again), "title")); assert(t && title_again == title);
    boundaries();
    object_edits();
    print("JSON parse, borrowed values, exact integers, Unicode, traversal and writer passed");
}
fn object_edits() {
    let original: const u8[:] = " \n{\n  \"theme\" : \"light\",\n  \"future\":{\"exact\":900719925474099312345,\"rate\":1.250e-20}\n}\n";
    let updated = lab_json_edit::set(original, "theme", "\"dark\"");
    assert(updated.code == 0 && updated.changed && updated.bytes == " \n{\n  \"theme\" : \"dark\",\n  \"future\":{\"exact\":900719925474099312345,\"rate\":1.250e-20}\n}\n");
    let unchanged = lab_json_edit::set(original, "theme", "\"light\"");
    assert(unchanged.code == 0 && !unchanged.changed && unchanged.bytes == original);
    let inserted = lab_json_edit::set(original, "日本語\n\"", "[true, {\"a\":null}]"); assert(inserted.code == 0 && inserted.changed);
    let doc = lab_json_codec::parse(inserted.bytes); let selected = lab_json_edit::find(doc, "日本語\n\"");
    assert(selected.code == 0 && selected.index >= 0 && lab_json_codec::raw(lab_json_codec::Value { doc, selected.index }) == "[true, {\"a\":null}]");
    let empty = lab_json_edit::set(" \n{ }\t", "", "0"); assert(empty.code == 0 && empty.bytes == " \n{ \"\":0}\t");
    let escaped = lab_json_edit::set("{\"\\u0061\" : [1,2],\"other\":true}", "a", "{} ");
    assert(escaped.code == 0 && escaped.bytes == "{\"\\u0061\" : {} ,\"other\":true}");
    let duplicate = lab_json_edit::set("{\"a\":1,\"\\u0061\":2}", "a", "3"); assert(duplicate.code == lab_json_edit::AMBIGUOUS && duplicate.bytes.len == 0);
    let unrelated = lab_json_edit::set("{\"a\":1,\"a\":2}", "b", "3"); assert(unrelated.code == 0);
    let absent = lab_json_edit::find(doc, "missing"); assert(absent.code == 0 && absent.index == -1);
    assert(lab_json_edit::set("[]", "a", "0").code == lab_json_edit::NOT_OBJECT);
    assert(lab_json_edit::set("{broken", "a", "0").code == lab_json_edit::SOURCE);
    let bad_value = lab_json_edit::set("{}", "a", "[1,]"); assert(bad_value.code == lab_json_edit::VALUE && bad_value.error.offset == 3 && bad_value.bytes.len == 0);
    assert(lab_json_edit::set("{}", [255], "0").code == lab_json_edit::KEY);
    assert(lab_json_edit::set("{}", "a", "0", lab_json_codec::Limits { bytes: 6 }).code == lab_json_edit::LIMIT);
    let exact = lab_json_edit::set("{}", "a", "0", lab_json_codec::Limits { bytes: 7 }); assert(exact.code == 0 && exact.bytes == "{\"a\":0}");
    let complexity = lab_json_edit::set("{}", "a", "[0]", lab_json_codec::Limits { tokens: 3 });
    assert(complexity.code == lab_json_edit::LIMIT && complexity.error.code == lab_json_codec::TOKEN_LIMIT && complexity.bytes.len == 0);
    let depth = lab_json_edit::set("{}", "a", "[]", lab_json_codec::Limits { depth: 1 }); assert(depth.code == lab_json_edit::LIMIT && depth.error.code == lab_json_codec::DEPTH_LIMIT);
    print("JSON edits: exact unknown-field preservation, escaped keys, duplicate ambiguity, fragments and combined budgets passed");
}
fn boundaries() {
    let dup = lab_json_codec::parse("{\"\\u0061\":1,\"a\":2}"); let a, found = lab_json_codec::integer(lab_json_codec::get(lab_json_codec::root(dup), "a")); assert(found && a == 1);
    let bytes: u8[3] = [0x22, 0x80, 0x22]; let invalid = lab_json_codec::parse(bytes); assert(invalid.error.code == lab_json_codec::UNICODE && invalid.error.offset == 1);
    let limited = lab_json_codec::parse("null", lab_json_codec::Limits { bytes: 3 }); assert(limited.error.code == lab_json_codec::BYTE_LIMIT);
    let overflow = lab_json_codec::parse("-9223372036854775809"); let n, ok = lab_json_codec::integer(lab_json_codec::root(overflow)); assert(!ok);
    let fraction = lab_json_codec::parse("12.5e-1"); let number, finite = lab_json_codec::number(lab_json_codec::root(fraction)); assert(finite && number == 1.25);
    let small = lab_json_codec::parse("0.000000000000000000000125"); let small_number, small_ok = lab_json_codec::number(lab_json_codec::root(small)); assert(small_ok && small_number > 1e-22 && small_number < 2e-22);
    let huge = lab_json_codec::parse("1e400"); let inf, representable = lab_json_codec::number(lab_json_codec::root(huge)); assert(!representable && huge.error.code == lab_json_codec::OK);
    var controls: u8[>..] = []; for i in 32 { controls.push(i as u8); } controls.append("\"\\🚀");
    var writer = lab_json_codec::Writer {}; lab_json_codec::write_string(writer, controls); let encoded, complete = lab_json_codec::finish(writer); assert(complete);
    let decoded = lab_json_codec::parse(encoded); let text, text_ok = lab_json_codec::text(lab_json_codec::root(decoded)); assert(text_ok && text == controls);
    var invalid_writer = lab_json_codec::Writer {}; lab_json_codec::write_string(invalid_writer, [0x80 as u8]); assert(invalid_writer.error == lab_json_codec::UNICODE);
    var pending = lab_json_codec::Writer {}; lab_json_codec::begin_object(pending); lab_json_codec::key(pending, "a"); lab_json_codec::end(pending);
    let unfinished, done = lab_json_codec::finish(pending); assert(!done && unfinished.len == 0 && pending.error == lab_json_codec::SYNTAX);
    var repeated = lab_json_codec::Writer {}; lab_json_codec::write_null(repeated); lab_json_codec::write_bool(repeated, true); assert(repeated.error == lab_json_codec::SYNTAX);
    var too_small = lab_json_codec::Writer { limit: 2 }; lab_json_codec::write_string(too_small, "abc"); lab_json_codec::write_string(too_small, [0x80 as u8]); assert(too_small.error == lab_json_codec::BYTE_LIMIT);
    var nested = lab_json_codec::Writer {}; for i in 128 { lab_json_codec::begin_array(nested); } lab_json_codec::write_value(nested, lab_json_codec::root(dup)); assert(nested.error == lab_json_codec::DEPTH_LIMIT);
    var deepest = lab_json_codec::Writer {}; for i in 128 { lab_json_codec::begin_array(deepest); } lab_json_codec::write_null(deepest); for i in 128 { lab_json_codec::end(deepest); }
    let deep_text, deep_ok = lab_json_codec::finish(deepest); assert(deep_ok); let deep_doc = lab_json_codec::parse(deep_text); assert(deep_doc.error.code == lab_json_codec::OK);
    var decimal = lab_json_codec::Writer {}; lab_json_codec::write_number(decimal, "1.250e-20"); let decimal_text, decimal_ok = lab_json_codec::finish(decimal); assert(decimal_ok && decimal_text == "1.250e-20");
    var illegal = lab_json_codec::Writer {}; lab_json_codec::write_number(illegal, "01"); assert(illegal.error == lab_json_codec::SYNTAX);
}
