// Git's flat paths are one adapter for the domain-independent tree model.
namespace lab_git_tree;
import lab.git.repository;
import lab.collections.tree;
fn build(files: const lab_git_repository::Files&) -> lab_collections_tree::Tree {
    var tree = lab_collections_tree::Tree {};
    for item in files.items.len {
        let path = files.items[item].path; var parent: i64 = -1; var start: i64 = 0;
        for i in path.len {
            if path[i] != '/' || i == path.len - 1 { continue; }
            if i == start { return lab_collections_tree::Tree { code: lab_collections_tree::INVALID }; }
            let key = path[..i + 1]; var folder = lab_collections_tree::index(tree, key);
            if folder < 0 { folder = lab_collections_tree::add(tree, key, lab_git_repository::display(path[start..i]), parent, true); }
            if folder < 0 { return lab_collections_tree::Tree { code: tree.code }; }
            parent = folder; start = i + 1;
        }
        if lab_collections_tree::add(tree, path, lab_git_repository::display(path[start..]), parent, false, item) < 0 { return lab_collections_tree::Tree { code: tree.code }; }
    } tree
}
