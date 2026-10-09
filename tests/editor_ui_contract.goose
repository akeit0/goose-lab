import std;
import os;
import gfx;
import lab.ui.input.shortcuts;
import lab.ui.render.font;
import lab.ui.render.text_layout;
import lab.ui.view;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.ui.views.text;
import workbench.editor.single;
import lab.ui.views.editor;
import lab.document.model;
import lab.document.file;
import lab.document.piece_tree;
import lab.ui.input.composition;
import lab.document.close;
fn main() { let argv = args(); assert(argv.len == 4); let value, ok = parse_flt(argv[3]); assert(ok); editor_contract(argv[1], argv[2], value as f32); }

fn editor_tick(app: app_editor_single::App&) { assert(gfx::frame()); app_editor_single::frame(app); }
fn editor_key(app: app_editor_single::App&, name: const u8[:], mods: i64 = 0) {
    if (mods & gfx::MOD_CTRL) != 0 { assert(gfx::inject_key("Left Ctrl", true)); } if (mods & gfx::MOD_SHIFT) != 0 { assert(gfx::inject_key("Left Shift", true)); }
    if (mods & gfx::MOD_GUI) != 0 { assert(gfx::inject_key("Left GUI", true)); }
    assert(gfx::inject_key(name, true) && gfx::inject_key(name, false));
    if (mods & gfx::MOD_SHIFT) != 0 { assert(gfx::inject_key("Left Shift", false)); } if (mods & gfx::MOD_CTRL) != 0 { assert(gfx::inject_key("Left Ctrl", false)); }
    if (mods & gfx::MOD_GUI) != 0 { assert(gfx::inject_key("Left GUI", false)); } editor_tick(app);
}
fn editor_wait(app: app_editor_single::App&) { let until = clock_ns() + 5000000000; while lab_document_file::busy(app.file) { assert(clock_ns() < until); sleep_ms(2); editor_tick(app); } }
fn editor_disk_idle(app: app_editor_single::App&) { let until = clock_ns() + 5000000000; while app.workspace.reading.id != 0 { assert(clock_ns() < until); sleep_ms(2); editor_tick(app); } }
fn editor_click(app: app_editor_single::App&, name: const u8[:]) {
    for n in app.view.nodes { if n.name == name { let r = n.rect; gfx::inject_mouse((r.x + r.w / 2.0) * app.scale, (r.y + r.h / 2.0) * app.scale, gfx::MOUSE_LEFT, true); gfx::inject_mouse((r.x + r.w / 2.0) * app.scale, (r.y + r.h / 2.0) * app.scale, gfx::MOUSE_LEFT, false); editor_tick(app); return; } } assert(false);
}
fn editor_contract(path: const u8[:], screenshot: const u8[:], scale: f32) {
    let original = "first 日本語\r\nsecond\r\n"; assert(write_file_atomic(path, original));
    assert(gfx::open_headless((1180.0 * scale) as i64, (820.0 * scale) as i64)); var app = app_editor_single::create(path, scale); editor_tick(app); editor_wait(app);
    assert(app.file.code == 0 && lab_document_model::contents(app.file.document) == original && app.view.input.focused == 7);
    // Preedit is a virtual replacement, never a document edit or dirty/undo entry.
    assert(lab_document_model::select(app.file.document,15,6)); let revision=app.file.document.revision;
    assert(gfx::inject_editing("にほんご",2,1)); editor_tick(app);
    assert(lab_document_model::contents(app.file.document)==original && app.file.document.revision==revision && !lab_document_model::dirty(app.file.document));
    assert(app.editor.composition.cursor==6 && app.editor.composition.end==9 && app.editor.preview.id!=0);
    assert(gfx::screenshot(str(screenshot,".ime.png"))); let preview_bytes=lab_ui_render_text_layout::live_bytes();
    let preview_id=app.editor.preview.id; assert(gfx::inject_editing("にほんご",1,2)); editor_tick(app);
    assert(app.editor.preview.id==preview_id && app.editor.composition.cursor==3 && app.editor.composition.end==9);
    editor_key(app,"Return"); editor_key(app,"Tab"); editor_key(app,"S",lab_ui_input_shortcuts::primary());
    assert(app.view.input.focused==7 && lab_document_model::contents(app.file.document)==original && app.file.document.history.len==0);
    for i in 4 { editor_tick(app); assert(lab_ui_render_text_layout::live_bytes()==preview_bytes); }
    assert(gfx::inject_editing("",0,0) && gfx::inject_text("日本")); editor_tick(app);
    assert(lab_document_model::contents(app.file.document)=="first 日本\r\nsecond\r\n" && app.file.document.history.len==1 && app.editor.preview.id==0);
    editor_key(app,"Z",lab_ui_input_shortcuts::primary()); assert(lab_document_model::contents(app.file.document)==original);
    editor_key(app,"End",lab_ui_input_shortcuts::primary()); assert(gfx::inject_editing("にゅうりょく",6,0)); editor_tick(app);
    assert(gfx::inject_text("入力")); editor_tick(app); assert(gfx::inject_text("a")); editor_tick(app);
    assert(lab_document_model::contents(app.file.document)==str(original,"入力a"));
    editor_key(app,"Z",lab_ui_input_shortcuts::primary()); assert(lab_document_model::contents(app.file.document)==str(original,"入力"));
    editor_key(app,"Z",lab_ui_input_shortcuts::primary()); assert(lab_document_model::contents(app.file.document)==original);
    assert(gfx::inject_editing("取消",-1,-1)); editor_tick(app); editor_key(app,"Escape");
    assert(!app.editor.composition.pending && lab_document_model::contents(app.file.document)==original);
    // Moving focus cancels preedit and drops a commit already collected in that batch.
    assert(gfx::inject_editing("取消",0,2)); editor_tick(app);
    for n in app.view.nodes { if n.name=="change" { let r=n.rect; gfx::inject_mouse((r.x+4.0)*scale,(r.y+4.0)*scale,gfx::MOUSE_LEFT,true); gfx::inject_mouse((r.x+4.0)*scale,(r.y+4.0)*scale,gfx::MOUSE_LEFT,false); } }
    assert(gfx::inject_text("must not leak")); editor_tick(app);
    assert(app.editing_path && app.view.input.focused==1 && lab_ui_view::field_state(app.view,1).text==app.file.path && lab_document_model::contents(app.file.document)==original && !app.editor.composition.pending);
    assert(gfx::inject_editing("仮",0,1)); editor_tick(app); editor_key(app,"Escape");
    assert(app.editing_path && !lab_ui_view::field_state(app.view,1).composition.pending);
    editor_click(app,"cancel-path"); assert(!app.editing_path && app.view.input.focused==7);
    assert(gfx::inject_editing("focus",0,5)); editor_tick(app); gfx::inject_focus(false); editor_tick(app);
    assert(!app.editor.composition.pending && lab_document_model::contents(app.file.document)==original); gfx::inject_focus(true); editor_tick(app); app.view.input.focused=7;
    editor_key(app, "End", lab_ui_input_shortcuts::primary()); assert(gfx::inject_text("追加")); editor_tick(app); assert(app.file.document.history.len == 1 && lab_document_model::dirty(app.file.document));
    editor_key(app, "Return"); editor_key(app, "Tab"); assert(app.view.input.focused == 7);
    assert(lab_document_model::contents(app.file.document) == str(original, "追加\r\n\t"));
    editor_key(app, "Z", lab_ui_input_shortcuts::primary()); editor_key(app, "Z", lab_ui_input_shortcuts::primary()); editor_key(app, "Z", lab_ui_input_shortcuts::primary());
    assert(!lab_document_model::dirty(app.file.document) && lab_document_model::contents(app.file.document) == original);
    editor_key(app, "Y", lab_ui_input_shortcuts::primary()); assert(lab_document_model::contents(app.file.document) == str(original, "追加"));
    editor_key(app, "Z", lab_ui_input_shortcuts::primary()); editor_key(app, "Home", lab_ui_input_shortcuts::primary()); editor_key(app, "End", gfx::MOD_SHIFT); editor_key(app, "Backspace");
    assert(lab_document_model::contents(app.file.document) == "\r\nsecond\r\n"); editor_key(app, "Z", lab_ui_input_shortcuts::primary()); assert(lab_document_model::contents(app.file.document) == original);
    editor_key(app, "C", lab_ui_input_shortcuts::primary()); assert(gfx::clipboard() == "first 日本語");
    assert(gfx::set_clipboard("貼り付け\n")); editor_key(app, "V", lab_ui_input_shortcuts::primary()); assert(lab_document_model::contents(app.file.document) == "貼り付け\n\r\nsecond\r\n"); editor_key(app, "Z", lab_ui_input_shortcuts::primary());
    editor_key(app, "X", lab_ui_input_shortcuts::primary()); assert(gfx::clipboard() == "first 日本語" && lab_document_model::contents(app.file.document) == "\r\nsecond\r\n"); editor_key(app, "Z", lab_ui_input_shortcuts::primary());
    // Mouse caret uses shaping of the complete visible line; exact bytes stay in the model.
    let area = lab_ui_view::bounds(app.view, "code"); let inside = lab_ui_views_text::inside(area, app_editor_single::config()); let line = lab_ui_views_editor::line(app.editor, app.file.document, 0, app.canvas.fonts[1].font);
    let x = (inside.x + lab_ui_render_text_layout::position(line.layout, 6)) * scale; let y = (inside.y + 12.0) * scale;
    gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, true); gfx::inject_mouse(x, y, gfx::MOUSE_LEFT, false); editor_tick(app); assert(app.file.document.selection.cursor == 6);
    assert(gfx::inject_text("edited ")); editor_tick(app); assert(lab_document_model::contents(app.file.document) == "first edited 日本語\r\nsecond\r\n");
    editor_key(app, "S", lab_ui_input_shortcuts::primary()); editor_wait(app); assert(app.file.code == 0 && !lab_document_model::dirty(app.file.document));
    var saved: u8[>..] = []; assert(read_file(path, saved) && saved == "first edited 日本語\r\nsecond\r\n");
    editor_key(app, "End", lab_ui_input_shortcuts::primary()); assert(gfx::inject_text("local")); editor_tick(app);
    editor_disk_idle(app); assert(write_file_atomic(path, "external\n")); editor_key(app, "S", lab_ui_input_shortcuts::primary()); editor_wait(app); assert(app.file.code == lab_document_file::CONFLICT && lab_document_model::dirty(app.file.document));
    editor_click(app, "change"); lab_ui_controls_field::set(lab_ui_view::field_state(app.view, 1), path); editor_click(app, "open"); assert(app.modal.opened);
    editor_key(app, "Escape"); assert(!app.modal.opened && lab_document_model::dirty(app.file.document));
    editor_click(app, "open"); assert(app.modal.opened); editor_click(app, "discard-open"); editor_wait(app); assert(!app.modal.opened && !lab_document_model::dirty(app.file.document) && lab_document_model::contents(app.file.document) == "external\n");
    editor_disk_idle(app); assert(write_file_atomic(path, original) && lab_document_file::open(app.file, path)); editor_wait(app);
    app.view.input.focused = 7; editor_key(app, "End", lab_ui_input_shortcuts::primary()); editor_key(app, "Backspace"); assert(lab_document_model::contents(app.file.document) == "first 日本語\r\nsecond");
    editor_key(app, "Z", lab_ui_input_shortcuts::primary()); assert(app.file.document.selection.cursor == original.len && lab_document_model::contents(app.file.document) == original);
    let fresh = str(path, ".new"); assert(lab_document_file::open(app.file, fresh)); editor_wait(app); assert(!app.file.exists);
    app.view.input.focused = 7; assert(gfx::inject_text("new 日本語")); editor_tick(app); editor_click(app, "change"); lab_ui_controls_field::set(lab_ui_view::field_state(app.view, 1), fresh); editor_click(app, "open"); editor_wait(app);
    assert(app.file.code == 0 && app.file.exists && !lab_document_model::dirty(app.file.document)); var created: u8[>..] = []; assert(read_file(fresh, created) && created == "new 日本語" && delete_file(fresh));
    assert(lab_document_file::open(app.file, path)); editor_wait(app); assert(lab_document_model::contents(app.file.document) == original);
    let cached_bytes=lab_ui_render_text_layout::live_bytes(); assert(cached_bytes>0); for i in 12 { editor_tick(app); assert(lab_ui_render_text_layout::live_bytes()==cached_bytes); }
    emoji_editor_contract(app,original,screenshot);
    close_contract(app,path,original,screenshot);
    assert(gfx::screenshot(screenshot)); app_editor_single::destroy(app); assert(lab_ui_render_text_layout::live_bytes()==0);
    untitled_close_contract(str(path,".close-new"),scale);
    assert(gfx::misuse_count() == 0); gfx::close();
    print("Text editor: Unicode/IME editing, undo, atomic saves, conflicts and save/discard/cancel close including untitled and pending edits passed");
}

fn emoji_editor_contract(app: app_editor_single::App&, original: const u8[:], screenshot: const u8[:]) {
    app.view.input.focused=7; editor_key(app,"End",lab_ui_input_shortcuts::primary());
    let text="A👍🏽👨‍👩‍👧‍👦🇯🇵B"; assert(gfx::inject_text(text)); editor_tick(app);
    editor_key(app,"Left"); editor_key(app,"Left",gfx::MOD_SHIFT);
    assert(app.file.document.selection.cursor==original.len+text.len-9 && app.file.document.selection.anchor==original.len+text.len-1);
    editor_key(app,"C",lab_ui_input_shortcuts::primary()); assert(gfx::clipboard()=="🇯🇵"); editor_key(app,"Backspace");
    assert(lab_document_model::contents(app.file.document)==str(original,"A👍🏽👨‍👩‍👧‍👦B"));
    editor_key(app,"Z",lab_ui_input_shortcuts::primary()); assert(lab_document_model::contents(app.file.document)==str(original,text));
    assert(gfx::inject_editing("😀",1,0)); editor_tick(app); assert(lab_document_model::contents(app.file.document)==str(original,text));
    assert(gfx::screenshot(str(screenshot,".emoji-ime.png")));
    assert(gfx::inject_editing("",0,0) && gfx::inject_text("😀")); editor_tick(app);
    assert(lab_document_model::contents(app.file.document)==str(original,"A👍🏽👨‍👩‍👧‍👦😀B"));
    editor_key(app,"Z",lab_ui_input_shortcuts::primary()); editor_key(app,"Z",lab_ui_input_shortcuts::primary());
    assert(lab_document_model::contents(app.file.document)==original && !lab_document_model::dirty(app.file.document));
}
fn close_contract(app: app_editor_single::App&, path: const u8[:], original: const u8[:], screenshot: const u8[:]) {
    assert(gfx::inject_close()); editor_tick(app); assert(app.closing.ready && !app.close_modal.opened);
    app.closing=lab_document_close::State {}; app.view.input.focused=7;
    // Text before the native close in the same queue must be included in the decision.
    assert(gfx::inject_text("unsaved") && gfx::inject_close()); editor_tick(app);
    let local=lab_document_model::contents(app.file.document); assert(app.closing.prompt && app.close_modal.opened && !app.closing.ready && lab_document_model::dirty(app.file.document));
    assert(gfx::screenshot(str(screenshot,".close.png")));
    assert(gfx::inject_close() && gfx::inject_close()); editor_tick(app); assert(app.closing.prompt);
    editor_key(app,"Escape"); assert(!app.close_modal.opened && !app.closing.ready && lab_document_model::contents(app.file.document)==local);
    assert(gfx::inject_close()); editor_tick(app); editor_click(app,"close-discard");
    assert(app.closing.ready && lab_document_model::contents(app.file.document)==local); var disk: u8[>..]=[]; assert(read_file(path,disk) && disk==original);
    app.closing=lab_document_close::State {}; assert(lab_document_model::undo(app.file.document)); app.view.input.focused=7;
    assert(gfx::inject_text("save-close") && gfx::inject_close()); editor_tick(app); editor_click(app,"close-save");
    assert(app.closing.saving && !app.closing.ready); editor_wait(app);
    assert(app.closing.ready && !lab_document_model::dirty(app.file.document)); disk.resize(0); assert(read_file(path,disk) && disk==lab_document_model::contents(app.file.document));
    app.closing=lab_document_close::State {}; assert(lab_document_file::open(app.file,path)); editor_wait(app); app.view.input.focused=7;
    assert(gfx::inject_text("local")); editor_tick(app); let conflict=lab_document_model::contents(app.file.document);
    editor_disk_idle(app);
    assert(write_file_atomic(path,"external\n") && gfx::inject_close()); editor_tick(app); editor_click(app,"close-save"); editor_wait(app);
    assert(app.file.code==lab_document_file::CONFLICT && app.closing.prompt && app.close_modal.opened && !app.closing.ready && lab_document_model::contents(app.file.document)==conflict);
    disk.resize(0); assert(read_file(path,disk) && disk=="external\n"); editor_click(app,"close-cancel");
    assert(!app.closing.prompt && !app.closing.ready && lab_document_model::dirty(app.file.document));
    editor_disk_idle(app); assert(write_file_atomic(path,original) && lab_document_file::open(app.file,path,true)); editor_wait(app); app.view.input.focused=7;
    assert(gfx::inject_text("pending")); editor_tick(app); assert(lab_document_file::save(app.file));
    assert(gfx::inject_close()); editor_tick(app); assert(!app.closing.ready); editor_wait(app);
    assert(app.closing.ready && !lab_document_model::dirty(app.file.document));
    app.closing=lab_document_close::State {}; app.view.input.focused=7;
    assert(gfx::inject_text("older") && gfx::inject_close()); editor_tick(app); editor_click(app,"close-save");
    let code,changed=lab_document_model::insert(app.file.document,"newer"); assert(code==0 && changed); let latest=lab_document_model::contents(app.file.document); editor_wait(app);
    assert(app.closing.prompt && !app.closing.ready && app.file.code==lab_document_file::DIRTY && lab_document_model::contents(app.file.document)==latest);
    editor_click(app,"close-cancel");
    editor_disk_idle(app); assert(write_file_atomic(path,original) && lab_document_file::open(app.file,path,true)); editor_wait(app);
}
fn untitled_close_contract(path: const u8[:], scale: f32) {
    var app=app_editor_single::create("",scale); editor_tick(app); app.view.input.focused=7;
    assert(gfx::inject_text("new 日本語") && gfx::inject_close()); editor_tick(app); assert(app.close_modal.opened && app.file.path.len==0);
    editor_click(app,"close-save"); assert(app.closing.prompt && app.file.notice=="Enter a file path to save");
    lab_ui_controls_field::set(lab_ui_view::field_state(app.view,2005),str(path,"/missing/child.txt")); editor_click(app,"close-save"); editor_wait(app);
    assert(app.closing.prompt && !app.closing.ready && lab_document_model::dirty(app.file.document));
    lab_ui_controls_field::set(lab_ui_view::field_state(app.view,2005),path); editor_click(app,"close-save"); editor_wait(app);
    assert(app.closing.ready && !lab_document_model::dirty(app.file.document)); var disk: u8[>..]=[]; assert(read_file(path,disk) && disk=="new 日本語" && delete_file(path));
    app_editor_single::destroy(app); assert(lab_ui_render_text_layout::live_bytes()==0);
}
