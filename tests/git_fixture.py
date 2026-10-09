"""Use a disposable real repository; never modify the caller's index/worktree."""
import os
import json
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

def run(args, **kwargs):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True,
                            encoding="utf-8", errors="backslashreplace", timeout=45, **kwargs)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    if result.stdout.strip():
        print(result.stdout.strip())
    return result.stdout

helper = Path(__file__).with_name("process_fixture.py").resolve()
files_cli = None
json_cli = None
git_objects = None
git_history = None
editor_contract = None
if "--editor-contract" in sys.argv:
    at = sys.argv.index("--editor-contract")
    editor_contract = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
workspace_editor = None
workspace_contract = None
if "--workspace-editor" in sys.argv:
    at = sys.argv.index("--workspace-editor")
    workspace_editor = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
if "--workspace-contract" in sys.argv:
    at = sys.argv.index("--workspace-contract")
    workspace_contract = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
text_editor = None
if "--text-editor" in sys.argv:
    at = sys.argv.index("--text-editor")
    text_editor = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
find_files = None
if "--find-files" in sys.argv:
    at = sys.argv.index("--find-files")
    find_files = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
if "--git-history" in sys.argv:
    at = sys.argv.index("--git-history")
    git_history = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
if "--git-objects" in sys.argv:
    at = sys.argv.index("--git-objects")
    git_objects = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
if "--json-cli" in sys.argv:
    at = sys.argv.index("--json-cli")
    json_cli = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
if "--files-cli" in sys.argv:
    at = sys.argv.index("--files-cli")
    files_cli = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
if "--runner" in sys.argv:
    at = sys.argv.index("--runner")
    runner = Path(sys.argv[at + 1]).resolve()
    del sys.argv[at:at + 2]
    # Read while the child is still running; buffering until completion fails this.
    command = [str(runner), "--", sys.executable, str(helper), "stream"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert process.stdout.readline() == b"first\n"
    assert process.poll() is None, "runner buffered output until process exit"
    stdout, stderr = process.communicate(timeout=5)
    assert process.returncode == 0 and stdout == "日本語\nlast\n".encode("utf-8"), (stdout, stderr)
    assert b"warning:\xff\n" in stderr, stderr
    result = subprocess.run([str(runner), "--", sys.executable, str(helper), "bytes"],
                            capture_output=True, timeout=5)
    assert result.returncode == 0 and result.stdout == b"\x00\r\n\n\x1a\xff", result
    for options, mode, expected, message in (
        ([], "exit", 42, b"exit=42"),
        (["--cancel-after", "50"], "sleep", 1, b"cancel"),
        (["--timeout", "100"], "sleep", 1, b"timed out"),
    ):
        result = subprocess.run([str(runner), *options, "--", sys.executable, str(helper), mode],
                                capture_output=True, timeout=5)
        assert result.returncode == expected and message in result.stderr.lower(), result
    print("I/O runner: live bytes, split UTF-8, binary stderr, child exit, timer cancellation and deadline passed")
with tempfile.TemporaryDirectory(prefix="goose git ") as directory:
    file_root = Path(directory) / "I-O 日本語 files"
    file_root.mkdir()
    (file_root / "bytes.bin").write_bytes(b"\x00\r\n\n\x1a\xff")
    (file_root / "empty.bin").write_bytes(b"")
    (file_root / "large.bin").write_bytes(bytes(range(256)) * 8192)
    (file_root / "oversize.bin").write_bytes(b"x" * (2097152 + 1))
    (file_root / "empty-dir").mkdir()
    (file_root / "many").mkdir()
    for i in range(70):
        (file_root / "many" / f"entry-{i:03d} 日本語.txt").write_bytes(b"entry")
    search_root = file_root / "search"
    search_root.mkdir()
    run(["git", "-C", search_root, "init", "-q"])
    contents = {
        "readme.txt": "日本語 needle\r\nababa needle\nNEEDLE\n".encode(),
        "nested/日本語.txt": b"prefix needle suffix\n",
        "nested/many.txt": b"".join(f"line {i} needle\n".encode() for i in range(70)),
        "long.txt": b"x" * 70000 + b" needle\n",
        "ignored.txt": b"needle\n", ".gitignore": b"ignored.txt\n",
        "binary.dat": b"\0needle", "bad.dat": b"\xffneedle", "large.dat": b"x" * 2097153,
        "empty.txt": b"", "build/out.txt": b"needle\n", "nested/build-core/out.txt": b"needle\n",
        "third_party/vendor.txt": b"needle\n", "node_modules/lib.txt": b"needle\n",
    }
    for name, data in contents.items():
        path = search_root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    def search_snapshot():
        return {p.relative_to(search_root): p.read_bytes() for p in search_root.rglob("*") if p.is_file()}
    search_before = search_snapshot()
    if find_files:
        def find(*options, query="needle", root=search_root):
            return subprocess.run([str(find_files), *map(str, options), "--", str(root), query], capture_output=True, timeout=10)
        def records(result):
            return sorted((json.loads(line) for line in result.stdout.splitlines()), key=lambda h: (h["path"], h["start"]))
        serial = find("--include", "**/*.txt", "--parallel", 1)
        parallel = find("--include", "**/*.txt", "--parallel", 4)
        hits = records(serial)
        assert serial.returncode == parallel.returncode == 0 and hits == records(parallel) and len(hits) == 75, (serial, parallel)
        first = next(h for h in hits if h["path"] == "readme.txt" and h["line"] == 1)
        assert (first["column"], first["start"], first["end"], first["preview"]) == (5, 10, 16, "日本語 needle"), first
        assert next(h for h in hits if h["path"] == "long.txt")["preview"].startswith("…"), hits
        folded = find("--include", "**/*.txt", "--ignore-case")
        assert folded.returncode == 0 and len(records(folded)) == 76, folded
        overlap = find("--include", "readme.txt", query="aba")
        assert overlap.returncode == 0 and [h["start"] for h in records(overlap)] == [18, 20], overlap
        exact = find("--include", "readme.txt", "--max-matches", 2)
        beyond = find("--include", "readme.txt", "--max-matches", 1)
        assert exact.returncode == 0 and len(records(exact)) == 2 and beyond.returncode == 1 and len(records(beyond)) == 1 and b"incomplete" in beyond.stderr, (exact, beyond)
        subset = find("--include", "**/*.txt", "--exclude", "nested/**")
        assert subset.returncode == 0 and len(records(subset)) == 4, subset
        skipped = find()
        assert skipped.returncode == 1 and len(records(skipped)) == 75 and b"3 skipped" in skipped.stderr, skipped
        for options, root, query, expected, diagnostic in (
            (["--cancel-after", "0"], search_root, "needle", 1, b"cancelled"),
            (["--max-paths", "1"], search_root, "needle", 1, b"incomplete"),
            (["--max-depth", "0"], search_root, "needle", 1, b"incomplete"),
            ([], search_root / "missing", "needle", 1, b"Unable"),
            (["--include", "***"], search_root, "needle", 2, b"Invalid"),
            (["--parallel", "0"], search_root, "needle", 2, b"Invalid"),
            ([], search_root, "", 2, b"Invalid"),
        ):
            result = find(*options, root=root, query=query)
            assert result.returncode == expected and diagnostic in result.stderr, result
        no_hits = find("--include", "**/*.txt", query="absent-value-92831")
        assert no_hits.returncode == 0 and no_hits.stdout == b"", no_hits
        print("Find in files CLI: bounded parallel reads, exact offsets, Unicode columns, overlap, glob exclusion, skips, partial limits and cancellation passed")
    if len(sys.argv) > 2:
        for scale in ("1.0", "1.25"):
            run([sys.argv[2], search_root, Path.cwd() / f"file-search-interacted-{scale}.png", scale, "search"])
        output = run([sys.argv[3], "--repo", search_root, "--search", "needle", "--include", "**/*.txt", "--headless", "--frames", "3", "--width", "560", "--height", "860", "--screenshot", Path.cwd() / "file-search-compact.png"])
        assert "matches=75" in output and "screenshot=true" in output, output
    assert search_snapshot() == search_before, "file search changed project files"
    if text_editor:
        editor_file = file_root / "editor 日本語.txt"
        original_editor = "first 日本語\r\nsecond\r\n".encode()
        for scale in ("1.0", "1.25"):
            run([editor_contract, editor_file, Path.cwd() / f"text-editor-interacted-{scale}.png", scale])
            assert editor_file.read_bytes() == original_editor
        output = run([text_editor, "--file", editor_file, "--headless", "--frames", "3", "--width", "560", "--height", "860", "--screenshot", Path.cwd() / "text-editor-compact.png"])
        assert "dirty=false" in output and "screenshot=true" in output, output
        assert not list(file_root.glob("*.goose-lab-recovery-*"))
    if workspace_editor:
        for scale in ("1.0", "1.25"):
            workspace_root = file_root / f"workspace-{scale}"
            run([workspace_contract, workspace_root, Path.cwd() / f"workspace-interacted-{scale}.png", scale])
        output = run([workspace_editor, "--root", workspace_root, "--file", workspace_root / "a.txt", "--headless", "--frames", "3", "--width", "560", "--height", "860", "--screenshot", Path.cwd() / "workspace-compact.png"])
        assert "dirty=false" in output and "screenshot=true" in output, output
        assert not list(workspace_root.rglob("*.goose-lab-recovery-*"))
    if json_cli:
        settings = file_root / "settings 日本語.json"
        original = b' \n{\n  "theme" : "light",\n  "future":{"exact":900719925474099312345,"rate":1.250e-20}\n}\n'
        def config(*args):
            return subprocess.run([str(json_cli), *map(str, args)], capture_output=True, timeout=10)
        settings.write_bytes(original)
        result = config("get", settings, "future")
        assert result.returncode == 0 and result.stdout == b'{"exact":900719925474099312345,"rate":1.250e-20}\n', result
        result = config("set", settings, "theme", '"dark"')
        assert result.returncode == 0 and result.stdout == b"" and b"synced=true" in result.stderr, result
        assert settings.read_bytes() == original.replace(b'"light"', b'"dark"')
        prior = settings.stat().st_mtime_ns
        result = config("set", settings, "theme", '"dark"')
        assert result.returncode == 0 and b"unchanged" in result.stderr.lower() and settings.stat().st_mtime_ns == prior, result
        result = config("set", settings, '日本語\n"', '[true,{"value":null}]')
        assert result.returncode == 0 and json.loads(settings.read_bytes())['日本語\n"'] == [True, {"value": None}], result
        for data, options, command, key, fragment, message in (
            (original, [], "set", "theme", "[1,]", b"value is not valid"),
            (b'{"a":1,"\\u0061":2}', [], "set", "a", "3", b"ambiguous"),
            (b'{"a":1,"\\u0061":2}', [], "get", "a", None, b"ambiguous"),
            (b"[]", [], "set", "a", "0", b"object"),
            (b"{broken", [], "set", "a", "0", b"source is not valid"),
            (original, [], "get", "missing", None, b"missing"),
            (original, ["--limit", "5"], "get", "theme", None, b"capacity"),
            (original, ["--cancel-after", "0"], "set", "theme", '"dark"', b"cancelled"),
            (b"{}", ["--limit", "6"], "set", "a", "0", b"limit"),
        ):
            settings.write_bytes(data)
            arguments = [*options, command, settings, key]
            if fragment is not None:
                arguments.append(fragment)
            result = config(*arguments)
            assert result.returncode == 1 and message in result.stderr.lower() and result.stdout == b"", result
            assert settings.read_bytes() == data, "rejected edit changed settings"
        if os.name == "nt":
            settings.write_bytes(original)
            os.chmod(settings, stat.S_IREAD)
            try:
                result = config("set", settings, "theme", '"dark"')
                assert result.returncode == 1 and settings.read_bytes() == original, result
            finally:
                os.chmod(settings, stat.S_IWRITE)
        settings.unlink()
        result = config("set", settings, "theme", '"dark"')
        assert result.returncode == 1 and not settings.exists(), result
        assert not list(file_root.glob(".goose-lab-save-*")), "settings edit leaked staging files"
        print("JSON settings CLI: exact get/set, unknown fields, escaped keys, no-op, rejected input, cancellation and save failures passed")
    if files_cli:
        def files(*args):
            return subprocess.run([str(files_cli), *map(str, args)], capture_output=True, timeout=10)
        before = {path.relative_to(file_root): path.read_bytes() for path in file_root.rglob("*") if path.is_file()}
        result = files("read", file_root / "bytes.bin")
        assert result.returncode == 0 and result.stdout == b"\x00\r\n\n\x1a\xff", result
        result = files("--limit", "70", "list", file_root / "many")
        labels = result.stdout.decode("utf-8").splitlines()
        assert result.returncode == 0 and set(labels) == {f"file\tentry-{i:03d} 日本語.txt" for i in range(70)}, result
        for options, mode, name, message in (
            (["--limit", "5"], "read", "bytes.bin", b"capacity"),
            (["--limit", "69"], "list", "many", b"capacity"),
            (["--cancel-after", "0"], "read", "large.bin", b"cancelled"),
            (["--cancel-after", "0"], "list", "many", b"cancelled"),
            ([], "read", "missing", b"missing"),
            ([], "read", "empty-dir", b"regular"),
            ([], "list", "bytes.bin", b"directory"),
        ):
            result = files(*options, mode, file_root / name)
            assert result.returncode == 1 and message in result.stderr.lower(), result
            if mode == "read":
                assert result.stdout == b"", "failed reads must not emit partial contents"
        result = files("--limit", "0", "read", file_root / "empty.bin")
        assert result.returncode == 0 and result.stdout == b"", result
        assert before == {path.relative_to(file_root): path.read_bytes() for path in file_root.rglob("*") if path.is_file()}
        print("Async files CLI: binary bytes, paged names, exact limits, cancellation, missing/type errors and read-only operation passed")
        target = file_root / "copy 日本語.bin"
        for source in ("bytes.bin", "empty.bin", "large.bin"):
            target.write_bytes(b"old complete")
            result = files("copy", file_root / source, target)
            assert result.returncode == 0 and result.stdout == b"" and b"synced=true" in result.stderr, result
            assert target.read_bytes() == (file_root / source).read_bytes()
        for options, source, destination, message in (
            (["--limit", "5"], "bytes.bin", target, b"capacity"),
            (["--cancel-after", "0"], "large.bin", target, b"cancelled"),
            ([], "missing", target, b"missing"),
            ([], "bytes.bin", file_root / "missing-parent" / "new.bin", b"missing"),
            ([], "bytes.bin", file_root / "empty-dir", b"regular"),
        ):
            target.write_bytes(b"old complete")
            result = files(*options, "copy", file_root / source, destination)
            assert result.returncode == 1 and message in result.stderr.lower() and result.stdout == b"", result
            assert target.read_bytes() == b"old complete"
        result = files("copy", target, target)
        assert result.returncode == 0 and target.read_bytes() == b"old complete", result
        if os.name == "nt":
            os.chmod(target, stat.S_IREAD)
            try:
                result = files("copy", file_root / "bytes.bin", target)
                assert result.returncode == 1 and target.read_bytes() == b"old complete", result
            finally:
                os.chmod(target, stat.S_IWRITE)
        assert not list(file_root.glob(".goose-lab-save-*")), "save leaked temporary files"
        target.unlink()
        assert before == {path.relative_to(file_root): path.read_bytes() for path in file_root.rglob("*") if path.is_file()}
        print("Atomic save CLI: exact binary/empty/2 MiB copies, same-path copy, failure/cancellation preservation and temporary cleanup passed")
    if git_history:
        history_repo = Path(directory) / "history 日本語"
        history_repo.mkdir()
        def hg(*args, data=None):
            result = subprocess.run(["git", "-C", str(history_repo), *args], input=data, capture_output=True, timeout=10)
            assert result.returncode == 0, (args, result.stderr)
            return result.stdout.strip().decode("utf-8")
        def history(*args):
            return subprocess.run([str(git_history), str(history_repo), *map(str, args)], capture_output=True, timeout=10)
        hg("init", "-q", "-b", "main")
        hg("config", "user.name", "日本語 author")
        hg("config", "user.email", "history@example.invalid")
        hg("config", "core.autocrlf", "false")
        empty = history("list")
        assert empty.returncode == 0 and json.loads(empty.stdout)["commits"] == [], empty
        initial_history = {"literal[1].txt": b"before\n@@ ordinary text\n", "日本語.txt": "日本語 before\r\n".encode(),
                           "removed.txt": b"deleted\n", "binary.bin": b"\0before\xff", "empty.txt": b"", "invalid.txt": b"\xffbad", "large.bin": b"x" * 2097152}
        for name, data in initial_history.items():
            (history_repo / name).write_bytes(data)
        hg("add", "--all"); hg("commit", "-qm", "root 日本語")
        root_commit = hg("rev-parse", "HEAD")
        hg("checkout", "-qb", "side")
        (history_repo / "side.txt").write_bytes(b"from side\n")
        hg("add", "--all"); hg("commit", "-qm", "side")
        side_commit = hg("rev-parse", "HEAD")
        hg("checkout", "-q", "main")
        (history_repo / "literal[1].txt").write_bytes(b"after\n@@ ordinary text\n")
        (history_repo / "binary.bin").write_bytes(b"\0after\xff")
        (history_repo / "removed.txt").unlink()
        hg("add", "--all"); hg("commit", "-qm", "edit and delete")
        edit_commit = hg("rev-parse", "HEAD")
        hg("merge", "--no-ff", "-qm", "merge side", "side")
        merge_commit = hg("rev-parse", "HEAD")
        tree = hg("rev-parse", "HEAD^{tree}")
        anchor = merge_commit
        for i in range(34):
            anchor = hg("commit-tree", tree, "-p", anchor, data=f"page {i} 日本語\n".encode())
        hg("update-ref", "HEAD", anchor)
        expected = hg("log", "--first-parent", "--format=%H", "HEAD", "--").splitlines()
        assert len(expected) == 37 and side_commit not in expected
        marker_history = Path(directory) / "history-external.txt"
        history_driver = '"' + sys.executable + '" "' + str(helper) + '" touch "' + str(marker_history) + '"'
        hg("config", "diff.external", history_driver)
        before_history_index = (history_repo / ".git" / "index").read_bytes()
        def history_snapshot():
            return {p.relative_to(history_repo): p.read_bytes() for p in history_repo.rglob("*") if p.is_file() and ".git" not in p.relative_to(history_repo).parts}
        before_history_files = history_snapshot()
        first = history("list"); assert first.returncode == 0, first
        page = json.loads(first.stdout)
        assert page["anchor"] == anchor and page["more"] and [c["id"] for c in page["commits"]] == expected[:32]
        assert page["commits"][0]["author"] == "日本語 author"
        moved = hg("commit-tree", tree, "-p", anchor, data=b"new HEAD\n")
        hg("update-ref", "HEAD", moved)
        last = history("list", anchor, 32, 32); assert last.returncode == 0, last
        tail = json.loads(last.stdout)
        assert not tail["more"] and [c["id"] for c in tail["commits"]] == expected[32:]
        assert tail["commits"][2]["id"] == merge_commit and tail["commits"][2]["parents"] == 2 and tail["commits"][2]["parent"] == edit_commit
        assert json.loads(history("list").stdout)["anchor"] == moved
        hg("update-ref", "HEAD", anchor)
        files = history("files", root_commit); assert files.returncode == 0, files
        assert {f["path"]: f["status"] for f in json.loads(files.stdout)} == {p: "A" for p in initial_history}
        files = history("files", merge_commit); assert files.returncode == 0 and json.loads(files.stdout) == [{"path": "side.txt", "status": "A"}], files
        files = history("files", edit_commit); assert files.returncode == 0, files
        assert {f["path"]: f["status"] for f in json.loads(files.stdout)} == {"binary.bin": "M", "literal[1].txt": "M", "removed.txt": "D"}
        for name in ("literal[1].txt", "日本語.txt", "binary.bin", "empty.txt", "invalid.txt"):
            result = history("blob", root_commit, name)
            assert result.returncode == 0 and result.stdout == initial_history[name], result
        patch = history("diff", root_commit, "literal[1].txt"); assert patch.returncode == 0 and b"+before" in patch.stdout, patch
        patch = history("diff", edit_commit, "literal[1].txt")
        assert patch.returncode == 0 and b"-before" in patch.stdout and b"+after" in patch.stdout, patch
        patch = history("diff", edit_commit, "removed.txt")
        assert patch.returncode == 0 and b"-deleted" in patch.stdout, patch
        for command, commit_id, name in (("blob", edit_commit, "removed.txt"), ("blob", root_commit, "absent.txt"), ("blob", root_commit, "large.bin"), ("diff", "--help", "literal[1].txt")):
            result = history(command, commit_id, name)
            assert result.returncode == 1 and result.stdout == b"", result
        assert history("list", "--help", 0, 1).returncode == 1
        assert history("list", anchor, -1, 1).returncode == 1
        if len(sys.argv) > 2:
            for scale in ("1.0", "1.25"):
                run([sys.argv[2], history_repo, Path.cwd() / f"git-history-interacted-{scale}.png", scale, "history"])
            run([sys.argv[3], "--repo", history_repo, "--history", "--headless", "--frames", "3", "--width", "560", "--height", "860",
                 "--screenshot", Path.cwd() / "git-history-compact.png"])
        assert not marker_history.exists(), "history executed external diff"
        assert (history_repo / ".git" / "index").read_bytes() == before_history_index and history_snapshot() == before_history_files
        print("Git history: anchored pages, moving HEAD, root/merge/deletion, exact binary/Unicode/empty blobs, bounds and read-only operation passed")
    repo = Path(directory) / "日本語 repo with spaces"
    repo.mkdir()
    (repo / "nested").mkdir()
    def git(*args):
        return run(["git", "-C", repo, *args])
    git("init", "-q")
    git("config", "user.name", "Goose fixture")
    git("config", "user.email", "fixture@example.invalid")
    git("config", "core.autocrlf", "false")
    initial = {".gitignore": "*.tmp\nignored/\n", "literal[1].txt": "before\ncontext\n", "staged.txt": "before staged\n",
               "日本語.txt": "日本語 before\n", "removed.txt": "deleted\n",
               "-option.txt": "literal option\n", "code.goose": "".join(f"let value_{i} = {i};\n" for i in range(1, 101))}
    for name, text in initial.items():
        (repo / name).write_text(text, encoding="utf-8", newline="\n")
    (repo / "binary.bin").write_bytes(b"\0before")
    git("add", "--all")
    git("commit", "-qm", "fixture")
    (repo / "literal[1].txt").write_text("after\ncontext\nextra\n", encoding="utf-8", newline="\n")
    (repo / "staged.txt").write_text("before staged\nsaved staged\n", encoding="utf-8", newline="\n")
    git("add", "--", "staged.txt")
    (repo / "日本語.txt").write_text("日本語 after\n", encoding="utf-8", newline="\n")
    (repo / "-option.txt").write_text("changed literal option\n", encoding="utf-8", newline="\n")
    (repo / "removed.txt").unlink()
    (repo / "binary.bin").write_bytes(b"\0after")
    lines = initial["code.goose"].splitlines()
    lines[4] = 'let 日本語 = "café";'
    lines[69] = 'let long_text = "' + "x" * 1600 + '";'
    (repo / "code.goose").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    (repo / "untracked.txt").write_text("new 日本語\nno final newline", encoding="utf-8", newline="\n")
    (repo / "nested" / "new [日本語].txt").write_bytes("nested\tdata\r\n".encode("utf-8"))
    (repo / "nested" / "inner").mkdir()
    (repo / "other").mkdir()
    (repo / "nested" / "inner" / "same.goose").write_bytes(b"nested leaf\n")
    (repo / "other" / "same.goose").write_bytes(b"other leaf\n")
    for i in range(10):
        (repo / f"z-extra-{i}.txt").write_bytes(b"virtual row\n")
    (repo / "empty.txt").write_bytes(b"")
    (repo / "newbinary.bin").write_bytes(b"\0new")
    (repo / "oversized.txt").write_bytes(b"x" * (2097152 + 1))
    (repo / "invalid-encoding.txt").write_bytes(b"\xffbad\n")
    (repo / "-new[1].txt").write_text("literal new file\n", encoding="utf-8", newline="\n")
    (repo / "ignored.tmp").write_bytes(b"ignored root")
    (repo / "ignored").mkdir()
    (repo / "ignored" / "content.txt").write_bytes(b"ignored directory")
    (repo / ".git" / "info" / "exclude").write_text("info-excluded.txt\n", encoding="utf-8")
    (repo / "info-excluded.txt").write_bytes(b"ignored via info")
    global_excludes = Path(directory) / "global.ignore"
    global_excludes.write_text("global-excluded.txt\n", encoding="utf-8")
    git("config", "core.excludesFile", str(global_excludes))
    (repo / "global-excluded.txt").write_bytes(b"ignored via user config")
    # A configured external driver must not execute when the viewer obtains a diff.
    marker = Path(directory) / "external.txt"
    driver = '"' + sys.executable + '" "' + str(helper) + '" touch "' + str(marker) + '"'
    git("config", "diff.external", driver)
    before_index = (repo / ".git" / "index").read_bytes()
    def snapshot():
        return {path.relative_to(repo): path.read_bytes() for path in repo.rglob("*")
                if path.is_file() and ".git" not in path.relative_to(repo).parts}
    before_files = snapshot()
    if git_objects:
        requests = ["HEAD", "HEAD:literal[1].txt", "HEAD:binary.bin", "HEAD:日本語.txt", "no-such-object-44291", "HEAD:staged.txt"]
        result = subprocess.run([str(git_objects), str(repo), *requests], capture_output=True, timeout=10)
        assert result.returncode == 1 and result.stderr == b"", result
        objects = [json.loads(line) for line in result.stdout.splitlines()]
        assert [item["request"] for item in objects] == requests and len(objects) == 6
        assert objects[0]["type"] == "commit" and objects[0]["status"] == "found"
        assert objects[1]["size"] == len(initial["literal[1].txt"].encode()) and objects[1]["preview"] == "before\\ncontext\\n"
        assert objects[2]["type"] == "blob" and objects[2]["size"] == 7 and objects[2]["preview"] == "\\u0000before"
        assert objects[3]["preview"] == "日本語 before\\n" and objects[4]["status"] == "missing" and objects[5]["status"] == "found"
        result = subprocess.run([str(git_objects), str(repo), "HEAD:staged.txt", "HEAD:binary.bin"], capture_output=True, timeout=10)
        assert result.returncode == 0 and len(result.stdout.splitlines()) == 2, result
        print("Git object CLI: one process, ordered live requests, raw binary/Unicode bodies, missing response recovery and EOF passed")
    run([sys.argv[1], repo, sys.executable, helper, file_root])
    assert not list(file_root.rglob(".goose-lab-save-*")), "save contract leaked temporary files"
    if len(sys.argv) > 2:
        for scale in ("1.0", "1.25"):
            run([sys.argv[2], repo, Path.cwd() / f"git-viewer-interacted-{scale}.png", scale])
        output = run([sys.argv[3], "--repo", repo / "nested", "--headless", "--frames", "3", "--width", "560", "--height", "860",
                      "--screenshot", Path.cwd() / "git-viewer-compact.png"])
        assert "files=25" in output and "screenshot=true" in output, output
        linked = Path(directory) / "linked 日本語 worktree"
        git("worktree", "add", "--detach", "--quiet", str(linked), "HEAD")
        (linked / "staged.txt").write_bytes(b"before staged\nlinked change\n")
        run([sys.argv[2], linked, Path.cwd() / "git-viewer-linked.png", "1.0", "linked"])
    assert not marker.exists(), "external diff was executed"
    assert (repo / ".git" / "index").read_bytes() == before_index, "viewer changed the Git index"
    assert snapshot() == before_files, "viewer changed files"
