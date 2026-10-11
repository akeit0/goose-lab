// On-demand frames poll without idle GPU work; screen writes invalidate content.
import std;
import os;
import gfx;

fn main() {
    guard gfx::open_headless(32, 24) else { write_stderr(str("gfx: ", gfx::error(), "\n")); return; }
    gfx::present_on_demand(true);
    assert(gfx::frame());
    let revision = gfx::screen_revision();
    let content = gfx::screen_content_revision();
    let submits = gfx::submit_count();
    let presents = gfx::present_count();
    for i in 8 { assert(gfx::frame()); }
    assert(gfx::submit_count() == submits && gfx::present_count() == presents);
    assert(gfx::screen_revision() == revision && gfx::screen_content_revision() == content);
    gfx::request_present();
    assert(gfx::screen_content_revision() > content);
    let requested = gfx::screen_content_revision();
    var pass = gfx::PassDesc {};
    pass.color[0] = gfx::screen();
    gfx::begin_pass(pass); gfx::end_pass();
    assert(gfx::screen_content_revision() > requested);
    assert(gfx::frame() && gfx::submit_count() > submits);
    let after = gfx::submit_count();
    for i in 8 { assert(gfx::frame()); }
    assert(gfx::submit_count() == after && gfx::misuse_count() == 0);
    gfx::close();
    print("on-demand idle frames and screen invalidation passed");
}
