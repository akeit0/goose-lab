// Practical single-document sample using the reusable document/file/view APIs.
namespace app_editor_single;
import std;
import gfx;
import lab.ui.render.font;
import lab.ui.render.scene;
import lab.ui.layout.engine;
import lab.ui.view;
import lab.ui.controls.field;
import lab.ui.layout.scroll;
import lab.ui.geometry;
import lab.ui.controls.components;
import lab.document.model;
import lab.document.file;
import lab.document.workspace;
import lab.ui.views.editor;
import lab.ui.views.text;
import lab.document.piece_tree;
import lab.text.strings;
import lab.ui.overlays.modal;
import lab.document.close;
import workbench.navigation;
enum Action { Input, Save, Undo, Redo, Open, Change, Cancel, Compact, Discard, Keep, Dismiss, Reload, Files, ProjectSearch, RunSearch, CancelSearch, SelectFile, SelectHit, Refresh, CloseSave, CloseDiscard, CloseCancel, WorkbenchEditor, WorkbenchChanges }
struct App { canvas: lab_ui_render_scene::Canvas, view: lab_ui_view::View<Action> = lab_ui_view::View<Action> {}, editor: lab_ui_views_editor::State = lab_ui_views_editor::State {},
    workspace: lab_document_workspace::State = lab_document_workspace::State {}, reveal_pending: bool = false, seen_generation: u64 = 0, seen_reveal: u64 = 0,
    scale: f32 = 1.0, editing_path: bool = false,  modal: lab_ui_overlays_modal::State = lab_ui_overlays_modal::State {},
    closing: lab_document_close::State = lab_document_close::State {}, close_modal: lab_ui_overlays_modal::State = lab_ui_overlays_modal::State {},
    file: lab_document_file::State = lab_document_file::State {} }
fn config() -> lab_ui_views_text::Config<Action> { lab_ui_views_text::Config<Action> { id: 7, scroll_id: 2, bar_id: 17, action: Action.Input, font: 1, stride: 24.0, gutter: 64.0 } }
fn create(path: const u8[:], scale: f32 = 1.0) -> App {
    gfx::defer_close(true);
    var app = App { canvas: lab_ui_render_scene::create(lab_ui_render_font::default_font(), scale), scale: scale }; assert(lab_ui_render_scene::add_font(app.canvas, lab_ui_render_font::default_mono(), 14.0) == 1);
    app.view.layout = lab_ui_layout_engine::create(app.canvas.fonts[0].font); app.view.defer_overlays = true;
    app.file = lab_document_file::create(); assert(app.file.code == 0); lab_ui_controls_field::set(lab_ui_view::field_state(app.view, 1), path);
    if path.len > 0 { lab_document_file::open(app.file, path); } else { app.editing_path = true; } app.view.input.focused = 7; app
}
fn poll(app: App&) {
    let was_busy = lab_document_file::busy(app.file);
    lab_document_workspace::poll(app.workspace, app.file);
    if was_busy && !lab_document_file::busy(app.file) && app.view.input.focused == 0 { app.view.input.focused = 7; }
    if app.seen_generation != app.file.generation { app.seen_generation = app.file.generation; lab_ui_views_editor::clear(app.editor); app.editor = lab_ui_views_editor::State {}; app.editing_path = false; app.view.input.focused = 7; lab_ui_view::scroll_state(app.view, 2).offset = 0.0; }
    if app.seen_reveal != app.workspace.reveal { app.seen_reveal = app.workspace.reveal; app.reveal_pending = true; app.view.input.focused = 7; }
    if app.workspace.prompt && !app.modal.opened { lab_ui_overlays_modal::open(app.view, app.modal, 1002); }
    if !app.workspace.prompt && app.modal.opened { lab_ui_overlays_modal::close(app.view, app.modal); }
    lab_document_close::poll(app.closing,app.file,app.workspace.saving || app.workspace.opening); sync_close_modal(app);
}
fn sync_close_modal(app: App&) {
    if app.closing.prompt && !app.close_modal.opened {
        if !app.file.exists { lab_ui_controls_field::set(lab_ui_view::field_state(app.view,2005),app.file.path); }
        lab_ui_overlays_modal::open(app.view,app.close_modal,2002);
    }
    if !app.closing.prompt && app.close_modal.opened { lab_ui_overlays_modal::close(app.view,app.close_modal); }
}
fn request_close(app: App&) {
    if app.workspace.prompt { lab_document_workspace::choose(app.workspace,app.file,lab_document_workspace::Choice.Keep); }
    lab_ui_overlays_modal::close(app.view,app.modal);
    lab_document_close::request(app.closing,app.file);
    lab_document_close::poll(app.closing,app.file,app.workspace.saving || app.workspace.opening); sync_close_modal(app);
}
fn basename(path: const u8[:]) -> u8[>..] { var start: i64 = 0; for i in path.len { if path[i] == '/' || path[i] == '\\' { start = i + 1; } } lab_text_strings::display_bytes(path[start..], 260) }
fn build(app: App&, width: f32, height: f32, project: bool = false, project_name: const u8[:] = []) {
    let theme = lab_ui_controls_components::Theme {}; let busy = lab_document_file::busy(app.file) || app.closing.pending || app.closing.saving || app.closing.ready; let d .= app.file.document;
    lab_ui_view::begin(app.view, width, height); lab_ui_view::shortcut(app.view, "S", gfx::MOD_CTRL, Action.Save); lab_ui_view::shortcut(app.view, "O", gfx::MOD_CTRL, Action.Change);
    lab_ui_view::box(app.view, "root", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), padding: lab_ui_layout_engine::padding(16), gap: 8 }) {
        if project_name.len > 0 { app_workbench_navigation::header(app.view, project_name, false, Action.WorkbenchEditor, Action.WorkbenchChanges, Action.WorkbenchEditor); }
        lab_ui_view::box(app.view, "header", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
            let name: u8[>..] = if app.file.path.len > 0 { basename(app.file.path) } else { "Untitled" };
            lab_ui_view::label(app.view, "file-name", str(if lab_document_model::dirty(d) { "● " } else { "" }, name), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
            lab_ui_view::button(app.view, "change", 3, Action.Change, if app.file.exists { "Open…" } else { "Save as…" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(76.0), height: lab_ui_layout_engine::grow() }, false, !busy);
            lab_ui_view::button(app.view, "undo", 8, Action.Undo, "Undo", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(64.0), height: lab_ui_layout_engine::grow() }, false, !busy && d.at > 0);
            lab_ui_view::button(app.view, "redo", 9, Action.Redo, "Redo", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(64.0), height: lab_ui_layout_engine::grow() }, false, !busy && d.at < d.history.len);
            lab_ui_view::button(app.view, "save", 2, Action.Save, "Save", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(64.0), height: lab_ui_layout_engine::grow() }, true, !busy && app.file.path.len > 0 && (lab_document_model::dirty(d) || !app.file.exists));
        };
        if app.editing_path {
            lab_ui_view::box(app.view, "open-row", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
                lab_ui_view::field(app.view, "path-input", 1, Action.Open, if app.file.exists { "File path…" } else { "File to create…" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, !busy, 512);
                lab_ui_view::button(app.view, "open", 4, Action.Open, if app.file.exists { "Open" } else { "Create" }, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(72.0), height: lab_ui_layout_engine::grow() }, false, !busy);
                lab_ui_view::button(app.view, "cancel-path", 5, Action.Cancel, "Cancel", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(76.0), height: lab_ui_layout_engine::grow() }, false, !busy);
            };
        }
        let status: u8[>..] = if busy { if app.file.phase == lab_document_file::LOADING { "Reading file…" } else { "Saving · Checking disk contents before publication…" } } else if app.editor.copy_failed { "Unable to copy selection" } else if app.editor.code == lab_ui_views_editor::LAYOUT_LIMIT { "Line shaping limit reached" } else if app.editor.code != 0 { lab_document_model::message(app.editor.code) } else { lab_document_file::message(app.file) };
        lab_ui_view::label(app.view, "status", status, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(20.0) }, 0, theme.muted);
        if app.workspace.disk != lab_document_workspace::SAME {
            lab_ui_view::box(app.view, "disk-row", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(28.0), gap: 8 }) {
                lab_ui_view::label(app.view, "disk-status", lab_document_workspace::message(app.workspace), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, 0, theme.muted);
                lab_ui_view::button(app.view, "reload", 10, Action.Reload, "Reload", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(76.0), height: lab_ui_layout_engine::grow() }, false, !busy);
            };
        }
        lab_ui_view::box(app.view, "workspace-body", lab_ui_layout_engine::Config { direction: if width >= 900.0 { lab_ui_layout_engine::ROW } else { lab_ui_layout_engine::COLUMN }, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow(), gap: 12 }) {
            if project { lab_ui_view::leaf(app.view, "project", lab_ui_layout_engine::Config { width: if width >= 900.0 { lab_ui_layout_engine::fixed(292.0) } else { lab_ui_layout_engine::grow() }, height: if width >= 900.0 { lab_ui_layout_engine::grow() } else { lab_ui_layout_engine::fixed(228.0) } }); }
            lab_ui_view::leaf(app.view, "code", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
        };
        lab_ui_view::box(app.view, "footer", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(26.0), gap: 8 }) {
            lab_ui_view::label(app.view, "position", str("Ln ", lab_document_piece_tree::line_at(d.tree, d.selection.cursor) + 1, " · ", lab_document_model::size(d), " bytes · ", if d.newline == "\r\n" { "CRLF" } else { "LF" }, if lab_document_model::dirty(d) { " · Unsaved" } else { " · UTF-8" }), lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() }, 0, theme.muted);
            lab_ui_view::button(app.view, "compact", 6, Action.Compact, "Clear undo", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(104.0), height: lab_ui_layout_engine::grow() }, false, !busy && d.history.len > 0);
        };
    };
    lab_ui_view::solve(app.view); lab_ui_views_editor::at_view(app.view, app.canvas, app.editor, d, lab_ui_view::bounds(app.view, "code"), config(), !busy);
    if app.reveal_pending { lab_ui_views_editor::reveal(app.view, app.canvas, app.editor, d, lab_ui_view::bounds(app.view, "code"), config()); app.reveal_pending = false; }
    if app.modal.opened {
        let panel = lab_ui_geometry::rect(max(8.0, (width - 500.0) / 2.0), max(8.0, (height - 170.0) / 2.0), min(500.0, width - 16.0), 170.0);
        lab_ui_overlays_modal::at_panel(app.view, 1000, 1002, panel, Action.Dismiss) {
            lab_ui_view::shortcut(app.view, "Escape", 0, Action.Keep);
            lab_ui_view::at_label(app.view, "discard-title", lab_ui_geometry::rect(panel.x + 16.0, panel.y + 14.0, panel.w - 32.0, 28.0), "Keep your unsaved changes?");
            lab_ui_view::at_label(app.view, "discard-detail", lab_ui_geometry::rect(panel.x + 16.0, panel.y + 50.0, panel.w - 32.0, 26.0), if app.workspace.intent.reload { "Reload discards local edits and clears undo history." } else { "Save and continue, or discard and open the selected file." }, 0, theme.muted);
            lab_ui_view::at_button(app.view, "keep", 1002, Action.Keep, lab_ui_geometry::rect(panel.x + 16.0, panel.y + 106.0, 110.0, 34.0), "Keep editing");
            lab_ui_view::at_button(app.view, "save-before-open", 1003, Action.Save, lab_ui_geometry::rect(panel.x + 138.0, panel.y + 106.0, 114.0, 34.0), if app.workspace.intent.reload { "Save & reload" } else { "Save & open" }, app.file.path.len > 0);
            lab_ui_view::at_button(app.view, "discard-open", 1004, Action.Discard, lab_ui_geometry::rect(panel.x + panel.w - 158.0, panel.y + 106.0, 142.0, 34.0), if app.workspace.intent.reload { "Discard & reload" } else { "Discard & open" });
        };
    }
    if app.close_modal.opened { close_panel(app,width,height); }
}
fn close_panel(app: App&, width: f32, height: f32) {
    let new_file=!app.file.exists; let h: f32=if new_file { 242.0 } else { 194.0 };
    let panel=lab_ui_geometry::rect(max(8.0,(width-500.0)/2.0),max(8.0,(height-h)/2.0),min(500.0,width-16.0),h);
    lab_ui_overlays_modal::at_panel(app.view,2000,2002,panel,Action.CloseCancel) {
        lab_ui_view::shortcut(app.view,"Escape",0,Action.CloseCancel); lab_ui_view::shortcut(app.view,"S",gfx::MOD_CTRL,Action.CloseSave);
        lab_ui_view::at_label(app.view,"close-title",lab_ui_geometry::rect(panel.x+16.0,panel.y+14.0,panel.w-32.0,28.0),"Save changes before closing?");
        lab_ui_view::at_label(app.view,"close-detail",lab_ui_geometry::rect(panel.x+16.0,panel.y+50.0,panel.w-32.0,26.0),"Discard closes without saving. Cancel keeps editing.",0,lab_ui_controls_components::Theme {}.muted);
        if new_file { lab_ui_view::at_field(app.view,"close-path",2005,Action.CloseSave,lab_ui_geometry::rect(panel.x+16.0,panel.y+86.0,panel.w-32.0,32.0),"File path…",true,512); }
        lab_ui_view::at_label(app.view,"close-status",lab_ui_geometry::rect(panel.x+16.0,panel.y+h-90.0,panel.w-32.0,24.0),if app.file.code!=0 || app.file.notice=="Enter a file path to save" { lab_document_file::message(app.file) } else { "" },0,lab_ui_controls_components::Theme {}.muted);
        let w=(panel.w-48.0)/3.0; let y=panel.y+h-50.0;
        lab_ui_view::at_button(app.view,"close-cancel",2002,Action.CloseCancel,lab_ui_geometry::rect(panel.x+16.0,y,w,34.0),"Cancel");
        lab_ui_view::at_button(app.view,"close-discard",2004,Action.CloseDiscard,lab_ui_geometry::rect(panel.x+24.0+w,y,w,34.0),"Discard");
        lab_ui_view::record(app.view,lab_ui_view::Node<Action> {name:"close-save",text:"Save",id:2003,kind:lab_ui_view::BUTTON,action:Action.CloseSave,
            rect:lab_ui_geometry::rect(panel.x+32.0+2.0*w,y,w,34.0),placed:true,primary:true});
    };
}
fn action(app: App&, event: lab_ui_view::Event<Action>) -> bool {
    if event.kind==lab_ui_view::CLOSE_REQUESTED { request_close(app); return true; }
    if event.action==Action.CloseCancel && (event.kind==lab_ui_view::ACTIVATE || lab_ui_overlays_modal::backdrop(event)) {
        lab_document_close::choose(app.closing,app.file,lab_document_close::Choice.Cancel); sync_close_modal(app); return true;
    }
    if app.closing.pending || app.closing.saving || app.closing.ready { return false; }
    if event.action == Action.Input { if lab_document_file::busy(app.file) { return false; } let before = app.file.document.revision; let changed = lab_ui_views_editor::input(app.view, app.canvas, app.editor, app.file.document, lab_ui_view::bounds(app.view, "code"), config(), event); if app.file.document.revision != before { app.file.notice = []; app.file.code = 0; } return changed; }
    if event.action == Action.Dismiss && (lab_ui_overlays_modal::backdrop(event) || (event.input.kind == gfx::EVENT_KEY && event.input.down && event.input.scancode == gfx::scancode("Escape"))) { lab_document_workspace::choose(app.workspace, app.file, lab_document_workspace::Choice.Keep); lab_ui_overlays_modal::close(app.view, app.modal); return true; }
    if event.kind != lab_ui_view::ACTIVATE && event.kind != lab_ui_view::SUBMIT { return false; }
    if lab_document_file::busy(app.file) { return false; }
    match event.action {
        CloseSave => {
            if !app.file.exists {
                let path=lab_ui_view::field_state(app.view,2005).text;
                if path.len==0 { app.file.code=0; app.file.notice="Enter a file path to save"; return true; }
                if !lab_document_file::target(app.file,path) { return true; }
            }
            lab_document_close::choose(app.closing,app.file,lab_document_close::Choice.Save); sync_close_modal(app);
        },
        CloseDiscard => { lab_document_close::choose(app.closing,app.file,lab_document_close::Choice.Discard); sync_close_modal(app); },
        CloseCancel => {},
        Save => { if app.workspace.prompt { lab_document_workspace::choose(app.workspace, app.file, lab_document_workspace::Choice.Save); if !app.workspace.prompt { lab_ui_overlays_modal::close(app.view, app.modal); } } else { lab_document_file::save(app.file); } },
        Undo => { app.editor.code = 0; lab_document_model::undo(app.file.document); lab_ui_views_editor::reveal(app.view, app.canvas, app.editor, app.file.document, lab_ui_view::bounds(app.view, "code"), config()); },
        Redo => { app.editor.code = 0; lab_document_model::redo(app.file.document); lab_ui_views_editor::reveal(app.view, app.canvas, app.editor, app.file.document, lab_ui_view::bounds(app.view, "code"), config()); },
        Change => { lab_document_model::break_group(app.file.document); app.editing_path = true; lab_ui_controls_field::set(lab_ui_view::field_state(app.view, 1), app.file.path); app.view.input.focused = 1; },
        Cancel => { app.editing_path = false; app.view.input.focused = 7; },
        Open => { if !app.file.exists { if lab_document_file::target(app.file, lab_ui_view::field_state(app.view, 1).text) { app.editing_path = false; app.view.input.focused = 7; lab_document_file::save(app.file); } } else { lab_document_workspace::request(app.workspace, app.file, lab_document_workspace::Intent { path: lab_ui_view::field_state(app.view, 1).text, reload: true }); if app.workspace.prompt { lab_ui_overlays_modal::open(app.view, app.modal, 1002); } } },
        Discard => { lab_ui_overlays_modal::close(app.view, app.modal); lab_document_workspace::choose(app.workspace, app.file, lab_document_workspace::Choice.Discard); },
        Keep => { lab_document_workspace::choose(app.workspace, app.file, lab_document_workspace::Choice.Keep); lab_ui_overlays_modal::close(app.view, app.modal); }, Compact => { if lab_document_model::compact(app.file.document) { app.editor.code = 0; } }, Reload => { lab_document_workspace::request(app.workspace, app.file, lab_document_workspace::Intent { path: app.file.path, reload: true }); if app.workspace.prompt { lab_ui_overlays_modal::open(app.view, app.modal, 1002); } },
        Input => {}, Dismiss => {}, WorkbenchEditor => {}, WorkbenchChanges => {}, Files => {}, ProjectSearch => {}, RunSearch => {}, CancelSearch => {}, SelectFile => {}, SelectHit => {}, Refresh => {},
    } true
}
fn frame(app: App&) {
    poll(app); let size = gfx::screen_size(); let w = size.x / app.scale; let h = size.y / app.scale; lab_ui_render_scene::begin(app.canvas, w, h);
    fn describe() { build(app, w, h); } fn reduce(event: lab_ui_view::Event<Action>) -> bool { action(app, event) }
    lab_ui_view::frame(app.view, app.canvas, gfx::events(), gfx::mouse_pos(), gfx::focused(), app.scale, describe, reduce);
    lab_ui_views_editor::paint(app.canvas, app.editor, app.file.document, lab_ui_view::bounds(app.view, "code"), config(), lab_ui_view::scroll_state(app.view, 2).offset, app.view.input.focused == 7);
    lab_ui_view::paint_overlays(app.view, app.canvas); lab_ui_render_scene::render(app.canvas, lab_ui_controls_components::Theme {}.background);
}
fn destroy(app: App&) { lab_ui_views_editor::clear(app.editor); lab_document_workspace::close(app.workspace); lab_document_file::close(app.file); gfx::text_input(false); gfx::defer_close(false); lab_ui_layout_engine::destroy(app.view.layout); lab_ui_render_scene::destroy(app.canvas); }
