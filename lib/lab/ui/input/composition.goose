// IME preedit owns a bounded UTF-8 snapshot, separate from committed text.
namespace lab_ui_input_composition;
import std;
import gfx;
import lab.text.strings;
struct State { first: i64 = 0, last: i64 = 0,
    cursor: i64 = 0, end: i64 = 0, revision: u64 = 0, serial: u64 = 0, pending: bool = false, text: u8[..512] = [] }
fn active(s: const State&) -> bool { s.text.len != 0 }
fn clear(s: State&) { s.text.resize(0); s.cursor=0; s.end=0; s.pending=false; s.serial++; }
// SDL's start/length count scalars, not bytes or extended graphemes.
fn byte_at(text: const u8[:], scalar: i64) -> i64 {
    if scalar < 0 { return text.len; } var at: i64=0; var count: i64=0;
    while at<text.len && count<scalar { at=lab_text_strings::next(text,at); count++; } at
}
fn payload(token: u64, limit: i64) -> u8[>..], bool {
    var out: u8[>..]=[]; let n=gfx::text_event_into(token,out);
    if n<0 || n>limit { return out,false; } out.resize(n,0);
    if gfx::text_event_into(token,out)!=n { out.resize(0); return out,false; } return out,true;
}
fn update(s: State&, e: gfx::Event, first: i64, last: i64, revision: u64 = 0, limit: i64 = 512) -> bool {
    assert(limit>=0 && limit<=512);
    let bytes,ok=payload(e.text,limit);
    if !ok || !lab_text_strings::single_line(bytes) { clear(s); gfx::clear_composition(); return false; }
    let reshape=!s.pending || s.text!=bytes;
    if !s.pending && bytes.len>0 { s.first=first; s.last=last; s.revision=revision; s.pending=true; }
    s.text.resize(0); s.text.append(bytes); s.cursor=byte_at(s.text,e.start); s.end=if e.length<0 { s.cursor } else { byte_at(s.text,max(0,e.start as i64)+e.length) };
    s.end=max(s.cursor,s.end); if reshape { s.serial++; } true
}
