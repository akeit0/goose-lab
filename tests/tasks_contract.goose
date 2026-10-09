import std;
import os;
import task_inbox.model;
import lab.fs.storage;
import lab.text.strings;
fn main() {
    let argv = args(); assert(argv.len == 2); let path = argv[1]; delete_file(path);
    var j = app_tasks_model::Journal {};
    assert(app_tasks_model::apply(j, app_tasks_model::Command { kind: app_tasks_model::ADD, title: "   Plan café visit  " }) == app_tasks_model::OK);
    let id = j.store.items[0].id; assert(j.store.items[0].title == "Plan café visit");
    assert(app_tasks_model::apply(j, app_tasks_model::Command { kind: app_tasks_model::ADD, title: "Ship Goose utilities" }) == app_tasks_model::OK);
    assert(app_tasks_model::visible(j.store, app_tasks_model::ALL, "GOOSE").len == 1);
    assert(app_tasks_model::apply(j, app_tasks_model::Command { kind: app_tasks_model::TOGGLE, id: id }) == app_tasks_model::OK);
    assert(app_tasks_model::visible(j.store, app_tasks_model::DONE, "").len == 1);
    assert(app_tasks_model::apply(j, app_tasks_model::Command { kind: app_tasks_model::RENAME, id: id, title: "Call café" }) == app_tasks_model::OK);
    assert(app_tasks_model::apply(j, app_tasks_model::Command { kind: app_tasks_model::DELETE, id: id }) == app_tasks_model::OK);
    assert(app_tasks_model::undo(j) && j.store.items[0].title == "Call café" && j.store.items[0].done);
    let next = j.store.next_id; assert(app_tasks_model::undo(j) && j.store.next_id == next);
    assert(app_tasks_model::apply(j, app_tasks_model::Command { kind: app_tasks_model::ADD, title: " " }) == app_tasks_model::INVALID);
    let undo_count = j.past.len;
    assert(app_tasks_model::apply(j, app_tasks_model::Command { kind: app_tasks_model::DELETE, id: 999 }) == app_tasks_model::ABSENT && j.past.len == undo_count);
    let bytes = app_tasks_model::encode(j.store); let restored, valid = app_tasks_model::decode(bytes);
    assert(valid && restored == j.store);
    for cut in bytes.len { let partial, accepted = app_tasks_model::decode(bytes[..cut]); assert(!accepted && partial.items.len == 0); }
    var duplicate = j.store; duplicate.items[1].id = duplicate.items[0].id;
    let duplicated, accepted = app_tasks_model::decode(app_tasks_model::encode(duplicate)); assert(!accepted && duplicated.items.len == 0);
    assert(!lab_text_strings::single_line("\xC0\xAF") && !lab_text_strings::single_line("hello\nworld"));
    assert(!lab_text_strings::single_line("\xED\xA0\x80") && lab_text_strings::single_line("café Ελληνικά"));
    assert(!lab_text_strings::single_line("a\xC2\x85b") && !lab_text_strings::single_line("a\xE2\x80\xA8b"));
    assert(app_tasks_model::save(path, j.store) == lab_fs_storage::OK);
    let loaded, code = app_tasks_model::load(path); assert(code == lab_fs_storage::OK && loaded == j.store);
    let file = lab_fs_storage::envelope("GXTASKS!", 1, bytes);
    assert(lab_fs_storage::checksum("123456789") == 0xCBF43926);
    for cut in file.len { let partial = lab_fs_storage::unpack(file[..cut], "GXTASKS!", 1); assert(partial.code != lab_fs_storage::OK && partial.data.len == 0); }
    var damaged: u8[>..] = []; damaged.append(file); damaged[damaged.len - 1] ^= 1;
    assert(lab_fs_storage::unpack(damaged, "GXTASKS!", 1).code == lab_fs_storage::CORRUPT);
    assert(lab_fs_storage::unpack(lab_fs_storage::envelope("GXTASKS!", 2, bytes), "GXTASKS!", 1).code == lab_fs_storage::VERSION);
    assert(app_tasks_model::save(str(path, "/absent/tasks.gxt"), j.store) == lab_fs_storage::IO);
    let unchanged, old_code = app_tasks_model::load(path); assert(old_code == lab_fs_storage::OK && unchanged == j.store);
    var huge: u8[>..] = []; huge.resize(lab_fs_storage::MAX_BYTES + 1, 0);
    assert(write_file_atomic(path, huge)); let oversized, too_large = app_tasks_model::load(path); assert(too_large == lab_fs_storage::LIMIT);
    assert(delete_file(path)); let missing, missing_code = app_tasks_model::load(path); assert(missing_code == lab_fs_storage::MISSING);
    var full = app_tasks_model::Journal {};
    for i in 128 { assert(app_tasks_model::apply(full, app_tasks_model::Command { kind: app_tasks_model::ADD, title: str("Task ", i) }) == app_tasks_model::OK); }
    assert(full.past.len == 16 && app_tasks_model::apply(full, app_tasks_model::Command { kind: app_tasks_model::ADD, title: "overflow" }) == app_tasks_model::FULL);
    print("Tasks, undo, UTF-8, bounded persistence and corruption contract passed");
}
