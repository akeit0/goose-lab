// Worker adapter. Completions own snapshots; no handles/references escape.
namespace lab_git_client;
import std;
import os;
import lab.io.cancel;
import lab.io.process;
import lab.git.repository;
import lab.git.history;
import lab.text.diff;
import lab.fs.search;
struct Job { stop: bool = false, serial: u64 = 0, refresh: bool = false, staged: bool = false, untracked: bool = false,
    history: bool = false, history_listing: bool = false, commit_files: bool = false, content: bool = false,
    anchor: u8[..64] = [], offset: i64 = 0, commit: lab_git_history::Commit = lab_git_history::Commit {},
    repo: u8[..512] = [], path: u8[..512] = [], search_file: bool = false, query: u8[..512] = [],
    hit: lab_fs_search::Hit = default<lab_fs_search::Hit>(), ignore_case: bool = false, cancel: lab_io_cancel::Token = lab_io_cancel::Token {} }
struct Completed { serial: u64, refresh: bool, staged: bool, repo: u8[..512], path: u8[..512],
    history: bool = false, history_listing: bool = false, commit_files: bool = false, content: bool = false,
    commit: lab_git_history::Commit = lab_git_history::Commit {}, page: lab_git_history::Page = lab_git_history::Page {},
    search_file: bool = false, query: u8[..512] = [], hit: lab_fs_search::Hit = default<lab_fs_search::Hit>(),
    watch_paths: lab_git_repository::WatchPaths = lab_git_repository::WatchPaths {},
    files: lab_git_repository::Files = lab_git_repository::Files {}, error: u8[..512] = [], diff: lab_git_repository::Diff = lab_git_repository::Diff {} }
struct State { serial: u64 = 0, busy: bool = false, refresh: bool = false, token: lab_io_cancel::Token = lab_io_cancel::Token {} }
thread_fn worker() {
    loop {
        let job = qget<Job>(); if job.stop { break; }
        let options = lab_io_process::Options { cancel: job.cancel };
        var result = Completed { serial: job.serial, refresh: job.refresh, staged: job.staged, repo: job.repo, path: job.path,
            history: job.history, history_listing: job.history_listing, commit_files: job.commit_files, content: job.content, commit: job.commit,
            search_file: job.search_file, query: job.query, hit: job.hit };
        if job.refresh {
            let root = lab_git_repository::root(job.repo, options);
            if root.code != lab_git_repository::OK { result.error = root.error; }
            else {
                result.repo = root.path; result.watch_paths = lab_git_repository::watch_paths(root.path, options);
                if job.history_listing { result.page = lab_git_history::page(root.path, job.anchor, job.offset, 32, options); }
                else { result.files = lab_git_repository::files(root.path, job.staged, options); }
            }
        } else if job.search_file {
            let opened = lab_fs_search::open_hit(job.repo, job.hit, job.query, lab_fs_search::Options { ignore_case: job.ignore_case, cancel: job.cancel });
            if opened.code != 0 { result.diff = lab_git_repository::Diff { code: lab_git_repository::INVALID, error: opened.error }; }
            else {
                let patch = lab_text_diff::plain(opened.bytes);
                result.diff = lab_git_repository::Diff { code: if patch.code == 0 { lab_git_repository::OK } else { lab_git_repository::INVALID },
                    error: if patch.code == 0 { "" } else { lab_text_diff::message(patch.code) }, bytes: opened.bytes.len, patch: copy(patch) };
            }
        } else if job.commit_files { result.files = lab_git_history::files(job.repo, job.commit, options); }
        else if job.history {
            if job.content {
                let blob = lab_git_history::blob(job.repo, job.commit.id, job.path, options);
                if blob.code != 0 { result.diff = lab_git_repository::Diff { code: blob.code, error: blob.error }; }
                else {
                    let patch = lab_text_diff::plain(blob.object.bytes);
                    result.diff = lab_git_repository::Diff { code: if patch.code == 0 { lab_git_repository::OK } else { lab_git_repository::INVALID },
                        error: if patch.code == 0 { "" } else { lab_text_diff::message(patch.code) }, bytes: blob.object.size, patch: copy(patch) };
                }
            } else { result.diff = lab_git_history::diff(job.repo, job.commit, job.path, options); }
        } else if job.untracked && !job.staged { result.diff = lab_git_repository::untracked(job.repo, job.path, options); }
        else { result.diff = lab_git_repository::diff(job.repo, job.path, job.staged, options); }
        qput(result);
    }
}
fn start(state: State&, repo: const u8[:], path: const u8[:], staged: bool, refresh: bool, untracked: bool = false) -> bool {
    if repo.len == 0 || repo.len > 512 || path.len > 512 { return false; }
    let job = Job { refresh: refresh, staged: staged, untracked: untracked, repo: repo, path: path }; begin(state, job)
}
fn begin(state: State&, request: const Job&) -> bool {
    if state.busy || request.repo.len == 0 || state.serial == 0xFFFFFFFFFFFFFFFF { return false; }
    let token = lab_io_cancel::create(); if token.id == 0 { return false; }
    state.serial++; state.busy = true; state.refresh = request.refresh; state.token = token;
    var job = request; job.serial = state.serial; job.cancel = token; qput(job); true
}
fn finish(state: State&, result: const Completed&) -> bool {
    if !state.busy || state.serial != result.serial { return false; }
    state.busy = false; lab_io_cancel::destroy(state.token); true
}
