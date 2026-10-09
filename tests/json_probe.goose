import std;
import os;
import lab.json.codec;
fn main() {
    let argv = args(); assert(argv.len == 2); var input: u8[>..] = []; assert(read_file(argv[1], input));
    let doc = lab_json_codec::parse(input);
    if doc.error.code != lab_json_codec::OK { print("ERROR ", doc.error.code, " ", doc.error.offset); return; }
    // Rebuild every container and decoded key/string through the writer.
    var writer = lab_json_codec::Writer {};
    // A flat tape allows traversal without recursive serializer callbacks.
    var frames: i64[..128] = []; var index: i64 = 0;
    while index < doc.tokens.len {
        while frames.len > 0 && index == frames[frames.len - 1] { lab_json_codec::end(writer); frames.resize(frames.len - 1); }
        let token = doc.tokens[index]; let value = lab_json_codec::Value { doc: doc, index: index };
        if writer.frames.len > 0 && writer.frames[writer.frames.len - 1].kind == lab_json_codec::OBJECT && !writer.frames[writer.frames.len - 1].needs_value {
            let text, ok = lab_json_codec::text(value); assert(ok); lab_json_codec::key(writer, text);
        } else if token.kind == lab_json_codec::OBJECT || token.kind == lab_json_codec::ARRAY {
            if token.kind == lab_json_codec::OBJECT { lab_json_codec::begin_object(writer); } else { lab_json_codec::begin_array(writer); }
            frames.push(token.next);
        } else if token.kind == lab_json_codec::STRING {
            let text, ok = lab_json_codec::text(value); assert(ok); lab_json_codec::write_string(writer, text);
        } else { lab_json_codec::write_value(writer, value); }
        index++;
    }
    while frames.len > 0 { lab_json_codec::end(writer); frames.resize(frames.len - 1); }
    let output, ok = lab_json_codec::finish(writer); assert(ok); print("OK"); print(output);
}
