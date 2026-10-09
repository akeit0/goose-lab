// Platform command key for application actions, text fields and text views.
namespace lab_ui_input_shortcuts;
import std;
import gfx;
extern "glab_ui_is_macos" fn macos() -> bool;
extern "glab_ui_primary_mod" fn primary() -> i32;
fn primary_for(mac: bool) -> i32 { if mac { gfx::MOD_GUI } else { gfx::MOD_CTRL } }
fn command_for(mods: i32, mac: bool) -> bool {
    (mods & (gfx::MOD_CTRL | gfx::MOD_GUI | gfx::MOD_ALT)) == primary_for(mac)
}
fn command(mods: i32) -> bool { command_for(mods, macos()) }
fn hint(key: const u8[:], mods: i32) -> u8[>..] {
    str(if (mods & gfx::MOD_CTRL) != 0 { "Ctrl+" } else { "" },
        if (mods & gfx::MOD_GUI) != 0 { if macos() { "Cmd+" } else { "Super+" } } else { "" },
        if (mods & gfx::MOD_ALT) != 0 { if macos() { "Option+" } else { "Alt+" } } else { "" },
        if (mods & gfx::MOD_SHIFT) != 0 { "Shift+" } else { "" }, key)
}
