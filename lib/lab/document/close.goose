// UI-independent exit decision; borrow the file session, never own or write a backup.
namespace lab_document_close;
import std;
import lab.document.model;
import lab.document.file;
enum Choice { Cancel, Save, Discard }
struct State { pending: bool = false, prompt: bool = false, saving: bool = false, ready: bool = false }
fn request(s: State&, file: lab_document_file::State&) {
    if s.pending || s.prompt || s.saving || s.ready { return; }
    lab_document_model::break_group(file.document); s.pending=true;
}
fn poll(s: State&, file: const lab_document_file::State&, settling: bool = false) {
    if settling || lab_document_file::busy(file) { return; }
    if s.saving {
        s.saving=false;
        if file.code==0 && !lab_document_model::dirty(file.document) { s.ready=true; }
        else { s.prompt=true; }
    }
    if s.pending { s.pending=false; s.prompt=lab_document_model::dirty(file.document); s.ready=!s.prompt; }
}
fn choose(s: State&, file: lab_document_file::State&, choice: Choice) -> bool {
    if !s.prompt || lab_document_file::busy(file) { return false; }
    match choice {
        Cancel => { s.prompt=false; true },
        Discard => { s.prompt=false; s.ready=true; true },
        Save => { if !lab_document_file::save(file) { return false; } s.prompt=false; s.saving=true; true },
    }
}
