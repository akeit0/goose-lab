// Owned, bounded search pages: encode only used hits/issues and string bytes.
namespace lab_fs_search_codec;
import std;
import binary;
import lab.fs.search;
let MAX_BYTES: i64 = 44540;
fn integer(out: u8[>..]&, value: u64, width: i64) {
    for i in width { out.push(((value >> (i * 8)) & 255) as u8); }
}
fn text(out: u8[>..]&, value: const u8[:]) { integer(out, value.len as u64, 2); out.append(value); }
fn encode(batch: const lab_fs_search::Batch&) -> u8[>..] {
    var out: u8[>..] = [1];
    integer(out, (batch.code as! u32), 4); out.push(if batch.done { 1 } else { 0 });
    integer(out, (batch.result as! u32), 4);
    for value in [batch.progress.entries, batch.progress.files, batch.progress.searched,
        batch.progress.skipped, batch.progress.matches, batch.progress.active] { integer(out, value as! u64, 8); }
    out.push(batch.hits.len as u8); out.push(batch.issues.len as u8);
    for hit in batch.hits {
        text(out, hit.path); for value in [hit.line, hit.column, hit.start, hit.end] { integer(out, value as! u64, 8); }
        text(out, hit.preview);
    }
    for issue in batch.issues {
        text(out, issue.path); integer(out, (issue.reason as! u32), 4); integer(out, (issue.detail as! u32), 4);
    }
    assert(out.len <= MAX_BYTES); out
}
struct Reader { data: const u8[:], at: i64 = 0, valid: bool = true }
fn byte(r: Reader&) -> u8 {
    let data, ok = binary::read_bytes(r.data, r.at, 1); if !ok { r.valid = false; return 0; } r.at++; data[0]
}
fn int32(r: Reader&) -> i32 {
    let value, ok = binary::read_u32le(r.data, r.at); if !ok { r.valid = false; return 0; } r.at += 4; value as! i32
}
fn int64(r: Reader&) -> i64 {
    let low, a = binary::read_u32le(r.data, r.at); let high, b = binary::read_u32le(r.data, r.at + 4);
    if !a || !b { r.valid = false; return 0; } r.at += 8; (low | ((high as u64) << 32)) as! i64
}
fn string(r: Reader&, maximum: i64) -> const u8[:] {
    let size, a = binary::read_u16le(r.data, r.at);
    if !a || size > maximum { r.valid = false; return r.data[..0]; }
    let data, b = binary::read_bytes(r.data, r.at + 2, size);
    if !b { r.valid = false; return r.data[..0]; } r.at += 2 + size as i64; data
}
// A failure exposes only an empty Batch, never a partially decoded page.
fn decode(data: const u8[:]) -> lab_fs_search::Batch, bool {
    if data.len < 60 || data.len > MAX_BYTES { return lab_fs_search::Batch {}, false; }
    var r = Reader { data }; let version = byte(r); let code = int32(r); let done = byte(r); let result = int32(r);
    let entries = int64(r); let files = int64(r); let searched = int64(r);
    let skipped = int64(r); let matches = int64(r); let active = int64(r);
    let hits = byte(r); let issues = byte(r);
    if version != 1 || done > 1 || hits > 32 || issues > 32 { return lab_fs_search::Batch {}, false; }
    var batch = lab_fs_search::Batch { code: code, done: done != 0, result: result, progress: lab_fs_search::Progress { entries, files, searched, skipped, matches, active } };
    for i in hits as i64 {
        let path = string(r, 512); let line = int64(r); let column = int64(r); let start = int64(r); let end = int64(r); let preview = string(r, 320);
        if !r.valid { return lab_fs_search::Batch {}, false; }
        batch.hits.push(lab_fs_search::Hit { path, line, column, start, end, preview });
    }
    for i in issues as i64 {
        let path = string(r, 512); let reason = int32(r); let detail = int32(r);
        if !r.valid { return lab_fs_search::Batch {}, false; }
        batch.issues.push(lab_fs_search::Issue { path, reason, detail });
    }
    if !r.valid || r.at != data.len { return lab_fs_search::Batch {}, false; } return batch, true;
}
