// App navigation stays with the sample; reusable controls remain in lab.ui.
namespace app_workbench_navigation;
import lab.ui.view;
import lab.ui.layout.engine;
fn header<A>(view: lab_ui_view::View<A>&, name: const u8[:], changes: bool, editor: A, git: A, open_file: A, can_open: bool = false) {
    lab_ui_view::box(view, "workbench-header", lab_ui_layout_engine::Config { direction: lab_ui_layout_engine::ROW, width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::fixed(32.0), gap: 8 }) {
        lab_ui_view::label(view, "workbench-name", name, lab_ui_layout_engine::Config { width: lab_ui_layout_engine::grow(), height: lab_ui_layout_engine::grow() });
        lab_ui_view::button(view, "workbench-editor", 900001, editor, "Editor", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(72.0), height: lab_ui_layout_engine::grow() }, !changes);
        lab_ui_view::button(view, "workbench-changes", 900002, git, "Git", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(56.0), height: lab_ui_layout_engine::grow() }, changes);
        if changes { lab_ui_view::button(view, "workbench-open-file", 900003, open_file, "Edit file", lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(86.0), height: lab_ui_layout_engine::grow() }, false, can_open); }
    };
}
