// Manual profiling by layer. Each stage has a separate call frame so the empty
// stage does not allocate an unused editor/UI model. No CI timing thresholds.
import std;
import os;
import vec;
import gfx;
import lab.ui.render.scene;
import lab.ui.render.font;
import lab.ui.render.text_layout;
import lab.ui.layout.engine;
import lab.ui.controls.field;
import lab.ui.view;
import lab.ui.geometry;
import workbench.editor.single;
enum Action { Input }
fn report() { print("sources=",lab_ui_render_font::source_bytes()," atlases=",lab_ui_render_font::atlas_bytes()," clay=",lab_ui_layout_engine::live_bytes()," layouts=",lab_ui_render_text_layout::live_bytes()," scene_snapshot=",lab_ui_render_scene::live_bytes()," submits=",gfx::submit_count()," presents=",gfx::present_count()); }
fn empty(frames: i64) {
    gfx::present_on_demand(true); var count=0;
    while gfx::frame() { if count==0 { assert(gfx::begin_screen(float4 {0.04,0.05,0.065,1.0})); gfx::end_pass(); } count++; if count==frames { break; } sleep_ms(16); }
    assert(gfx::frame()); report();
}
fn text(frames: i64) {
    var c=lab_ui_render_scene::create(lab_ui_render_font::default_font()); var count=0;
    while gfx::frame() {
        lab_ui_render_scene::begin(c,1180.0,820.0); lab_ui_render_scene::text(c,0,24.0,24.0,"Goose UI / 日本語 / é",float4 {1.0,1.0,1.0,1.0});
        lab_ui_render_scene::render(c,float4 {0.04,0.05,0.065,1.0}); count++; if count==frames { break; } sleep_ms(16);
    }
    assert(gfx::frame()); report(); print("renders=",c.renders," skipped=",c.skipped," quad_prefix=",72*10922," gpu_geometry=",c.capacity); lab_ui_render_scene::destroy(c);
}
fn field(frames: i64) {
    var c=lab_ui_render_scene::create(lab_ui_render_font::default_font()); var v=lab_ui_view::View<Action> {}; v.layout=lab_ui_layout_engine::create(c.fonts[0].font); var count=0;
    while gfx::frame() {
        lab_ui_render_scene::begin(c,1180.0,820.0);
        fn build() { lab_ui_view::begin(v,1180.0,820.0); lab_ui_view::field(v,"profile-field",1,Action.Input,"Type here…",lab_ui_layout_engine::Config { width: lab_ui_layout_engine::fixed(400.0), height: lab_ui_layout_engine::fixed(40.0) }); lab_ui_view::solve(v); }
        fn reduce(event: lab_ui_view::Event<Action>) -> bool { event.kind==lab_ui_view::CHANGE }
        lab_ui_view::frame(v,c,gfx::events(),gfx::mouse_pos(),gfx::focused(),1.0,build,reduce);
        lab_ui_render_scene::render(c,float4 {0.04,0.05,0.065,1.0}); count++; if count==frames { break; } sleep_ms(16);
    }
    assert(gfx::frame()); report(); print("renders=",c.renders," skipped=",c.skipped," quad_prefix=",72*10922," gpu_geometry=",c.capacity); lab_ui_layout_engine::destroy(v.layout); lab_ui_render_scene::destroy(c);
}
fn editor(frames: i64) {
    var app=app_editor_single::create("README.md"); var count=0;
    while gfx::frame() { app_editor_single::frame(app); count++; if app.closing.ready || count==frames { break; } sleep_ms(16); }
    assert(gfx::frame()); report(); print("renders=",app.canvas.renders," skipped=",app.canvas.skipped," quad_prefix=",72*10922," gpu_geometry=",app.canvas.capacity);
    app_editor_single::destroy(app);
}
fn main() {
    let argv=args(); var stage: u8[..16]="editor"; var frames: i64=180; var window=false;
    var i=1; while i<argv.len {
        if argv[i]=="--window" { window=true; }
        else if i+1<argv.len && argv[i]=="--stage" { i++; stage=argv[i]; }
        else if i+1<argv.len && argv[i]=="--frames" { i++; let n,ok=parse_int(argv[i]); assert(ok && n>0); frames=n; } i++;
    }
    if stage=="field" || stage=="editor" { gfx::text_transactions(true); }
    assert(if window { gfx::open("Goose / UI profile",1180,820,gfx::WINDOW_RESIZABLE) } else { gfx::open_headless(1180,820) });
    if stage=="empty" { empty(frames); } else if stage=="text" { text(frames); } else if stage=="field" { field(frames); } else { assert(stage=="editor"); editor(frames); }
    assert(lab_ui_render_font::source_bytes()==0 && lab_ui_render_font::atlas_bytes()==0 && lab_ui_render_text_layout::live_bytes()==0 && lab_ui_layout_engine::live_bytes()==0 && lab_ui_render_scene::live_bytes()==0);
    gfx::close();
}
