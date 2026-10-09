// Versioned, bounded documents. Decoding never exposes a partial payload.
namespace lab_fs_storage;
import std;
import os;
import binary;
let OK: i32 = 0; let MISSING: i32 = 1; let IO: i32 = 2; let LIMIT: i32 = 3;
let INVALID: i32 = 4; let VERSION: i32 = 5; let CORRUPT: i32 = 6;
let MAX_BYTES: i64 = 65536;
struct Loaded { code: i32, data: u8[>..] = [] }
extern "glab_goose_file_read" fn read_raw(path: const u8[:], out: u8[:], count: i64&) -> i32;
fn u16le(out: u8[>..]&, value: u16) { out.push((value & 255) as u8); out.push((value >> 8) as u8); }
fn u32le(out: u8[>..]&, value: u32) { for i in 4 { out.push(((value >> (i * 8)) & 255) as u8); } }
fn checksum(bytes: const u8[:]) -> u32 {
    var crc: u32 = 0xFFFFFFFF;
    for byte in bytes {
        crc ^= byte as u32;
        for bit in 8 { crc = (crc >> 1) ^ (if (crc & 1) != 0 { 0xEDB88320 as u32 } else { 0 as u32 }); }
    }
    crc ^ 0xFFFFFFFF
}
fn envelope(tag: const u8[:], version: u16, payload: const u8[:]) -> u8[>..] {
    assert(tag.len == 8 && payload.len <= MAX_BYTES - 20);
    var out: u8[>..] = []; out.append(tag); u16le(out, version); u16le(out, 0);
    u32le(out, payload.len as u32); u32le(out, checksum(payload)); out.append(payload); out
}
fn unpack(bytes: const u8[:], tag: const u8[:], version: u16) -> Loaded {
    if bytes.len > MAX_BYTES { return Loaded { code: LIMIT }; }
    if tag.len != 8 || bytes.len < 20 { return Loaded { code: CORRUPT }; }
    if bytes[..8] != tag { return Loaded { code: INVALID }; }
    let stored_version, v = binary::read_u16le(bytes, 8); let flags, f = binary::read_u16le(bytes, 10);
    let size, n = binary::read_u32le(bytes, 12); let expected, c = binary::read_u32le(bytes, 16);
    if !v || !f || !n || !c || flags != 0 || size as i64 != bytes.len - 20 { return Loaded { code: CORRUPT }; }
    if stored_version != version { return Loaded { code: VERSION }; }
    if checksum(bytes[20..]) != expected { return Loaded { code: CORRUPT }; }
    var out = Loaded { code: OK }; out.data.append(bytes[20..]); out
}
fn load(path: const u8[:], tag: const u8[:], version: u16) -> Loaded {
    var bytes: u8[>..] = []; bytes.resize(MAX_BYTES, 0); var count: i64 = 0;
    let code = read_raw(path, bytes, count);
    if code != OK { return Loaded { code: code }; }
    bytes.resize(count); unpack(bytes, tag, version)
}
fn save(path: const u8[:], tag: const u8[:], version: u16, payload: const u8[:]) -> i32 {
    if tag.len != 8 { return INVALID; }
    if payload.len > MAX_BYTES - 20 { return LIMIT; }
    let bytes = envelope(tag, version, payload);
    if write_file_atomic(path, bytes) { OK } else { IO }
}
