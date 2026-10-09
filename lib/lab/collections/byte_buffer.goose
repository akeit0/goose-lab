// Bounded incremental input. Consumed prefixes are compacted before growth.
namespace lab_collections_byte_buffer;
import std;
struct Buffer { start: i64 = 0, limit: i64 = 2097152, data: u8[>..] = [] }
fn available(buffer: const Buffer&) -> i64 { buffer.data.len - buffer.start }
fn append(buffer: Buffer&, bytes: const u8[:]) -> bool {
    if buffer.limit < 0 || bytes.len > buffer.limit - available(buffer) { return false; }
    if buffer.start > 0 && (buffer.start >= buffer.data.len / 2 || bytes.len > buffer.limit - buffer.data.len) {
        let count = available(buffer); for i in count { buffer.data[i] = buffer.data[buffer.start + i]; }
        let data .= buffer.data; data.resize(count); buffer.start = 0;
    }
    buffer.data.append(bytes); true
}
fn delimiter(buffer: const Buffer&, byte: u8) -> i64 {
    for i in available(buffer) { if buffer.data[buffer.start + i] == byte { return i; } } -1
}
fn consume(buffer: Buffer&, count: i64) -> bool {
    if count < 0 || count > available(buffer) { return false; }
    buffer.start += count;
    if buffer.start == buffer.data.len { let data .= buffer.data; data.resize(0); buffer.start = 0; } true
}
fn take(buffer: Buffer&, count: i64) -> u8[>..] {
    assert(count >= 0 && count <= available(buffer));
    var result: u8[>..] = []; result.append(buffer.data[buffer.start..buffer.start + count]);
    assert(consume(buffer, count)); result
}
fn first(buffer: const Buffer&) -> u8 { assert(available(buffer) > 0); buffer.data[buffer.start] }
