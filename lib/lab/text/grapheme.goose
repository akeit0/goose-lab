// Extended grapheme clusters, Unicode 17.0.0 / UAX #29 GB1..GB999.
// Scalar byte positions remain separate from user-visible editing boundaries.
namespace lab_text_grapheme;
import std;
import lab.text.utf8;
import lab.text.internal.grapheme_data;
fn number(at: i64) -> i64 { let s = lab_text_internal_grapheme_data::DATA; (s[at] as i64) | ((s[at+1] as i64)<<8) | ((s[at+2] as i64)<<16) }
fn property(cp: i64) -> i64 {
    if cp>=0 && cp<128 { if cp==13 { return 1; } if cp==10 { return 2; } return if cp<32 || cp==127 { 3 } else { 0 }; }
    if cp>=0xAC00 && cp<=0xD7A3 { return if (cp-0xAC00)%28==0 { 12 } else { 13 }; }
    var first: i64 = 0; var end = lab_text_internal_grapheme_data::DATA.len / 7;
    while first < end { let m=(first+end)/2; if number(m*7+3)<cp { first=m+1; } else { end=m; } }
    if first*7 < lab_text_internal_grapheme_data::DATA.len && number(first*7)<=cp { return lab_text_internal_grapheme_data::DATA[first*7+6]; } 0
}
fn control(p: i64) -> bool { let c=p & 15; c==1 || c==2 || c==3 }
fn pair(left: i64, right: i64) -> i32 {
    let l=left & 15; let r=right & 15;
    if l==1 && r==2 { return 0; } // CRLF
    if control(left) || control(right) { return 1; }
    if l==9 && (r==9 || r==10 || r==12 || r==13) { return 0; }
    if (l==12 || l==10) && (r==10 || r==11) { return 0; }
    if (l==13 || l==11) && r==11 { return 0; }
    if r==4 || r==5 || r==8 || l==7 { return 0; }
    -1
}
// Constant-size streaming state: one pass for contiguous buffers, no offsets needed.
struct State { previous: i64 = -1, regional: i64 = 0, emoji: bool = false, zwj: bool = false, consonant: bool = false, linker: bool = false }
fn feed(s: State&, cp: i64) -> bool {
    let p=property(cp); var boundary = s.previous < 0;
    if s.previous >= 0 {
        let simple=pair(s.previous,p);
        boundary = if simple>=0 { simple==1 }
            else if (p & 32)!=0 && s.consonant && s.linker { false }
            else if (p & 16)!=0 && s.zwj { false }
            else if (s.previous & 15)==6 && (p & 15)==6 { s.regional%2==0 } else { true };
    }
    s.regional = if (p & 15)==6 { s.regional+1 } else { 0 };
    s.zwj = (p & 15)==5 && s.emoji;
    if (p & 16)!=0 { s.emoji=true; } else if (p & 15)!=4 { s.emoji=false; }
    if (p & 32)!=0 { s.consonant=true; s.linker=false; }
    else if (p & 64)!=0 { s.linker=s.linker || s.consonant; }
    else if (p & 128)==0 { s.consonant=false; s.linker=false; }
    s.previous=p; boundary
}
// Read(at, backwards) returns a scalar and its start/end byte position.
// Static borrowed accessor also works over a piece tree, including across leaves.
fn boundary_at<Read>(at: i64, length: i64) -> bool {
    if at<=0 || at>=length { return at==0 || at==length; }
    let left, start=Read(at,true); let right, end=Read(at,false);
    let l=property(left); let r=property(right); let simple=pair(l,r); if simple>=0 { return simple==1; }
    if (r & 32)!=0 {
        var pos=at; var linker=false;
        while pos>0 { let cp,before=Read(pos,true); let p=property(cp);
            if (p & 64)!=0 { linker=true; } else if (p & 128)==0 { if (p & 32)!=0 && linker { return false; } break; } pos=before;
        }
    }
    if (l & 15)==5 && (r & 16)!=0 {
        var pos=start;
        while pos>0 { let cp,before=Read(pos,true); let p=property(cp); if (p & 15)==4 { pos=before; } else { if (p & 16)!=0 { return false; } break; } }
    }
    if (l & 15)==6 && (r & 15)==6 {
        var pos=at; var count=0;
        while pos>0 { let cp,before=Read(pos,true); if (property(cp) & 15)!=6 { break; } count++; pos=before; }
        return count%2==0;
    } true
}
fn scalar(value: const u8[:], at: i64, backwards: bool) -> i64, i64 {
    var start=at;
    if backwards { assert(at>0); start--; while start>0 && (value[start] & 0xC0)==0x80 { start--; } }
    let cp,end,ok=lab_text_utf8::decode(value,start); assert(ok); return cp, if backwards { start } else { end };
}
// Requires valid UTF-8 and a scalar boundary. Use lab.text.utf8.valid at an input boundary.
fn boundary(value: const u8[:], at: i64) -> bool {
    fn read(pos: i64, backwards: bool) -> i64, i64 { let cp,end=scalar(value,pos,backwards); return cp,end; }
    boundary_at(at,value.len,read)
}
fn previous(value: const u8[:], at: i64) -> i64 {
    var pos=clamp(at,0,value.len);
    if pos>0 { let cp,before=scalar(value,pos,true); pos=before; }
    while pos>0 && !boundary(value,pos) { let cp,before=scalar(value,pos,true); pos=before; } pos
}
fn next(value: const u8[:], at: i64) -> i64 {
    var pos=clamp(at,0,value.len);
    if pos<value.len { let cp,end=scalar(value,pos,false); pos=end; }
    while pos<value.len && !boundary(value,pos) { let cp,end=scalar(value,pos,false); pos=end; } pos
}
fn offsets(value: const u8[:]) -> u32[>..], bool {
    var out: u32[>..]=[]; var s=State {}; var at=0;
    if value.len>0x7FFFFFFF { return out,false; }
    while at<value.len { let cp,end,ok=lab_text_utf8::decode(value,at); if !ok { out.resize(0); return out,false; } if feed(s,cp) { out.push(at as u32); } at=end; }
    out.push(value.len as u32); return out,true;
}
