import std;
import os;
import gfx;
import lab.ui.input.shortcuts;
import lab.ui.render.font;
import lab.ui.view;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.git.repository;
import lab.text.diff;
import lab.git.client;
import workbench.git.viewer;
import lab.collections.tree;
import lab.ui.views.text;
import lab.fs.watch;
import lab.io.process;
import lab.fs.search;
fn tick(app: app_git_viewer::App&) { assert(gfx::frame()); app_git_viewer::frame(app); }
fn click(app: app_git_viewer::App&, name: const u8[:]) {
    let r = lab_ui_view::bounds(app.view, name); let x = (r.x + r.w / 2.0) * app.scale; let y = (r.y + r.h / 2.0) * app.scale;
    gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, true); gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, false); tick(app);
}
fn key(app: app_git_viewer::App&, name: const u8[:]) { assert(gfx::inject_key(name, true)); assert(gfx::inject_key(name, false)); tick(app); }
fn modified_key(app: app_git_viewer::App&, modifier: const u8[:], name: const u8[:]) {
    assert(gfx::inject_key(modifier, true)); assert(gfx::inject_key(name, true)); assert(gfx::inject_key(name, false)); assert(gfx::inject_key(modifier, false)); tick(app);
}
fn wait(app: app_git_viewer::App&) {
    let until = clock_ns() + 10000000000;
    while app.client.busy || app.changes.pending { assert(clock_ns() < until); sleep_ms(2); tick(app); }
}
fn wait_change(app: app_git_viewer::App&, previous: i64) {
    let until = clock_ns() + 10000000000;
    while app.auto_refreshes <= previous || app.client.busy || app.changes.pending {
        assert(clock_ns() < until); sleep_ms(2); tick(app);
    }
}
fn frames_for(app: app_git_viewer::App&, duration: i64) {
    let until = clock_ns() + duration; while clock_ns() < until { sleep_ms(2); tick(app); }
}
fn node(app: const app_git_viewer::App&, name: const u8[:]) -> lab_ui_view::Node<app_git_viewer::Action> {
    for n in app.view.nodes { if n.name == name { return n; } } assert(false); default<lab_ui_view::Node<app_git_viewer::Action>>()
}
fn has_node(app: const app_git_viewer::App&, name: const u8[:]) -> bool {
    for n in app.view.nodes { if n.name == name { return true; } } false
}
fn filter(app: app_git_viewer::App&, text: const u8[:]) {
    lab_ui_controls_field::set(app_git_viewer::query(app), ""); tick(app); click(app, "search");
    assert(gfx::inject_text(text)); tick(app); wait(app);
}
fn click_node(app: app_git_viewer::App&, name: const u8[:]) {
    let r = node(app, name).rect;
    gfx::inject_mouse((r.x + 8.0) * app.scale, (r.y + r.h / 2.0) * app.scale, gfx::MOUSE_LEFT, true);
    gfx::inject_mouse((r.x + 8.0) * app.scale, (r.y + r.h / 2.0) * app.scale, gfx::MOUSE_LEFT, false); tick(app);
}
fn linked_watch_contract(repo: const u8[:], scale: f32) {
    assert(gfx::open_headless((1180.0 * scale) as i64, (720.0 * scale) as i64));
    var app = app_git_viewer::create(repo, lab_ui_render_font::default_font(), lab_ui_render_font::default_mono(), scale);
    let worker = thread_spawn(lab_git_client::worker); app_git_viewer::refresh(app); tick(app); wait(app);
    assert(app.files.items.len == 1 && app.selected == "staged.txt");
    if app.watch_code != lab_fs_watch::UNSUPPORTED {
        assert(app.watch_code == 0 && app.metadata_watch.id != 0 && app.common_watch.id != 0);
        click(app, "staged"); wait(app); assert(app.files.items.len == 0);
        let previous = app.auto_refreshes; let add_args: const u8[:][5] = ["-C", repo, "add", "--", "staged.txt"];
        let added = lab_io_process::run("git", add_args, repo); assert(added.code == 0 && added.exit_code == 0); wait_change(app, previous);
        assert(app.staged && app.files.items.len == 1 && app.selected == "staged.txt" && app.diff.patch.added == 1);
        let before_ref = app.auto_refreshes; let ref_args: const u8[:][5] = ["-C", repo, "update-ref", "refs/heads/watch-fixture", "HEAD"];
        let updated = lab_io_process::run("git", ref_args, repo); assert(updated.code == 0 && updated.exit_code == 0); wait_change(app, before_ref);
        assert(app.selected == "staged.txt" && app.diff.patch.added == 1);
        let before_head = app.auto_refreshes; let commit_args: const u8[:][5] = ["-C", repo, "commit", "-qm", "linked fixture"];
        let committed = lab_io_process::run("git", commit_args, repo); assert(committed.code == 0 && committed.exit_code == 0); wait_change(app, before_head);
        assert(app.files.items.len == 0 && app.diff.patch.rows.len == 0);
    }
    app_git_viewer::join(app, worker); app_git_viewer::destroy(app); assert(gfx::misuse_count() == 0); gfx::close();
    print("Linked worktree: external index, common refs and detached HEAD invalidation passed");
}
fn history_contract(repo: const u8[:], screenshot: const u8[:], scale: f32) {
    assert(gfx::open_headless((1180.0 * scale) as i64, (820.0 * scale) as i64));
    var app = app_git_viewer::create(repo, lab_ui_render_font::default_font(), lab_ui_render_font::default_mono(), scale);
    app.live = false;
    let worker = thread_spawn(lab_git_client::worker); app_git_viewer::refresh(app); tick(app); wait(app);
    assert(!app.history && app.files.items.len == 0);
    click(app, "history"); wait(app);
    assert(app.history && app.page.items.len == 32 && app.page.more && app.commit_index == 0 && app.files.items.len == 0);
    let anchor = app.page.anchor;
    click(app, "older"); wait(app);
    assert(app.page.offset == 32 && app.page.items.len == 5 && !app.page.more && app.page.anchor == anchor);
    click_node(app, "commit-2"); wait(app);
    assert(app.commit.parents == 2 && app.files.items.len == 1 && app.selected == "side.txt" && app.diff.patch.added == 1);
    // Keyboard selection reaches an unrendered root row and retrieves its files.
    key(app, "End"); wait(app);
    assert(app.commit_index == 4 && app.commit.parent.len == 0 && app.files.items.len == 7);
    filter(app, "literal[1].txt"); assert(app.diff.patch.added == 2);
    click(app, "content-mode"); wait(app);
    assert(app.shown_content && app.diff.patch.source == "before\n@@ ordinary text\n" && app.diff.patch.hunks.len == 0);
    assert(app.diff.patch.rows[1].new == 2 && node(app, "copy").text == "Copy file");
    click(app, "copy"); assert(gfx::clipboard() == "before\n@@ ordinary text\n");
    assert(gfx::screenshot(str(screenshot, ".file.png")));
    // Content and diff toggles coalesce through the same request queue.
    app_git_viewer::read_diff(app);
    app_git_viewer::apply_action(app, lab_ui_view::Event<app_git_viewer::Action> { kind: lab_ui_view::ACTIVATE, action: app_git_viewer::Action.Patch, source: 36 });
    assert(app.pending); wait(app); assert(!app.shown_content && app.diff.patch.added == 2);
    click(app, "content-mode"); wait(app);
    filter(app, "binary.bin"); assert(app.diff.patch.binary && app.diff.bytes == 8 && !node(app, "copy").enabled);
    filter(app, "invalid.txt"); assert(app.diff.code != 0 && app.diff.patch.rows.len == 0);
    filter(app, "empty.txt"); assert(app.diff.code == 0 && app.diff.bytes == 0 && app.diff.patch.rows.len == 0);
    filter(app, "large.bin"); assert(app.diff.code != 0 && app.diff.patch.rows.len == 0);
    filter(app, "removed.txt"); assert(app.shown_content && app.diff.patch.source == "deleted\n");
    // A selection during a blocked/unfinished read cancels it, then adopts only the latest commit.
    app_git_viewer::read_diff(app); app_git_viewer::select_commit(app, 2); app_git_viewer::select_commit(app, 3);
    assert(app.pending);
    lab_ui_controls_field::set(app_git_viewer::query(app), "removed.txt");
    app_git_viewer::apply_action(app, lab_ui_view::Event<app_git_viewer::Action> { kind: lab_ui_view::CHANGE, action: app_git_viewer::Action.Search, source: 4 });
    assert(app.queued.commit_files && app.queued.commit.id == app.page.items[3].id); wait(app);
    assert(app.commit_index == 3 && app.commit.id == app.page.items[3].id && app.files.items.len == 3 && app.selected == "removed.txt");
    assert(!app.content && !app.shown_content && app.diff.patch.removed == 1 && !node(app, "content-mode").enabled);
    assert(gfx::screenshot(screenshot));
    filter(app, ""); click(app, "newer"); wait(app); assert(app.page.offset == 0 && app.page.anchor == anchor);
    // Returning to the working tree must not retain file-content rendering mode.
    click(app, "working"); wait(app); assert(!app.history && app.files.items.len == 0 && !app.shown_content);
    app_git_viewer::join(app, worker); assert(!app.client.busy && app.client.token.id == 0);
    assert(gfx::misuse_count() == 0); app_git_viewer::destroy(app); gfx::close();
    print("Git history UI: pages, pointer/keyboard selection, first-parent merges, plain contents, binary/empty/limits, exact copy, cancellation and mode recovery passed");
}
fn main() {
    let argv = args(); assert(argv.len == 4 || argv.len == 5); let value, ok = parse_flt(argv[3]); assert(ok); let scale = value as f32;
    if argv.len == 5 {
        if argv[4] == "history" { history_contract(argv[1], argv[2], scale); }
        else if argv[4] == "search" { search_contract(argv[1], argv[2], scale); }
        else { assert(argv[4] == "linked"); linked_watch_contract(argv[1], scale); } return;
    }
    assert(gfx::open_headless((1180.0 * scale) as i64, (720.0 * scale) as i64));
    var app = app_git_viewer::create(argv[1], lab_ui_render_font::default_font(), lab_ui_render_font::default_mono(), scale);
    let worker = thread_spawn(lab_git_client::worker); app_git_viewer::refresh(app); tick(app); wait(app);
    assert(app.files.items.len == 25 && app.diff.code == lab_git_repository::OK && app.diff.patch.rows.len > 0);
    assert(!has_node(app, "repo") && !has_node(app, "heading") && !app.editing_repo);
    assert(node(app, "repository-name").text == "日本語 repo with spaces");
    assert(app_git_viewer::repository_name("C:\\work\\project\\") == "project");
    assert(app_git_viewer::repository_name("/") == "/" && app_git_viewer::repository_name("C:/") == "C:");
    // Shared palette: focus restoration, disabled entries, pointer execution,
    // background shortcut isolation, and a real staged/working refresh.
    click(app, "search"); modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "K");
    assert(app.palette.modal.opened && app.view.input.focused == 100002);
    assert(gfx::screenshot(str(argv[2], ".commands.png")));
    assert(gfx::inject_text("working")); tick(app); key(app, "Return");
    assert(app.palette.modal.opened && !app.staged && !app.client.busy);
    assert(node(app, "command-description-2").text == "Already showing the working tree");
    key(app, "F5"); assert(!app.client.busy && app.palette.modal.opened);
    key(app, "Escape"); assert(!app.palette.modal.opened && app.view.input.focused == 4 && app_git_viewer::query(app).text.len == 0);
    modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "K"); assert(gfx::inject_text("staged")); tick(app); key(app, "Return"); wait(app);
    assert(app.staged && !app.palette.modal.opened && app.view.top_layer == 0);
    modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "K"); assert(gfx::inject_text("working")); tick(app); click_node(app, "command-2"); wait(app);
    assert(!app.staged && !app.palette.modal.opened && app.diff.patch.rows.len > 0);
    // Close before executing, so the repository editor receives the next input.
    modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "K"); assert(gfx::inject_text("change repository")); tick(app); key(app, "Return");
    assert(app.editing_repo && app.view.input.focused == 1 && !app.palette.modal.opened);
    click(app, "cancel-repo");
    // Opening/cancelling a draft does not request a different repository.
    click(app, "change-repo"); assert(app.editing_repo && has_node(app, "repo") && app.view.input.focused == 1);
    lab_ui_controls_field::set(app_git_viewer::repo_field(app), str(argv[1], "/absent"));
    click(app, "refresh"); wait(app);
    assert(app.editing_repo && app.notice.len == 0 && ends_with(app_git_viewer::repo_field(app).text, "/absent"));
    assert(gfx::screenshot(str(argv[2], ".repository-editor.png")));
    click(app, "cancel-repo"); assert(!app.editing_repo && !has_node(app, "repo") && app.view.input.focused == 14 && !app.client.busy);
    assert(app_git_viewer::repo_field(app).text == app.repo);
    let initial = app_git_viewer::tree_rows(app); let file_row = lab_collections_tree::row_index(initial, lab_collections_tree::index(app.tree, app.selected));
    let row = node(app, str("tree-6-row-", file_row)); let filename = node(app, str("tree-6-label-", file_row)); let status = node(app, str("file-status-", file_row));
    assert(row.text.len == 0 && !filename.centered && filename.rect.x == row.rect.x + 30.0 + initial.items[file_row].depth * 16.0);
    assert(status.rect.x + status.rect.w == row.rect.x + row.rect.w - 12.0 && filename.rect.x + filename.rect.w < status.rect.x);
    // Pointer folder toggle, parent/child keyboard movement and same-path refresh.
    let loaded = app.selected; let loaded_rows = app.diff.patch.rows.len;
    click_node(app, "tree-6-row-0"); assert(app.tree_state.current == "nested/" && app.tree_state.closed.len == 1);
    assert(app.selected == loaded && app.diff.patch.rows.len == loaded_rows && !app.client.busy);
    key(app, "Right"); assert(app.tree_state.closed.len == 0 && app.tree_state.current == "nested/");
    key(app, "Right"); assert(app.tree_state.current == "nested/inner/");
    key(app, "Right"); wait(app); assert(app.tree_state.current == "nested/inner/same.goose" && app.selected == "nested/inner/same.goose");
    key(app, "Left"); assert(app.tree_state.current == "nested/inner/");
    key(app, "Left"); assert(app.tree_state.closed.len == 1);
    key(app, "Left"); assert(app.tree_state.current == "nested/");
    key(app, "Left"); assert(app.tree_state.closed.len == 2);
    key(app, "Return"); assert(app.tree_state.closed.len == 1); key(app, "Space"); assert(app.tree_state.closed.len == 2);
    click(app, "refresh"); wait(app); assert(app.tree_state.closed.len == 2 && app.selected == "nested/inner/same.goose" && app.tree_state.current == "nested/");
    assert(gfx::screenshot(str(argv[2], ".tree-collapsed.png")));
    filter(app, "same.goose"); assert(app_git_viewer::visible(app).len == 2 && app.tree_state.closed.len == 2);
    let matched = app_git_viewer::tree_rows(app); assert(matched.items.len == 5 && matched.filtered);
    assert(gfx::screenshot(str(argv[2], ".tree-filter.png")));
    lab_ui_controls_field::set(app_git_viewer::query(app), ""); app_git_viewer::choose_visible(app); tick(app);
    assert(app.tree_state.closed.len == 2 && !app_git_viewer::tree_rows(app).filtered && app.tree_state.current == "nested/");
    click_node(app, "tree-6-row-0"); key(app, "Right"); key(app, "Right");
    key(app, "End"); wait(app); assert(app.selected == "日本語.txt" && lab_ui_view::scroll_state(app.view, 1).offset > 0.0);
    let previous_path = app.shown; let previous_rows = app.diff.patch.rows.len;
    click(app, "search"); assert(gfx::inject_text("code")); tick(app); assert(app.client.busy);
    assert(app.shown == previous_path && app.diff.patch.rows.len == previous_rows);
    assert(node(app, "refresh").enabled && node(app, "working").enabled && node(app, "staged").enabled && node(app, "copy").enabled);
    assert(node(app, "path").text == lab_git_repository::display(previous_path)); wait(app);
    assert(app.selected == "code.goose" && app_git_viewer::visible(app).len == 1 && app.diff.patch.hunks.len >= 2);
    let first = app.line; click(app, "next"); assert(app.line > first);
    click(app, "previous"); assert(app.line == first);
    click(app, "next"); key(app, "Down"); key(app, "Down"); key(app, "Down"); key(app, "Down"); key(app, "Down");
    assert(lab_ui_view::scroll_state(app.view, 2).offset > 0.0);
    click(app, "right"); assert(app.text.horizontal.offset == 160.0); click(app, "left"); assert(app.text.horizontal.offset == 0.0);
    click(app, "copy"); assert(gfx::clipboard() == app.diff.patch.source && app.diff.patch.source.len > 1600);
    assert(gfx::screenshot(argv[2]));
    // Shared text selection, exact source copy and find through platform events.
    click(app, "code"); modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "Home");
    modified_key(app, "Left Shift", "Right"); modified_key(app, "Left Shift", "Right");
    modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "C"); assert(gfx::clipboard() == "di");
    modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "A"); modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "C"); assert(gfx::clipboard() == app.diff.patch.source);
    // Drag against shared shaped byte positions on the first row.
    modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "Home");
    let text_area = lab_ui_view::bounds(app.view, "code");
    let x = text_area.x + 104.0; let y = text_area.y + app_git_viewer::STRIDE / 2.0;
    let end_x = x + lab_ui_render_font::width(app.canvas.fonts[3].font, "diff");
    gfx::inject_mouse(x * scale, y * scale, gfx::MOUSE_LEFT, true);
    gfx::inject_mouse(end_x * scale, y * scale, 0, false);
    gfx::inject_mouse(end_x * scale, y * scale, gfx::MOUSE_LEFT, false); tick(app);
    modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "C"); assert(gfx::clipboard() == "diff" && !app.text.dragging);
    modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "F"); assert(app.text.find_open && app.view.input.focused == 20);
    assert(gfx::inject_text("value")); tick(app); assert(app.text.matches.len >= 2 && app.text.active == 0);
    let found_at = app.text.cursor; key(app, "F3"); assert(app.text.active == 1 && app.text.cursor > found_at);
    modified_key(app, "Left Shift", "F3"); assert(app.text.active == 0 && app.text.cursor == found_at);
    assert(gfx::screenshot(str(argv[2], ".text-find.png")));
    key(app, "Escape"); assert(!app.text.find_open && app.view.input.focused == 7);
    // Thumb drag reaches real horizontal limits rather than a guessed maximum.
    click(app, "next");
    let cfg = app_git_viewer::text_config(); let track = lab_ui_views_text::bar(lab_ui_view::bounds(app.view, "code"), cfg);
    let thumb = lab_ui_views_text::thumb(app.text, app.document, lab_ui_view::bounds(app.view, "code"), cfg);
    gfx::inject_mouse((thumb.x + thumb.w / 2.0) * scale, (thumb.y + thumb.h / 2.0) * scale, gfx::MOUSE_LEFT, true);
    gfx::inject_mouse((track.x + track.w) * scale, (thumb.y + thumb.h / 2.0) * scale, 0, false);
    gfx::inject_mouse((track.x + track.w) * scale, (thumb.y + thumb.h / 2.0) * scale, gfx::MOUSE_LEFT, false); tick(app);
    assert(app.text.horizontal.offset == lab_ui_layout_scroll::limit(track.w, app.document.width + 2.0) && !app.text.bar_dragging);
    assert(gfx::screenshot(str(argv[2], ".horizontal.png")));
    if app.watch_code != lab_fs_watch::UNSUPPORTED {
        assert(app.watch_code == lab_fs_watch::OK && app.watch.id != 0);
        // Nested external edits refresh the collection without losing the filtered
        // file, horizontal/vertical scroll, selection or current find expression.
        let nested_path = str(argv[1], "/nested/inner/same.goose"); var nested_bytes: u8[>..] = []; assert(read_file(nested_path, nested_bytes));
        let patch_before = copy(app.diff.patch.source); let cursor = app.text.cursor; let anchor = app.text.anchor;
        let horizontal = app.text.horizontal.offset; let vertical = lab_ui_view::scroll_state(app.view, 2).offset;
        let closed = copy(app.tree_state.closed); let previous = app.auto_refreshes;
        assert(write_file_atomic(nested_path, "external nested edit\n")); wait_change(app, previous);
        assert(app.selected == "code.goose" && app.diff.patch.source == patch_before && app_git_viewer::query(app).text == "code");
        assert(app.text.cursor == cursor && app.text.anchor == anchor && app.text.horizontal.offset == horizontal);
        assert(lab_ui_view::scroll_state(app.view, 2).offset == vertical && app.tree_state.closed == closed && app.text.query == "value");
        let code_path = str(argv[1], "/code.goose"); var original: u8[>..] = []; assert(read_file(code_path, original));
        let before_edit = app.auto_refreshes; assert(write_file_atomic(code_path, str(original, "\nlet externally_added = 42;\n"))); wait_change(app, before_edit);
        assert(app.selected == "code.goose" && app.text.cursor == cursor && app.text.anchor == anchor);
        assert(lab_text_strings::contains_folded(app.diff.patch.source, "externally_added"));
        let retained_text = copy(app.text); let retained_line = app.line; let retained_vertical = lab_ui_view::scroll_state(app.view, 2).offset;
        app_git_viewer::jump(app, 1); app.text.horizontal.offset = 0.0; tick(app);
        assert(gfx::screenshot(str(argv[2], ".auto-refresh.png")));
        app.text = retained_text; app.line = retained_line; lab_ui_view::scroll_state(app.view, 2).offset = retained_vertical; tick(app);
        // A paused watch owns no handles; re-enable refreshes missed edits.
        click(app, "auto-refresh"); assert(!app.live && app.watch.id == 0);
        let paused = app.auto_refreshes; assert(write_file_atomic(code_path, original)); frames_for(app, 300000000);
        assert(app.auto_refreshes == paused && lab_text_strings::contains_folded(app.diff.patch.source, "externally_added"));
        click(app, "auto-refresh"); wait_change(app, paused); assert(app.live && app.diff.patch.source == patch_before);
        let restore = app.auto_refreshes; assert(write_file_atomic(nested_path, nested_bytes)); wait_change(app, restore);
        let quiet = app.auto_refreshes; frames_for(app, 300000000); assert(app.auto_refreshes == quiet && !app.client.busy);
    }
    // Switch mode after clearing the filter, then recover the working collection.
    lab_ui_controls_field::set(app_git_viewer::query(app), ""); tick(app); click(app, "staged"); wait(app);
    assert(app.staged && app.files.items.len == 1 && app.selected == "staged.txt" && app.diff.patch.added == 1);
    click(app, "copy"); assert(gfx::clipboard() == app.diff.patch.source);
    assert(gfx::screenshot(str(argv[2], ".staged.png")));
    if app.watch_code == lab_fs_watch::OK {
        // External git add changes only the index; worktree observation alone
        // would not discover the additional staged file.
        let index_path = str(argv[1], "/.git/index"); var index_bytes: u8[>..] = []; assert(read_file(index_path, index_bytes));
        let previous = app.auto_refreshes; let add_args: const u8[:][6] = ["-C", argv[1], "add", "--", "literal[1].txt", "-option.txt"];
        let added = lab_io_process::run("git", add_args, argv[1]); assert(added.code == 0 && added.exit_code == 0); wait_change(app, previous);
        assert(app.staged && app.files.items.len == 3 && app.selected == "staged.txt");
        let restore = app.auto_refreshes; assert(write_file_atomic(index_path, index_bytes)); wait_change(app, restore);
        assert(app.files.items.len == 1 && app.selected == "staged.txt");
    }
    // Mode changes can cancel an outstanding diff; the queued refresh wins.
    app_git_viewer::read_diff(app); assert(app.client.busy && !app.client.refresh);
    assert(app_git_viewer::action(app, lab_ui_view::Event<app_git_viewer::Action> { kind: lab_ui_view::ACTIVATE, action: app_git_viewer::Action.Working, source: 3 }));
    assert((app.pending && app.queued.refresh) && app.pending && !app.queued.staged);
    tick(app); wait(app); assert(!app.staged && app.files.items.len == 25 && !(app.pending && app.queued.refresh));
    // Search remains useful while a previous diff is running; latest intent wins.
    click(app, "search"); assert(gfx::inject_text("code")); tick(app);
    lab_ui_controls_field::set(app_git_viewer::query(app), "日本語.txt"); app_git_viewer::choose_visible(app); tick(app); wait(app);
    assert(app.selected == "日本語.txt" && app.diff.patch.added == 1 && app.diff.patch.removed == 1);
    click(app, "copy"); assert(gfx::clipboard() == app.diff.patch.source);
    assert(gfx::screenshot(str(argv[2], ".japanese.png")));
    // New files use the same virtual list, keyboard navigation and exact copy.
    filter(app, "untracked.txt"); assert(app.selected == "untracked.txt" && app.shown == app.selected && app.diff.untracked);
    assert(app.diff.code == 0 && app.diff.patch.added == 2 && app.diff.patch.removed == 0 && node(app, "file-status-0").text == "?");
    assert(starts_with(node(app, "summary").text, "Untracked · "));
    click(app, "copy"); assert(gfx::clipboard() == app.diff.patch.source && ends_with(gfx::clipboard(), "\\ No newline at end of file\n"));
    assert(gfx::screenshot(str(argv[2], ".untracked.png")));
    filter(app, "newbinary.bin"); assert(app.diff.untracked && app.diff.patch.binary && app.diff.bytes == 4);
    assert(gfx::screenshot(str(argv[2], ".binary.png")));
    filter(app, "oversized.txt"); assert(app.diff.code == lab_git_repository::LIMIT && app.notice.len > 0 && app.diff.patch.rows.len == 0 && !node(app, "copy").enabled);
    assert(gfx::screenshot(str(argv[2], ".limit.png")));
    filter(app, "empty.txt"); assert(app.diff.code == 0 && app.notice.len == 0 && app.diff.bytes == 0 && app.diff.patch.added == 0);
    filter(app, "new [日本語]"); assert(app.selected == "nested/new [日本語].txt" && app.diff.untracked && app.diff.patch.added == 1);
    // A failed repository refresh keeps the last successful collection available.
    let current_path = app.selected; let current_rows = app.diff.patch.rows.len;
    click(app, "change-repo");
    lab_ui_controls_field::set(app_git_viewer::repo_field(app), str(argv[1], "/absent")); tick(app); click(app, "open-repo"); wait(app);
    assert(app.editing_repo && has_node(app, "repo") && app.notice.len > 0 && app.selected == current_path && app.diff.patch.rows.len == current_rows);
    lab_ui_controls_field::set(app_git_viewer::repo_field(app), argv[1]); click(app, "repo"); key(app, "Return"); wait(app);
    assert(app.notice.len == 0 && !app.editing_repo && !has_node(app, "repo") && app.view.input.focused == 14);
    // Empty filters don't start a process or show the previous file under a new title.
    lab_ui_controls_field::set(app_git_viewer::query(app), "no-such-file"); app_git_viewer::choose_visible(app); tick(app); wait(app);
    assert(app.selected.len == 0 && app.diff.patch.rows.len == 0);
    app_git_viewer::join(app, worker); assert(!app.client.busy && app.client.token.id == 0 && app.watch.id == 0 && app.metadata_watch.id == 0 && app.common_watch.id == 0);
    assert(gfx::misuse_count() == 0); app_git_viewer::destroy(app); gfx::close();
    print("Git UI: filtering, untracked text/binary/empty/limits, hunk navigation, scrolling, exact copy, staged/working, latest selection and failure recovery passed");
}

fn wait_search(app: app_git_viewer::App&) {
    let until = clock_ns() + 10000000000;
    while app.search.busy || app.client.busy || app.pending { assert(clock_ns() < until); sleep_ms(2); tick(app); }
}
fn search_contract(repo: const u8[:], screenshot: const u8[:], scale: f32) {
    assert(gfx::open_headless((1180.0 * scale) as i64, (820.0 * scale) as i64));
    var app = app_git_viewer::create(repo, lab_ui_render_font::default_font(), lab_ui_render_font::default_mono(), scale); app.live = false;
    let worker = thread_spawn(lab_git_client::worker); app_git_viewer::refresh(app); tick(app); wait(app);
    assert(gfx::inject_key((if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), true) && gfx::inject_key("Left Shift", true));
    key(app, "F"); assert(gfx::inject_key("Left Shift", false) && gfx::inject_key((if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), false)); tick(app);
    assert(app.project_search && app.view.input.focused == 40 && !has_node(app, "search"));
    lab_ui_controls_field::set(app_git_viewer::search_query(app), "needle"); lab_ui_controls_field::set(app_git_viewer::include_query(app), "**/*.txt"); click(app, "run-search");
    var streaming = false; let until = clock_ns() + 10000000000;
    while app.search.busy || app.client.busy { assert(clock_ns() < until); sleep_ms(2); tick(app); if app.search.busy && app.hits.len > 0 { streaming = true; } }
    assert(streaming && app.hits.len == 75 && app.search_result == 0 && app.shown_worktree && app.shown_content);
    assert(app.diff.patch.source[app.text.anchor..app.text.cursor] == "needle");
    click_node(app, "hit-0"); key(app, "End"); wait_search(app); assert(app.hit_index == 74);
    assert(app.diff.patch.source[app.text.anchor..app.text.cursor] == "needle" && lab_ui_view::scroll_state(app.view, 4).offset > 0.0);
    key(app, "Home"); wait_search(app); assert(app.hit_index == 0);
    // Replacement requests coalesce while the old worker is producing pages.
    lab_ui_controls_field::set(app_git_viewer::search_query(app), "needle"); click(app, "run-search");
    lab_ui_controls_field::set(app_git_viewer::search_query(app), "aba"); click(app, "run-search"); wait_search(app);
    assert(app.hits.len == 2 && app.search_query == "aba" && app.hits[0].path == "readme.txt");
    assert(app.hits[0].start == 18 && app.hits[1].start == 20);
    click_node(app, "hit-1"); wait_search(app); assert(app.text.anchor == 20 && app.text.cursor == 23);
    app.view.input.focused = 7; modified_key(app, (if lab_ui_input_shortcuts::macos() { "Left GUI" } else { "Left Ctrl" }), "C"); assert(gfx::clipboard() == "aba");
    lab_ui_controls_field::set(app_git_viewer::include_query(app), "***"); click(app, "run-search"); assert(!app.search.busy && app.notice.len > 0 && app.hits.len == 2);
    lab_ui_controls_field::set(app_git_viewer::include_query(app), "readme.txt"); lab_ui_controls_field::set(app_git_viewer::search_query(app), "needle");
    click(app, "ignore-case"); click(app, "run-search"); wait_search(app); assert(app.hits.len == 3 && app.ignore_case);
    click_node(app, "hit-2"); wait_search(app); assert(app.diff.patch.source[app.text.anchor..app.text.cursor] == "NEEDLE");
    click(app, "copy"); assert(gfx::clipboard() == "日本語 needle\r\nababa needle\nNEEDLE\n");
    lab_ui_controls_field::set(app_git_viewer::search_query(app), "no-such-phrase"); click(app, "run-search"); wait_search(app); assert(app.hits.len == 0 && app.shown.len == 0 && app.diff.patch.rows.len == 0);
    lab_ui_controls_field::set(app_git_viewer::search_query(app), "needle"); lab_ui_controls_field::set(app_git_viewer::include_query(app), "**/*.txt"); click(app, "run-search"); click(app, "cancel-search"); wait_search(app);
    assert(app.search_result == lab_fs_search::CANCELLED);
    lab_ui_controls_field::set(app_git_viewer::include_query(app), "readme.txt"); click(app, "run-search"); wait_search(app); click_node(app, "hit-0"); wait_search(app);
    assert(app.hits.len == 3 && app.text.anchor == 10 && app.text.cursor == 16 && gfx::screenshot(screenshot));
    click(app, "working"); wait(app); assert(!app.project_search && !app.history && !app.shown_worktree && has_node(app, "search"));
    app_git_viewer::join(app, worker); app_git_viewer::destroy(app); assert(gfx::misuse_count() == 0); gfx::close();
    print("Find in files UI: live results, result keyboard/pointer selection, exact copy, latest-query wins, validation, cancellation and return to changes passed");
}
