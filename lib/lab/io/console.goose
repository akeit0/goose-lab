// Process-wide console policy; select before writing or starting output workers.
namespace lab_io_console;
import std;
extern "glab_console_binary_output" fn binary_raw() -> bool;
// Preserve exact stdout/stderr bytes on Windows; flushes existing output first.
// POSIX already preserves bytes. This changes both streams until process exit.
fn binary_output() -> bool { binary_raw() }
