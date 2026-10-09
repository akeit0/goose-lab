import std;
import os;
import lab.text.grapheme;
import lab.text.utf8;
import lab.collections.byte_buffer;
import lab.git.batch;
import vec;
import lab.ui.geometry;
import lab.ui.layout.viewport;
import lab.ui.layout.scroll;
import lab.collections.state_bank;
import lab.text.selection;
import lab.text.line_break;
import lab.collections.tree;
import lab.ui.command;
import lab.io.debounce;
import lab.text.strings;
import lab.text.literal_search;
import lab.fs.glob;
import lab.document.model;
import lab.document.piece_tree;
struct Draft { count: i64 = 7, text: u8[..16] = "draft" }
fn main() {
    grapheme_contract(); document_contract(); document_stress(); search_patterns(); byte_framing();
    tree_contract(); command_contract(); debounce_contract();
    let label: u8[11] = [97, 9, 10, 13, 92, 255, 0, 0xE6, 0x97, 0xA5, 98];
    assert(lab_text_strings::display_bytes(label) == "a\\t\\n\\r\\\\\\xff\\u0000日b");
    assert(lab_text_strings::display_bytes("abcd", 3) == "…");
    assert(lab_text_strings::display_bytes("日本語", 6) == "日…");
    let japanese, valid = lab_text_line_break::japanese("あ「い」う");
    let expected: u32[3] = [3, 12, 15]; assert(valid && japanese == expected);
    let punctuation, ok = lab_text_line_break::japanese("あい、う"); let expected_punctuation: u32[3] = [3, 9, 12]; assert(ok && punctuation == expected_punctuation);
    assert(!lab_text_line_break::can_end('(') && !lab_text_line_break::can_start(')'));
    assert(!lab_text_line_break::can_start(0x3063) && !lab_text_line_break::can_start(0x30FC));
    assert(!lab_text_line_break::can_start(0x31F0) && lab_text_line_break::allows(0x300D, 0x3042));
    let invalid, rejected = lab_text_line_break::japanese([0xE3, 0x81]); assert(!rejected && invalid.len == 0);
    let empty, empty_ok = lab_text_line_break::japanese(""); assert(empty_ok && empty.len == 0);
    let bounded, fits = lab_text_line_break::japanese("1234", 3); assert(!fits && bounded.len == 0);
    var bank = lab_collections_state_bank::Bank<Draft> {};
    assert(!lab_collections_state_bank::ensure(bank, 0) && !lab_collections_state_bank::lookup(bank, 9));
    lab_collections_state_bank::get(bank, 9).count = 12;
    let draft = lab_collections_state_bank::lookup(bank, 9); assert(draft); draft.text = "edited";
    assert(lab_collections_state_bank::get(bank, 9).count == 12 && lab_collections_state_bank::get(bank, 9).text == "edited");
    for id in 31 { assert(lab_collections_state_bank::ensure(bank, (id + 100) as u64)); }
    assert(!lab_collections_state_bank::ensure(bank, 999) && lab_collections_state_bank::ensure(bank, 9));
    assert(lab_collections_state_bank::remove(bank, 100) && !lab_collections_state_bank::remove(bank, 100));
    assert(lab_collections_state_bank::ensure(bank, 999) && lab_collections_state_bank::get(bank, 999).count == 7);
    assert(lab_collections_state_bank::get(bank, 9).count == 12);
    lab_collections_state_bank::clear(bank); assert(!lab_collections_state_bank::contains(bank, 9));
    var scroll = lab_ui_layout_scroll::State {};
    assert(lab_ui_layout_scroll::consume(scroll, 170.0, 80.0, 200.0) == 50.0 && scroll.offset == 120.0);
    assert(lab_ui_layout_scroll::consume(scroll, -150.0, 80.0, 200.0) == -30.0 && scroll.offset == 0.0);
    assert(lab_ui_layout_scroll::consume(scroll, 12.0, 80.0, 50.0) == 12.0 && scroll.offset == 0.0);
    lab_ui_layout_scroll::reveal(scroll, 140.0, 160.0, 80.0, 200.0); assert(scroll.offset == 80.0);
    lab_ui_layout_scroll::reveal(scroll, 20.0, 40.0, 80.0, 200.0); assert(scroll.offset == 20.0);
    lab_ui_layout_scroll::reveal(scroll, 0.0, 180.0, 80.0, 200.0); assert(scroll.offset == 0.0);
    scroll.offset = 20.0;
    let visible = lab_ui_layout_scroll::visible(scroll, 30.0, 10.0, 100, 0); assert(visible.first == 2 && visible.end == 5);
    let padded = lab_ui_layout_scroll::visible(scroll, 30.0, 10.0, 100); assert(padded.first == 1 && padded.end == 6);
    assert(lab_ui_layout_scroll::visible(scroll, 0.0, 10.0, 100).end == 0);
    scroll.offset = 2000.0; let beyond = lab_ui_layout_scroll::visible(scroll, 30.0, 10.0, 100); assert(beyond.first == 100 && beyond.end == 100);
    assert(lab_ui_geometry::empty(lab_ui_layout_scroll::thumb(scroll, lab_ui_geometry::rect(0.0, 0.0, 100.0, 0.0), 100.0)));
    let viewport = lab_ui_geometry::rect(10.0, 20.0, 100.0, 100.0); scroll.offset = 0.0;
    let thumb = lab_ui_layout_scroll::thumb(scroll, viewport, 500.0);
    lab_ui_layout_scroll::drag(scroll, thumb.y + thumb.h * 0.25, 0.25, viewport, 500.0); assert(scroll.offset == 0.0);
    lab_ui_layout_scroll::drag(scroll, 1000.0, 0.25, viewport, 500.0); assert(scroll.offset == 400.0);
    lab_ui_layout_scroll::drag(scroll, -1000.0, 0.25, viewport, 500.0); assert(scroll.offset == 0.0);
    assert(lab_ui_layout_scroll::track(viewport).w == 14.0 && lab_ui_layout_scroll::track(viewport).x == 96.0);
    lab_ui_layout_scroll::drag(scroll, 50.0, 0.25, viewport, 50.0); assert(scroll.offset == 0.0);
    assert(lab_text_selection::navigate(-1, 0, lab_text_selection::Motion.Next) == -1);
    assert(lab_text_selection::navigate(-1, 20, lab_text_selection::Motion.Next) == 0);
    assert(lab_text_selection::navigate(-1, 20, lab_text_selection::Motion.Previous) == 19);
    assert(lab_text_selection::navigate(0, 20, lab_text_selection::Motion.Previous) == 0);
    assert(lab_text_selection::navigate(19, 20, lab_text_selection::Motion.Next) == 19);
    assert(lab_text_selection::navigate(3, 20, lab_text_selection::Motion.PageNext, 5) == 8);
    assert(lab_text_selection::navigate(3, 20, lab_text_selection::Motion.PagePrevious, 5) == 0);
    assert(lab_text_selection::navigate(19, 20, lab_text_selection::Motion.First) == 0);
    assert(lab_text_selection::navigate(0, 20, lab_text_selection::Motion.Last) == 19);
    assert(lab_text_selection::page_rows(240.0, 44.0) == 5 && lab_text_selection::page_rows(0.0, 44.0) == 1);
    var tree = lab_ui_layout_viewport::Tree {};
    let outer = lab_ui_layout_viewport::push(tree, lab_ui_geometry::rect(10.0, 20.0, 100.0, 100.0), float2 { 0.0, -30.0 });
    let inner = lab_ui_layout_viewport::push(tree, lab_ui_geometry::rect(20.0, 60.0, 80.0, 80.0), float2 { 0.0, -15.0 });
    lab_ui_layout_viewport::pop(tree, inner); lab_ui_layout_viewport::pop(tree, outer);
    lab_ui_layout_viewport::resolve(tree, lab_ui_geometry::rect(0.0, 0.0, 200.0, 200.0));
    assert(tree.regions[inner].world.y == 30.0 && tree.regions[inner].clip.y == 30.0 && tree.regions[inner].clip.h == 80.0);
    assert(lab_ui_layout_viewport::place(tree, inner, lab_ui_geometry::rect(25.0, 70.0, 40.0, 20.0)).y == 25.0);
    assert(lab_ui_layout_viewport::top(tree, float2 { 30.0, 35.0 }) == inner);
    assert(lab_ui_layout_viewport::top(tree, float2 { 12.0, 25.0 }) == outer);
    tree.regions[outer].offset.y = -80.0;
    lab_ui_layout_viewport::resolve(tree, tree.screen);
    assert(tree.regions[inner].world.y == -20.0 && tree.regions[inner].clip.y == 20.0 && tree.regions[inner].clip.h == 40.0);
    assert(lab_ui_layout_viewport::top(tree, float2 { 30.0, 10.0 }) == -1);
    // Resolving twice must never accumulate translation.
    lab_ui_layout_viewport::resolve(tree, tree.screen); assert(tree.regions[inner].world.y == -20.0);
    print("State bank, scroll remainder/reveal/ranges and nested viewport geometry passed");
}

fn tree_contract() {
    var tree = lab_collections_tree::Tree {};
    let root_file = lab_collections_tree::add(tree, "readme", "Readme", -1, false, 1);
    let folder = lab_collections_tree::add(tree, "source/", "Source", -1, true);
    let inner = lab_collections_tree::add(tree, "source/inner/", "Inner", folder, true);
    let leaf = lab_collections_tree::add(tree, "source/inner/code", "Code", inner, false, 2);
    let sibling = lab_collections_tree::add(tree, "source/z", "z", folder, false, 3);
    assert(tree.code == 0 && tree.nodes[leaf].depth == 2 && tree.nodes[leaf].data == 2);
    var state = lab_collections_tree::State { current: "source/inner/code" };
    let all = lab_collections_tree::project(tree, state); assert(all.items.len == 5 && all.items[0].node == folder && all.items[4].node == root_file);
    assert(lab_collections_tree::set_expanded(state, tree.nodes[folder], false));
    let collapsed = lab_collections_tree::project(tree, state); assert(collapsed.items.len == 2 && lab_collections_tree::current(tree, state, collapsed) == -1);
    lab_collections_tree::normalize(tree, state, collapsed); assert(state.current == "source/");
    var matches: bool[5] = [false, false, false, true, false];
    let filtered = lab_collections_tree::project(tree, state, matches); assert(filtered.filtered && filtered.items.len == 3 && filtered.items[2].node == leaf);
    assert(state.closed.len == 1 && !lab_collections_tree::expanded(state, tree.nodes[folder]));
    matches[3] = false; let none = lab_collections_tree::project(tree, state, matches); assert(none.items.len == 0);
    let restored = lab_collections_tree::project(tree, state); assert(restored.items.len == 2);
    var rebuilt = lab_collections_tree::Tree {}; let new_folder = lab_collections_tree::add(rebuilt, "source/", "Source", -1, true);
    assert(lab_collections_tree::add(rebuilt, "source/z", "z", new_folder, false, 3) >= 0);
    lab_collections_tree::prune(rebuilt, state); assert(state.closed.len == 1 && !lab_collections_tree::expanded(state, rebuilt.nodes[new_folder]));
    var absent = lab_collections_tree::Tree {}; lab_collections_tree::prune(absent, state); assert(state.closed.len == 0);
    assert(lab_collections_tree::add(rebuilt, "source/z", "duplicate") == -1 && rebuilt.code == lab_collections_tree::INVALID);
    var invalid = lab_collections_tree::Tree {}; let file = lab_collections_tree::add(invalid, "f", "f");
    assert(lab_collections_tree::add(invalid, "child", "child", file) == -1 && invalid.code == lab_collections_tree::INVALID);
    var deep = lab_collections_tree::Tree {}; var parent: i64 = -1;
    for i in 33 { parent = lab_collections_tree::add(deep, str(i), str(i), parent, true); assert(parent >= 0); }
    assert(lab_collections_tree::add(deep, "too-deep", "too-deep", parent) == -1 && deep.code == lab_collections_tree::LIMIT);
    var wide = lab_collections_tree::Tree {};
    for i in 2048 { assert(lab_collections_tree::add(wide, str(i), str(i), -1, false, i) >= 0); }
    let wide_rows = lab_collections_tree::project(wide, state); assert(wide_rows.items.len == 2048);
    assert(lab_collections_tree::add(wide, "overflow", "overflow") == -1 && wide.code == lab_collections_tree::LIMIT);
}

fn command_contract() {
    var catalog = lab_ui_command::Catalog<i64> {};
    assert(lab_ui_command::add(catalog, 9, "Save snapshot", 90, "Save records", "file disk", "S", 2, false, "A request is running"));
    assert(lab_ui_command::add(catalog, 4, "Show response", 40, "Inspect original bytes", "http raw json"));
    assert(lab_ui_command::add(catalog, 7, "日本語検索", 70));
    let mixed = lab_ui_command::project(catalog, "  SAVE disk "); assert(mixed.items.len == 1 && mixed.items[0] == 0);
    let japanese = lab_ui_command::project(catalog, "日本語"); assert(japanese.items.len == 1 && japanese.items[0] == 2);
    let none = lab_ui_command::project(catalog, "response disk"); assert(none.items.len == 0);
    var state = lab_ui_command::State {}; let all = lab_ui_command::project(catalog, ""); lab_ui_command::normalize(catalog, state, all); assert(state.current == 4);
    let denied, denied_ok = lab_ui_command::resolve(catalog, 9); assert(!denied_ok);
    let action, allowed = lab_ui_command::resolve(catalog, 4); assert(allowed && action == 40);
    var reordered = lab_ui_command::Catalog<i64> {}; assert(lab_ui_command::add(reordered, 7, "日本語検索", 70)); assert(lab_ui_command::add(reordered, 4, "Show response", 41));
    let reordered_rows = lab_ui_command::project(reordered, ""); lab_ui_command::normalize(reordered, state, reordered_rows); assert(state.current == 4 && lab_ui_command::current(reordered, state, reordered_rows) == 1);
    let fresh_action, fresh_allowed = lab_ui_command::resolve(reordered, 4); assert(fresh_allowed && fresh_action == 41);
    assert(!lab_ui_command::add(catalog, 4, "Duplicate", 0) && catalog.code == lab_ui_command::INVALID);
    let invalid_rows = lab_ui_command::project(catalog, ""); assert(invalid_rows.items.len == 0);
    let invalid_action, invalid_allowed = lab_ui_command::resolve(catalog, 4); assert(!invalid_allowed);
    var invalid = lab_ui_command::Catalog<i64> {}; assert(!lab_ui_command::add(invalid, 0, "Invalid", 0));
    var multiline = lab_ui_command::Catalog<i64> {}; assert(!lab_ui_command::add(multiline, 1, "Line\nbreak", 0));
    var oversized = lab_ui_command::Catalog<i64> {}; assert(!lab_ui_command::add(oversized, 1, ['x'; 97], 0));
    var full = lab_ui_command::Catalog<i64> {}; for i in 64 { assert(lab_ui_command::add(full, (i + 1) as u64, str(i), i)); }
    assert(!lab_ui_command::add(full, 65, "Overflow", 0) && full.code == lab_ui_command::LIMIT);
    var duplicate_key = lab_ui_command::Catalog<i64> {}; assert(lab_ui_command::add(duplicate_key, 1, "First", 0, "", "", "S", 2));
    assert(!lab_ui_command::add(duplicate_key, 2, "Second", 0, "", "", "S", 2));
}

fn debounce_contract() {
    var s = lab_io_debounce::State {}; assert(!lab_io_debounce::ready(s, 100, 10, 30));
    lab_io_debounce::push(s, 100); assert(!lab_io_debounce::ready(s, 109, 10, 30));
    lab_io_debounce::push(s, 108); assert(!lab_io_debounce::ready(s, 117, 10, 30) && lab_io_debounce::ready(s, 118, 10, 30));
    lab_io_debounce::push(s, 116); lab_io_debounce::push(s, 124); assert(lab_io_debounce::ready(s, 130, 10, 30));
    lab_io_debounce::clear(s); assert(!lab_io_debounce::ready(s, 140, 10, 30));
    lab_io_debounce::push(s, 100); lab_io_debounce::push(s, 5); assert(s.first == 5 && !lab_io_debounce::ready(s, 4, 10, 30));
    assert(lab_io_debounce::ready(s, 15, 10, 30));
    lab_io_debounce::clear(s); lab_io_debounce::push(s, 9223372036854775800); assert(lab_io_debounce::ready(s, 9223372036854775807, 7, 7));
}


fn byte_framing() {
    var buffer = lab_collections_byte_buffer::Buffer { limit: 8 };
    assert(lab_collections_byte_buffer::append(buffer, "abcdef") && lab_collections_byte_buffer::consume(buffer, 4));
    assert(lab_collections_byte_buffer::append(buffer, "ghijkl") && lab_collections_byte_buffer::available(buffer) == 8);
    assert(!lab_collections_byte_buffer::append(buffer, "m") && !lab_collections_byte_buffer::consume(buffer, 9));
    assert(lab_collections_byte_buffer::take(buffer, 8) == "efghijkl" && lab_collections_byte_buffer::available(buffer) == 0);
    assert(lab_collections_byte_buffer::append(buffer, [97, 0, 98]) && lab_collections_byte_buffer::delimiter(buffer, 0) == 1);
    let binary: u8[3] = [97, 0, 98]; assert(lab_collections_byte_buffer::take(buffer, 3) == binary);
    let oid: const u8[:] = "0123456789012345678901234567890123456789";
    var packet: u8[>..] = []; packet.append(str(oid, " blob 6")); packet.push(0);
    let raw: u8[6] = [0, 13, 10, 10, 26, 255]; packet.append(raw); packet.push(0);
    // Every possible split, including header/body boundaries and embedded NULs.
    for split in packet.len + 1 {
        var decoder = lab_git_batch::Decoder {};
        assert(lab_git_batch::append(decoder, packet[..split])); let first = lab_git_batch::next(decoder);
        assert(first.code == 0);
        assert(lab_git_batch::append(decoder, packet[split..])); let second = lab_git_batch::next(decoder);
        if first.ready { assert(first.bytes == raw && !second.ready); }
        else { assert(second.ready && second.bytes == raw && second.kind == "blob" && second.size == 6); }
        assert(lab_git_batch::finish(decoder) == 0 && !lab_git_batch::append(decoder, "late"));
    }
    var decoder = lab_git_batch::Decoder {}; var consecutive: u8[>..] = []; consecutive.append(packet); consecutive.append(packet);
    assert(lab_git_batch::append(decoder, consecutive)); let owned = lab_git_batch::next(decoder); let next = lab_git_batch::next(decoder);
    assert(owned.bytes == raw && next.bytes == raw && lab_git_batch::finish(decoder) == 0);
    decoder = lab_git_batch::Decoder {}; assert(lab_git_batch::append(decoder, "HEAD:a\nb missing\0"));
    let missing = lab_git_batch::next(decoder); assert(missing.ready && missing.status == lab_git_batch::MISSING && missing.name == "HEAD:a\nb" && missing.bytes.len == 0);
    assert(lab_git_batch::append(decoder, str(oid, " blob 0\0\0"))); let empty = lab_git_batch::next(decoder); assert(empty.ready && empty.size == 0 && empty.bytes.len == 0);
    assert(lab_git_batch::finish(decoder) == 0);
    decoder = lab_git_batch::Decoder {}; assert(lab_git_batch::append(decoder, str(oid, "\0"))); assert(lab_git_batch::next(decoder).code == lab_git_batch::PROTOCOL);
    decoder = lab_git_batch::Decoder {}; assert(lab_git_batch::append(decoder, str(oid, " blob 1\0ax"))); assert(lab_git_batch::next(decoder).code == lab_git_batch::PROTOCOL);
    decoder = lab_git_batch::Decoder {}; assert(lab_git_batch::append(decoder, packet[..packet.len - 1])); assert(!lab_git_batch::next(decoder).ready && lab_git_batch::finish(decoder) == lab_git_batch::TRUNCATED);
    decoder = lab_git_batch::Decoder { max_bytes: 5 }; assert(lab_git_batch::append(decoder, packet)); assert(lab_git_batch::next(decoder).code == lab_git_batch::LIMIT);
    decoder = lab_git_batch::Decoder {}; var huge: u8[>..] = []; huge.resize(8193, 'a'); assert(lab_git_batch::append(decoder, huge)); assert(lab_git_batch::next(decoder).code == lab_git_batch::LIMIT);
    print("Byte framing: compaction, capacity, all splits, exact binary bodies, retained ownership and malformed/truncated limits passed");
}

fn search_patterns() {
    let pattern = lab_text_literal_search::compile("aba"); var cursor = lab_text_literal_search::Cursor {}; var hits: i64[..8] = [];
    loop { let page = lab_text_literal_search::scan(pattern, "ababa", cursor, 1); for hit in page.matches { hits.push(hit.start); assert(hit.end == hit.start + 3); } if page.done { break; } }
    let expected: i64[2] = [0, 2]; assert(hits == expected);
    cursor = lab_text_literal_search::Cursor {}; let folded = lab_text_literal_search::compile("a日本語", true);
    let page = lab_text_literal_search::scan(folded, "A日本語 a日本語", cursor); assert(page.done && page.matches.len == 2 && page.matches[1].start == 11);
    cursor = lab_text_literal_search::Cursor {}; let dense = lab_text_literal_search::compile("a");
    let first = lab_text_literal_search::scan(dense, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", cursor); assert(!first.done && first.matches.len == 32);
    let last = lab_text_literal_search::scan(dense, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", cursor); assert(last.done && last.matches.len == 1 && last.matches[0].start == 32);
    assert(lab_text_literal_search::scan(dense, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", cursor).matches.len == 0);
    assert(!lab_text_literal_search::compile("").valid && !lab_text_literal_search::compile([0xFF]).valid);
    fn yes(glob: const u8[:], path: const u8[:]) { let compiled = lab_fs_glob::compile(glob); assert(compiled.valid && lab_fs_glob::matches(compiled, path)); }
    fn no(glob: const u8[:], path: const u8[:]) { let compiled = lab_fs_glob::compile(glob); assert(compiled.valid && !lab_fs_glob::matches(compiled, path)); }
    yes("**/*.txt", "one.txt"); yes("**/*.txt", "a/b/日本語.txt"); no("*.txt", "a/b.txt");
    yes("**/foo", "foo"); yes("**/foo", "a/foo"); no("**/foo", "xfoo"); no("**/foo", "a/xfoo");
    yes("a/**/b", "a/b"); yes("a/**/b", "a/x/y/b"); no("a/**/b", "a/xb");
    yes("**/a/**/b", "x/a/y/b"); yes("**/a/**/b", "a/b"); no("**/a/**/b", "xa/b");
    yes("?.txt", "日.txt"); no("?.txt", "日本.txt"); no("?.txt", "/.txt");
    yes("**/build-*/**", "nested/build-core/a.goose"); yes("**/build/**", "build/");
    yes("literal[1].txt", "literal[1].txt"); no("*.TXT", "a.txt");
    assert(!lab_fs_glob::compile("***").valid && !lab_fs_glob::compile("a**/b").valid && !lab_fs_glob::compile("a\\b").valid);
    print("Search patterns: incremental overlapping KMP, ASCII folding, Unicode glob scalars and directory-prefix boundaries passed");
}

fn document_contract() {
    var empty = lab_document_model::create(""); assert(empty.tree.arena.len == 0 && empty.tree.capacity == 0);
    var doc = lab_document_model::create("日本語\r\nlast\n"); assert(doc.code == 0 && lab_document_model::lines(doc) == 3 && doc.newline == "\r\n");
    assert(!lab_document_model::boundary(doc, 1) && !lab_document_model::boundary(doc, 10));
    let code, changed = lab_document_model::replace(doc, 9, 11, "\nnew\n"); assert(code == 0 && changed && lab_document_model::contents(doc) == "日本語\nnew\nlast\n");
    assert(lab_document_model::dirty(doc) && lab_document_model::undo(doc) && !lab_document_model::dirty(doc));
    assert(lab_document_model::redo(doc)); lab_document_model::mark_saved(doc); assert(!lab_document_model::dirty(doc));
    assert(lab_document_model::select(doc, 0, 0)); let inserted, did = lab_document_model::insert(doc, "prefix "); assert(inserted == 0 && did);
    assert(lab_document_model::baseline(doc) == "日本語\nnew\nlast\n" && lab_document_model::undo(doc) && !lab_document_model::dirty(doc));
    assert(lab_document_model::undo(doc) && lab_document_model::dirty(doc)); assert(lab_document_model::redo(doc) && !lab_document_model::dirty(doc));
    assert(lab_document_model::compact(doc) && doc.history.len == 0 && lab_document_model::contents(doc) == lab_document_model::baseline(doc));
    print("Piece document: UTF-8/CRLF boundaries, edits, persistent undo/redo, saved revision and compaction passed");
}

recursive fn verify_piece(b: const lab_document_piece_tree::Buffer&, root: i64) -> i64, i64, i64 {
    if root < 0 { return 0, 0, 0; } let n = lab_document_piece_tree::get_node(b, root);
    if n.left < 0 { assert(n.right < 0 && n.bytes > 0 && n.bytes <= lab_document_piece_tree::LEAF && n.height == 1); var feeds: i64 = 0; for i in n.bytes { if lab_document_piece_tree::source_byte(b, n.start + i) == '\n' { feeds++; } } assert(feeds == n.lines); return n.bytes, feeds, 1; }
    let lb, lf, lh = verify_piece(b, n.left); let rb, rf, rh = verify_piece(b, n.right);
    assert(n.bytes == lb + rb && n.lines == lf + rf && n.height == max(lh, rh) + 1 && lh <= rh + 1 && rh <= lh + 1); return n.bytes, n.lines, n.height;
}
fn document_stress() {
    var source: u8[..32768] = []; for i in 9000 { source.push(if i % 79 == 0 { '\n' } else { 'a' }); }
    var d = lab_document_model::create(source); var rng: u64 = 42; var collected = false;
    for i in 1600 {
        rng = rng * 6364136223846793005 + 1; let start = (rng % (source.len + 1) as u64) as i64;
        let end = min(source.len, start + i % 7); let inserted = str("(", i, ")", if i % 3 == 0 { "\n" } else { "" });
        var expected: u8[..32768] = []; expected.append(source[..start]); expected.append(inserted); expected.append(source[end..]);
        let old_nodes = d.tree.nodes; let code, changed = lab_document_model::replace(d, start, end, inserted); assert(code == 0 && changed); source = expected;
        if d.tree.nodes < old_nodes { collected = true; }
        assert(lab_document_model::contents(d) == source); let bytes, feeds, height = verify_piece(d.tree, d.tree.root); assert(bytes == source.len && height < 32);
        var line: i64 = 0; assert(lab_document_piece_tree::line_start(d.tree, 0) == 0);
        for at in source.len { if source[at] == '\n' { line++; assert(lab_document_piece_tree::line_start(d.tree, line) == at + 1 && lab_document_piece_tree::line_at(d.tree, at + 1) == line); } }
        assert(line == feeds && lab_document_model::lines(d) == line + 1);
        if i % 17 == 0 { assert(lab_document_model::undo(d) && lab_document_model::redo(d) && lab_document_model::contents(d) == source); }
    }
    assert(d.tree.arena.len == d.tree.capacity * 7 + (d.tree.stored + 7) / 8 && d.tree.capacity <= lab_document_piece_tree::MAX_NODES);
    assert(collected && d.history.len == 256); lab_document_model::collect(d); assert(lab_document_model::contents(d) == source && lab_document_model::baseline(d).len == 9000);
    for i in 256 { assert(lab_document_model::undo(d)); let bytes, feeds, height = verify_piece(d.tree, d.tree.root); assert(bytes == lab_document_model::size(d)); }
    for i in 256 { assert(lab_document_model::redo(d)); } assert(lab_document_model::contents(d) == source);
    assert(lab_document_model::compact(d) && lab_document_model::contents(d) == source && lab_document_model::baseline(d).len == 9000 && d.history.len == 0);
    var small = lab_document_model::create("abc", lab_document_piece_tree::Limits { bytes: 4, store: 4 });
    let code, changed = lab_document_model::replace(small, 0, 0, "too large"); assert(code == lab_document_model::LIMIT && !changed && lab_document_model::contents(small) == "abc" && small.history.len == 0);
    var typing = lab_document_model::create(""); for i in 1000 { let code, changed = lab_document_model::insert(typing, "x", true); assert(code == 0 && changed); }
    assert(typing.history.len == 1 && lab_document_piece_tree::get_node(typing.tree, typing.tree.root).leaves < 8 && lab_document_model::undo(typing) && lab_document_model::size(typing) == 0 && lab_document_model::redo(typing));
    lab_document_model::mark_saved(typing); let code, changed = lab_document_model::insert(typing, "y", true); assert(code == 0 && changed && typing.history.len == 2 && lab_document_model::undo(typing) && !lab_document_model::dirty(typing));
    var recycling=lab_document_model::create("abc",lab_document_piece_tree::Limits { bytes: 16, store: 2048 }); var reclaimed=false;
    for i in 1500 {
        let old=recycling.tree.stored; let code,changed=lab_document_model::replace(recycling,0,3,if i%2==0 { "xyz" } else { "abc" });
        assert(code==0 && changed); if recycling.tree.stored<old { reclaimed=true; }
    }
    assert(reclaimed && recycling.history.len==256 && lab_document_model::baseline(recycling)=="abc");
    for i in 256 { assert(lab_document_model::undo(recycling)); let expected = if i%2==0 { "xyz" } else { "abc" }; assert(lab_document_model::contents(recycling)==expected); }
    for i in 256 { assert(lab_document_model::redo(recycling)); } assert(lab_document_model::contents(recycling)=="abc");
    print("Piece tree: 1,600 oracle edits, AVL/line invariants, live-root GC, limits, typing coalescence and saved undo boundary passed");
}

fn grapheme_case(source: const u8[:], expected: const i64[:]) {
    let offsets,ok=lab_text_grapheme::offsets(source); assert(ok && offsets.len==expected.len);
    var doc=lab_document_model::create(source);
    for i in offsets.len { assert(offsets[i]==expected[i]); }
    var at=0;
    loop {
        var found=false; for byte in expected { if at==byte { found=true; } }
        assert(lab_text_grapheme::boundary(source,at)==found && lab_document_model::grapheme_boundary(doc,at)==found);
        if at==source.len { break; } let cp,end,valid=lab_text_utf8::decode(source,at); assert(valid); at=end;
    }
    for i in expected.len-1 { assert(lab_text_grapheme::next(source,expected[i])==expected[i+1] && lab_document_model::next(doc,expected[i])==expected[i+1]); assert(lab_text_grapheme::previous(source,expected[i+1])==expected[i] && lab_document_model::previous(doc,expected[i+1])==expected[i]); }
}
fn grapheme_contract() {
    grapheme_case("é👍🏽👨‍👩‍👧‍👦🇯🇵\r\n",[0,3,11,36,44,46]);
    let argv=args();
    if argv.len>1 {
        var corpus: u8[>..]=[]; assert(read_file(argv[1],corpus)); var cases=0;
        for line in split(corpus,'\n') {
            let body=split(line,'#')[0]; var source: u8[>..]=[]; var expected: i64[>..]=[];
            for token in split(body,' ') {
                let item=trim(token);
                if item.len==0 || item=="×" { continue; }
                if item=="÷" { expected.push(source.len); }
                else { let cp,ok=parse_int(item,16); assert(ok); push_utf8(source,cp); }
            }
            if expected.len>0 { grapheme_case(source,expected); cases++; }
        } assert(cases>700); print("Unicode 17.0 official grapheme cases: ",cases);
    }
    // Context across pieces, including an EP + Extend* + ZWJ sequence at a leaf cut.
    var source: u8[>..]=[]; source.resize(4092,'a'); source.append("👨‍👩‍👧‍👦🇯🇵é"); var doc=lab_document_model::create(source);
    assert(lab_document_model::next(doc,4092)==4117 && lab_document_model::previous(doc,4117)==4092);
    assert(lab_document_model::next(doc,4117)==4125 && lab_document_model::previous(doc,4128)==4125);
    assert(!lab_document_model::grapheme_boundary(doc,4096));
    let code,changed=lab_document_model::replace(doc,4092,4117,""); assert(code==0 && changed && lab_document_model::undo(doc));
    print("Grapheme navigation: emoji/combining/Indic/CRLF, piece boundaries and byte-range API passed");
}
