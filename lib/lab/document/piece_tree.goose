// Persistent AVL piece tree. Nodes refer to an append-only UTF-8 byte arena.
namespace lab_document_piece_tree;
import std;
import lab.text.utf8;
import lab.text.line_index;
let OK: i32 = 0; let INVALID: i32 = 1; let LIMIT: i32 = 2;
let LEAF: i64 = 4096; let MAX_NODES: i64 = 32768;
struct Limits { bytes: i64 = 2097152, store: i64 = 8388608, nodes: i64 = MAX_NODES }
struct Node { left: i64 = -1, right: i64 = -1, start: i64 = 0, bytes: i64 = 0, lines: i64 = 0, height: i64 = 1, leaves: i64 = 1 }
// One resizable tail: seven-word node records followed by eight-byte text words.
// Child IDs use zero for absent, so all stored node fields are unsigned.
struct Buffer { code: i32 = OK, root: i64 = -1, limits: Limits = Limits {}, nodes: i64 = 0, capacity: i64 = 0, stored: i64 = 0, arena: u64[>..<] = [] }
fn get_node(b: const Buffer&, id: i64) -> Node {
    assert(id >= 0 && id < b.nodes); let i = id * 7;
    Node { (b.arena[i] as i64)-1, (b.arena[i+1] as i64)-1, b.arena[i+2] as i64, b.arena[i+3] as i64, b.arena[i+4] as i64, b.arena[i+5] as i64, b.arena[i+6] as i64 }
}
fn put(b: Buffer&, id: i64, n: Node) {
    let i = id * 7; b.arena[i]=(n.left+1) as u64; b.arena[i+1]=(n.right+1) as u64; b.arena[i+2]=n.start as u64; b.arena[i+3]=n.bytes as u64; b.arena[i+4]=n.lines as u64; b.arena[i+5]=n.height as u64; b.arena[i+6]=n.leaves as u64;
}
fn grow_nodes(b: Buffer&) {
    if b.nodes < b.capacity { return; }
    let capacity = min(b.limits.nodes, max(8, b.capacity * 2)); let words = (b.stored + 7) / 8; let old = b.capacity * 7; let next = capacity * 7;
    b.arena.resize(next + words, 0); var i = words; while i > 0 { i--; b.arena[next+i] = b.arena[old+i]; } b.capacity = capacity;
}
fn push_node(b: Buffer&, n: Node) { grow_nodes(b); put(b, b.nodes, n); b.nodes++; }
fn source_byte(b: const Buffer&, at: i64) -> u8 { assert(at >= 0 && at < b.stored); ((b.arena[b.capacity*7+at/8] >> ((at%8)*8)) & 255) as u8 }
fn append_text(b: Buffer&, text: const u8[:]) {
    b.arena.resize(b.capacity*7+(b.stored+text.len+7)/8, 0);
    for byte in text { let i = b.capacity*7+b.stored/8; let shift = (b.stored%8)*8; b.arena[i] = (b.arena[i] & ~((255 as u64) << shift)) | ((byte as u64) << shift); b.stored++; }
}
fn source_range(b: const Buffer&, start: i64, end: i64, out: u8[>..]&) { for at in start..end { out.push(source_byte(b, at)); } }
fn size(b: const Buffer&, root: i64) -> i64 { if root < 0 { 0 } else { get_node(b, root).bytes } }
fn feeds(b: const Buffer&, root: i64) -> i64 { if root < 0 { 0 } else { get_node(b, root).lines } }
fn height(b: const Buffer&, root: i64) -> i64 { if root < 0 { 0 } else { get_node(b, root).height } }
fn leaf(b: Buffer&, start: i64, end: i64) -> i64 {
    assert(start < end && end <= b.stored && b.nodes < b.limits.nodes);
    var lines: i64 = 0; for i in start..end { if source_byte(b, i) == '\n' { lines++; } }
    let id = b.nodes; push_node(b, Node { start: start, bytes: end - start, lines: lines }); id
}
fn branch(b: Buffer&, left: i64, right: i64) -> i64 {
    if left < 0 { return right; } if right < 0 { return left; }
    assert(b.nodes < b.limits.nodes); let id = b.nodes;
    let bytes = size(b, left) + size(b, right); let lines = feeds(b, left) + feeds(b, right);
    let h = max(height(b, left), height(b, right)) + 1; let leaves = get_node(b, left).leaves + get_node(b, right).leaves;
    push_node(b, Node { left: left, right: right, bytes: bytes, lines: lines, height: h, leaves: leaves }); id
}
fn balance(b: Buffer&, left: i64, right: i64) -> i64 {
    let lh = height(b, left); let rh = height(b, right);
    if lh > rh + 1 {
        let n = get_node(b, left);
        if height(b, n.left) >= height(b, n.right) { let tail = branch(b, n.right, right); return branch(b, n.left, tail); }
        let m = get_node(b, n.right); let head = branch(b, n.left, m.left); let tail = branch(b, m.right, right); return branch(b, head, tail);
    }
    if rh > lh + 1 {
        let n = get_node(b, right);
        if height(b, n.right) >= height(b, n.left) { let head = branch(b, left, n.left); return branch(b, head, n.right); }
        let m = get_node(b, n.left); let head = branch(b, left, m.left); let tail = branch(b, m.right, n.right); return branch(b, head, tail);
    } branch(b, left, right)
}
recursive fn join(b: Buffer&, left: i64, right: i64) -> i64 {
    if left < 0 { return right; } if right < 0 { return left; }
    if get_node(b, left).left < 0 && get_node(b, right).left < 0 && get_node(b, left).start + get_node(b, left).bytes == get_node(b, right).start && size(b, left) + size(b, right) <= LEAF { return leaf(b, get_node(b, left).start, get_node(b, right).start + get_node(b, right).bytes); }
    if height(b, left) > height(b, right) + 1 { let n = get_node(b, left); let tail = join(b, n.right, right); return balance(b, n.left, tail); }
    if height(b, right) > height(b, left) + 1 { let n = get_node(b, right); let head = join(b, left, n.left); return balance(b, head, n.right); }
    branch(b, left, right)
}
recursive fn split(b: Buffer&, root: i64, at: i64) -> i64, i64 {
    if at == 0 { return -1, root; } if at == size(b, root) { return root, -1; }
    let n = get_node(b, root);
    if n.left < 0 { let head = leaf(b, n.start, n.start + at); let tail = leaf(b, n.start + at, n.start + n.bytes); return head, tail; }
    let left_size = size(b, n.left);
    if at < left_size { let head, rest = split(b, n.left, at); let tail = join(b, rest, n.right); return head, tail; }
    if at == left_size { return n.left, n.right; }
    let rest, tail = split(b, n.right, at - left_size); let head = join(b, n.left, rest); return head, tail;
}
recursive fn build(b: Buffer&, ids: const i64[:], first: i64, end: i64) -> i64 {
    if first == end { return -1; } if end - first == 1 { return ids[first]; }
    let middle = first + (end - first) / 2; let left = build(b, ids, first, middle); let right = build(b, ids, middle, end); branch(b, left, right)
}
fn pieces(b: Buffer&, start: i64, end: i64) -> i64 {
    var ids: i64[..1024] = []; var at = start;
    while at < end {
        var next = min(end, at + LEAF); while next < end && (source_byte(b, next) & 0xC0) == 0x80 { next--; }
        ids.push(leaf(b, at, next)); at = next;
    } build(b, ids, 0, ids.len)
}
fn create(bytes: const u8[:], limits: Limits = Limits {}) -> Buffer {
    if limits.bytes < 0 || limits.bytes > 2097152 || limits.store < limits.bytes || limits.store > 8388608 || limits.nodes < 1 || limits.nodes > MAX_NODES || !lab_text_utf8::valid(bytes) { return Buffer { code: INVALID }; }
    if bytes.len > limits.bytes || max(0, 2 * ((bytes.len + LEAF - 4) / (LEAF - 3)) - 1) > limits.nodes { return Buffer { code: LIMIT }; }
    var b = Buffer { limits: limits };
    append_text(b, bytes); b.root = pieces(b, 0, bytes.len); b
}
fn byte_at(b: const Buffer&, root: i64, at: i64) -> u8 {
    assert(at >= 0 && at < size(b, root)); var node = root; var offset = at;
    loop { let n = get_node(b, node); if n.left < 0 { return source_byte(b, n.start + offset); } let length = size(b, n.left); if offset < length { node = n.left; } else { node = n.right; offset -= length; } }
}
fn boundary(b: const Buffer&, at: i64) -> bool { at >= 0 && at <= size(b, b.root) && (at == size(b, b.root) || (byte_at(b, b.root, at) & 0xC0) != 0x80) }
recursive fn append_range(b: const Buffer&, root: i64, start: i64, end: i64, out: u8[>..]&) {
    if start == end { return; } let n = get_node(b, root);
    if n.left < 0 { source_range(b, n.start + start, n.start + end, out); return; }
    let length = size(b, n.left);
    if start < length { append_range(b, n.left, start, min(end, length), out); }
    if end > length { append_range(b, n.right, max(0, start - length), end - length, out); }
}
fn read_at(b: const Buffer&, root: i64, start: i64, end: i64) -> u8[>..] {
    assert(start >= 0 && end >= start && end <= size(b, root)); var out: u8[>..] = []; append_range(b, root, start, end, out); out
}
fn read(b: const Buffer&, start: i64, end: i64) -> u8[>..] { read_at(b, b.root, start, end) }
fn reserve(b: const Buffer&, insertion: i64) -> i64 { 128 * (height(b, b.root) + 1) + 2 * ((insertion + LEAF - 4) / (LEAF - 3)) + 16 }
// Validation/preflight precede every append or node change; errors preserve text.
fn replace(b: Buffer&, start: i64, end: i64, bytes: const u8[:]) -> i32 {
    if b.code != OK || !boundary(b, start) || !boundary(b, end) || end < start || !lab_text_utf8::valid(bytes) { return INVALID; }
    if size(b, b.root) - (end - start) > b.limits.bytes - bytes.len || bytes.len > b.limits.store - b.stored || reserve(b, bytes.len) > b.limits.nodes - b.nodes { return LIMIT; }
    let old = b.stored; append_text(b, bytes); let inserted = pieces(b, old, b.stored);
    let head, rest = split(b, b.root, start); let removed, tail = split(b, rest, end - start);
    let prefix = join(b, head, inserted); b.root = join(b, prefix, tail); OK
}
recursive fn prefix_feeds(b: const Buffer&, root: i64, end: i64) -> i64 {
    if end == 0 { return 0; } if end == size(b, root) { return feeds(b, root); } let n = get_node(b, root);
    if n.left < 0 { var count: i64 = 0; for i in end { if source_byte(b, n.start + i) == '\n' { count++; } } return count; }
    let length = size(b, n.left); if end <= length { return prefix_feeds(b, n.left, end); } feeds(b, n.left) + prefix_feeds(b, n.right, end - length)
}
fn line_at(b: const Buffer&, at: i64) -> i64 { assert(at >= 0 && at <= size(b, b.root)); prefix_feeds(b, b.root, at) }
recursive fn feed_offset(b: const Buffer&, root: i64, which: i64) -> i64 {
    let n = get_node(b, root);
    if n.left < 0 { var count: i64 = 0; for i in n.bytes { if source_byte(b, n.start + i) == '\n' { if count == which { return i; } count++; } } assert(false); return 0; }
    let left_feeds = feeds(b, n.left); if which < left_feeds { return feed_offset(b, n.left, which); } size(b, n.left) + feed_offset(b, n.right, which - left_feeds)
}
fn line_start(b: const Buffer&, line: i64) -> i64 { assert(line >= 0 && line <= feeds(b, b.root)); if line == 0 { 0 } else { feed_offset(b, b.root, line - 1) + 1 } }
fn line_span(b: const Buffer&, line: i64) -> lab_text_line_index::Span {
    let first = line_start(b, line); var end = if line < feeds(b, b.root) { line_start(b, line + 1) - 1 } else { size(b, b.root) };
    if end > first && byte_at(b, b.root, end - 1) == '\r' && line < feeds(b, b.root) { end--; } lab_text_line_index::Span { first, end }
}
// All retained roots must be supplied. Collection remaps their numeric IDs.
fn collect(b: Buffer&, roots: i64[:]) {
    var marked: bool[>..] = []; marked.resize(b.nodes, false); var mapping: i64[>..] = []; mapping.resize(b.nodes, -1);
    fn mark(root: i64) {
        var stack: i64[..64] = []; if root >= 0 { stack.push(root); }
        while stack.len > 0 { let n = stack[stack.len - 1]; stack.resize(stack.len - 1); if marked[n] { continue; } marked[n] = true;
            let node = get_node(b, n); if node.left >= 0 { stack.push(node.right); stack.push(node.left); }
        }
    }
    mark(b.root); for root in roots { mark(root); }
    var count: i64 = 0;
    for i in b.nodes { if !marked[i] { continue; } var n = get_node(b, i); if n.left >= 0 { n.left = mapping[n.left]; n.right = mapping[n.right]; } mapping[i] = count; put(b, count, n); count++; }
    if b.root >= 0 { b.root = mapping[b.root]; } for i in roots.len { if roots[i] >= 0 { roots[i] = mapping[roots[i]]; } }
    b.nodes = count;
}

struct Range { start: i64, end: i64, next: i64 = 0 }
// Collect unreachable text too, without discarding any supplied undo/saved root.
fn collect_bytes(b: Buffer&) {
    var spans: Range[>..] = [];
    for i in b.nodes { let n=get_node(b,i); if n.left<0 { spans.push(Range { n.start, n.start+n.bytes }); } }
    fn less(a: const Range&, c: const Range&) -> bool { a.start < c.start }
    sort(spans, less);
    var ranges: Range[>..] = [];
    for span in spans {
        if ranges.len>0 && span.start<=ranges[ranges.len-1].end { ranges[ranges.len-1].end=max(ranges[ranges.len-1].end,span.end); }
        else { ranges.push(span); }
    }
    var next: i64=0;
    for i in ranges.len {
        ranges[i].next=next;
        for at in ranges[i].start..ranges[i].end {
            let byte=source_byte(b,at) as u64; let word=b.capacity*7+next/8; let shift=(next%8)*8;
            b.arena[word]=(b.arena[word] & ~((255 as u64) << shift)) | (byte << shift); next++;
        }
    }
    for i in b.nodes {
        var n=get_node(b,i); if n.left>=0 { continue; }
        var first: i64=0; var end=ranges.len;
        while first<end { let middle=first+(end-first)/2; if ranges[middle].end<=n.start { first=middle+1; } else { end=middle; } }
        assert(first<ranges.len && ranges[first].start<=n.start && n.start+n.bytes<=ranges[first].end);
        n.start=ranges[first].next+n.start-ranges[first].start; put(b,i,n);
    }
    b.stored=next; b.arena.resize(b.capacity*7+(next+7)/8);
}
