#include "io/process/process.h"
#include "io/cancel/cancel.h"
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <pthread.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#endif
enum { OK, INVALID, SPAWN, IO, LIMIT, TIMEOUT, CANCELLED, MEMORY };
static int valid_text(const uint8_t *p, int64_t n, int empty) {
    return n >= (empty ? 0 : 1) && n <= 32768 && (n == 0 || (p && !memchr(p, 0, (size_t)n)));
}
#ifdef _WIN32
static wchar_t *wide(const uint8_t *p, int64_t n) {
    if (!n) return NULL;
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)p, (int)n, NULL, 0);
    if (!count) return NULL;
    wchar_t *s = calloc((size_t)count + 1, sizeof *s);
    if (s) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)p, (int)n, s, count);
    return s;
}
/* Always quote every argument using the Microsoft CRT backslash/quote rules. */
static int quote(wchar_t *cmd, size_t *used, const wchar_t *arg) {
    size_t len = wcslen(arg);
    if (*used + len * 2 + 4 >= 32767) return 0;
    if (*used) cmd[(*used)++] = L' ';
    cmd[(*used)++] = L'"';
    size_t slashes = 0;
    for (size_t i = 0; i <= len; i++) {
        if (arg[i] == L'\\') { slashes++; continue; }
        size_t n = (arg[i] == L'"' || !arg[i]) ? slashes * 2 : slashes;
        while (n--) cmd[(*used)++] = L'\\';
        if (arg[i] == L'"') cmd[(*used)++] = L'\\';
        if (!arg[i]) break;
        cmd[(*used)++] = arg[i]; slashes = 0;
    }
    cmd[(*used)++] = L'"'; cmd[*used] = 0; return 1;
}
static int drain(HANDLE pipe, int *open, glab_process_sink sink, void *ctx, int64_t *used, int64_t limit) {
    if (!*open) return OK;
    /* Alternate streams even when one producer never stops writing. */
    for (int turn = 0; turn < 16; turn++) {
        DWORD available = 0;
        if (!PeekNamedPipe(pipe, NULL, 0, NULL, &available, NULL)) {
            if (GetLastError() == ERROR_BROKEN_PIPE) { *open = 0; return OK; }
            return IO;
        }
        if (!available) return OK;
        uint8_t bytes[4096]; DWORD got = 0, n = available < sizeof bytes ? available : (DWORD)sizeof bytes;
        if (!ReadFile(pipe, bytes, n, &got, NULL)) return IO;
        if ((int64_t)got > limit - *used) return LIMIT;
        sink(ctx, bytes, got); *used += got;
    }
    return OK;
}
struct input_writer { HANDLE pipe; glab_process_input *hooks; volatile LONG stop; };
static DWORD WINAPI write_input(void *arg) {
    struct input_writer *w = arg; int32_t code = OK;
    while (!InterlockedCompareExchange(&w->stop, 0, 0)) {
        uint8_t bytes[4096]; size_t length = 0;
        int state = w->hooks->peek(w->hooks->context, bytes, sizeof bytes, &length);
        if (state == 2) break;
        if (!state) { Sleep(1); continue; }
        size_t at = 0;
        while (at < length && !InterlockedCompareExchange(&w->stop, 0, 0)) {
            DWORD sent = 0;
            if (!WriteFile(w->pipe, bytes + at, (DWORD)(length - at), &sent, NULL) || !sent) {
                if (!InterlockedCompareExchange(&w->stop, 0, 0)) code = IO;
                goto done;
            }
            w->hooks->ack(w->hooks->context, sent); at += sent;
        }
    }
done:
    CloseHandle(w->pipe); w->pipe = NULL;
    w->hooks->closed(w->hooks->context, code); return 0;
}
static int32_t run_platform(const uint8_t *program, int64_t plen, const uint8_t *cwd, int64_t clen,
    const uint8_t *args, int64_t alen, int64_t timeout, int64_t limit, glab_cancel_lease lease,
    glab_process_sink out, void *oc, glab_process_sink err, void *ec, glab_process_input *hooks, int64_t *exit_code) {
    int32_t code = SPAWN;
    wchar_t *exe = wide(program, plen), *directory = wide(cwd, clen), *command = calloc(32768, sizeof(wchar_t));
    HANDLE reads[2] = {0}, writes[2] = {0}, input = INVALID_HANDLE_VALUE, job = NULL;
    PROCESS_INFORMATION pi = {0}; STARTUPINFOEXW si = {0}; SIZE_T attr_size = 0; int attrs_ready = 0;
    struct input_writer writer = {0}; HANDLE writer_thread = NULL;
    if (!exe || (clen && !directory)) { code = INVALID; goto done; }
    if (!command) { code = MEMORY; goto done; }
    size_t used = 0;
    if (!quote(command, &used, exe)) { code = INVALID; goto done; }
    for (int64_t at = 0; at < alen;) {
        int64_t end = at; while (end < alen && args[end]) end++;
        wchar_t *arg = end == at ? calloc(1, sizeof(wchar_t)) : wide(args + at, end - at);
        if (!arg || !quote(command, &used, arg)) { free(arg); code = INVALID; goto done; }
        free(arg); at = end + 1;
    }
    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    for (int i = 0; i < 2; i++) {
        if (!CreatePipe(&reads[i], &writes[i], &sa, 0) || !SetHandleInformation(reads[i], HANDLE_FLAG_INHERIT, 0)) goto done;
    }
    if (hooks) {
        if (!CreatePipe(&input, &writer.pipe, &sa, 0) || !SetHandleInformation(writer.pipe, HANDLE_FLAG_INHERIT, 0)) goto done;
        writer.hooks = hooks;
    } else input = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
    if (input == INVALID_HANDLE_VALUE) goto done;
    si.StartupInfo.cb = sizeof si; si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput = input; si.StartupInfo.hStdOutput = writes[0]; si.StartupInfo.hStdError = writes[1];
    InitializeProcThreadAttributeList(NULL, 1, 0, &attr_size);
    si.lpAttributeList = malloc(attr_size);
    if (!si.lpAttributeList) { code = MEMORY; goto done; }
    if (!InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &attr_size)) goto done;
    attrs_ready = 1; HANDLE inherited[3] = {input, writes[0], writes[1]};
    if (!UpdateProcThreadAttribute(si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
        inherited, sizeof inherited, NULL, NULL)) goto done;
    job = CreateJobObjectW(NULL, NULL);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0}; limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof limits)) goto done;
    if (!CreateProcessW(NULL, command, NULL, NULL, TRUE,
        CREATE_NO_WINDOW | CREATE_SUSPENDED | EXTENDED_STARTUPINFO_PRESENT, NULL, directory, &si.StartupInfo, &pi)) goto done;
    if (!AssignProcessToJobObject(job, pi.hProcess)) { TerminateProcess(pi.hProcess, 1); goto done; }
    if (ResumeThread(pi.hThread) == (DWORD)-1) goto done;
    for (int i = 0; i < 2; i++) { CloseHandle(writes[i]); writes[i] = NULL; }
    CloseHandle(input); input = INVALID_HANDLE_VALUE;
    if (hooks) {
        writer_thread = CreateThread(NULL, 0, write_input, &writer, 0, NULL);
        if (!writer_thread) { code = MEMORY; goto done; }
    }
    ULONGLONG started = GetTickCount64(); int open[2] = {1, 1}; int64_t captured = 0; int finished = 0;
    code = OK;
    while (open[0] || open[1] || !finished) {
        if (glab_cancel_check(lease)) { code = CANCELLED; break; }
        if (GetTickCount64() - started >= (ULONGLONG)timeout) { code = TIMEOUT; break; }
        code = drain(reads[0], &open[0], out, oc, &captured, limit);
        if (code == OK) code = drain(reads[1], &open[1], err, ec, &captured, limit);
        if (code != OK) break;
        DWORD wait = WaitForSingleObject(pi.hProcess, 0);
        if (wait == WAIT_FAILED) { code = IO; break; }
        if (wait == WAIT_OBJECT_0 && !finished) {
            DWORD status = 0; if (!GetExitCodeProcess(pi.hProcess, &status)) { code = IO; break; }
            *exit_code = status; finished = 1;
            /* Background descendants cannot keep inherited pipes alive. */
            CloseHandle(job); job = NULL;
        }
        if (open[0] || open[1] || !finished) Sleep(1);
    }
done:
    /* Stop future writes before killing readers. Job closure breaks blocked
       anonymous-pipe writes; the output worker never waits on WriteFile. */
    InterlockedExchange(&writer.stop, 1);
    if (job) CloseHandle(job);
    if (pi.hProcess) { WaitForSingleObject(pi.hProcess, INFINITE); CloseHandle(pi.hProcess); }
    if (writer_thread) { CancelSynchronousIo(writer_thread); WaitForSingleObject(writer_thread, INFINITE); CloseHandle(writer_thread); }
    else if (writer.pipe) CloseHandle(writer.pipe);
    if (pi.hThread) CloseHandle(pi.hThread);
    if (attrs_ready) DeleteProcThreadAttributeList(si.lpAttributeList);
    free(si.lpAttributeList);
    if (input != INVALID_HANDLE_VALUE) CloseHandle(input);
    for (int i = 0; i < 2; i++) { if (reads[i]) CloseHandle(reads[i]); if (writes[i]) CloseHandle(writes[i]); }
    free(exe); free(directory); free(command); return code;
}
#else
static int64_t millis(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000; }
static void spawn_error(int pipe) { int error = errno; ssize_t ignored = write(pipe, &error, sizeof error); (void)ignored; _exit(127); }
/* Block SIGPIPE only around this thread's write. Consume a newly generated
   EPIPE signal without changing the application's process-wide disposition. */
static ssize_t pipe_write(int fd, const uint8_t *bytes, size_t length) {
    sigset_t one, old, pending; sigemptyset(&one); sigaddset(&one, SIGPIPE);
    if (pthread_sigmask(SIG_BLOCK, &one, &old)) { errno = EIO; return -1; }
    if (sigpending(&pending)) { pthread_sigmask(SIG_SETMASK, &old, NULL); errno = EIO; return -1; }
    int had = sigismember(&pending, SIGPIPE);
    ssize_t n = write(fd, bytes, length); int error = errno;
    if (n < 0 && error == EPIPE && !had && !sigpending(&pending) && sigismember(&pending, SIGPIPE)) {
        int signal; while (sigwait(&one, &signal) == EINTR) {}
    }
    pthread_sigmask(SIG_SETMASK, &old, NULL); errno = error; return n;
}
static int32_t run_platform(const uint8_t *program, int64_t plen, const uint8_t *cwd, int64_t clen,
    const uint8_t *args, int64_t alen, int64_t timeout, int64_t limit, glab_cancel_lease lease,
    glab_process_sink out, void *oc, glab_process_sink err, void *ec, glab_process_input *hooks, int64_t *exit_code) {
    char *exe = calloc((size_t)plen + 1, 1), *directory = calloc((size_t)clen + 1, 1), *blob = calloc((size_t)alen + 1, 1);
    int fds[2][2] = {{-1,-1},{-1,-1}}, exec_error[2] = {-1,-1}, code = SPAWN, status = 0; pid_t pid = -1;
    int input_fds[2] = {-1, -1};
    if (!exe || !directory || !blob) { code = MEMORY; goto done; }
    memcpy(exe, program, (size_t)plen); if (clen) memcpy(directory, cwd, (size_t)clen); if (alen) memcpy(blob, args, (size_t)alen);
    char *argv[66] = {exe}; int count = 1;
    for (int64_t at = 0; at < alen;) { argv[count++] = blob + at; at += (int64_t)strlen(blob + at) + 1; }
    for (int i = 0; i < 2; i++) {
        if (pipe(fds[i])) goto done;
        if (fcntl(fds[i][0], F_SETFD, FD_CLOEXEC) < 0 || fcntl(fds[i][1], F_SETFD, FD_CLOEXEC) < 0 ||
            fcntl(fds[i][0], F_SETFL, O_NONBLOCK) < 0) goto done;
    }
    if (pipe(exec_error) || fcntl(exec_error[0], F_SETFD, FD_CLOEXEC) < 0 || fcntl(exec_error[1], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(exec_error[0], F_SETFL, O_NONBLOCK) < 0) goto done;
    if (hooks && (pipe(input_fds) || fcntl(input_fds[0], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(input_fds[1], F_SETFD, FD_CLOEXEC) < 0 || fcntl(input_fds[1], F_SETFL, O_NONBLOCK) < 0)) goto done;
    pid = fork(); if (pid < 0) goto done;
    if (!pid) {
        close(exec_error[0]);
        setpgid(0, 0); int input = hooks ? input_fds[0] : open("/dev/null", O_RDONLY);
        if (input < 0 || dup2(input, 0) < 0 || dup2(fds[0][1], 1) < 0 || dup2(fds[1][1], 2) < 0 || (clen && chdir(directory))) spawn_error(exec_error[1]);
        close(input); for (int i = 0; i < 2; i++) { close(fds[i][0]); close(fds[i][1]); }
        if (hooks) close(input_fds[1]);
        execvp(exe, argv); spawn_error(exec_error[1]);
    }
    setpgid(pid, pid);
    if (input_fds[0] >= 0) { close(input_fds[0]); input_fds[0] = -1; }
    close(exec_error[1]); exec_error[1] = -1;
    for (int i = 0; i < 2; i++) { close(fds[i][1]); fds[i][1] = -1; }
    int open_pipes[2] = {1,1}, finished = 0; int64_t used = 0, started = millis(); code = OK;
    while (open_pipes[0] || open_pipes[1] || !finished) {
        if (glab_cancel_check(lease)) { code = CANCELLED; break; }
        if (millis() - started >= timeout) { code = TIMEOUT; break; }
        if (exec_error[0] >= 0) {
            int failure = 0; ssize_t n = read(exec_error[0], &failure, sizeof failure);
            if (n > 0) { code = SPAWN; break; }
            if (!n) { close(exec_error[0]); exec_error[0] = -1; }
            else if (n < 0 && errno != EAGAIN && errno != EINTR) { code = IO; break; }
        }
        for (int i = 0; i < 2 && code == OK; i++) {
            if (!open_pipes[i]) continue;
            for (int turn = 0; turn < 16; turn++) {
                uint8_t bytes[4096]; ssize_t n = read(fds[i][0], bytes, sizeof bytes);
                if (!n) { open_pipes[i] = 0; break; }
                if (n < 0) { if (errno != EAGAIN && errno != EINTR) code = IO; break; }
                if (n > limit - used) { code = LIMIT; break; }
                (i ? err : out)(i ? ec : oc, bytes, (size_t)n); used += n;
            }
        }
        if (code != OK) break;
        if (input_fds[1] >= 0) {
            /* Fairness: one bounded stdin write per capture iteration. */
            uint8_t bytes[4096]; size_t length = 0;
            int state = hooks->peek(hooks->context, bytes, sizeof bytes, &length);
            if (state == 2) { close(input_fds[1]); input_fds[1] = -1; hooks->closed(hooks->context, OK); }
            else if (state == 1) {
                ssize_t n = pipe_write(input_fds[1], bytes, length);
                if (n > 0) hooks->ack(hooks->context, (size_t)n);
                else if (!n || (errno != EAGAIN && errno != EINTR)) {
                    close(input_fds[1]); input_fds[1] = -1; hooks->closed(hooks->context, IO);
                }
            }
        }
        if (!finished) {
            pid_t waited = waitpid(pid, &status, WNOHANG);
            if (waited < 0 && errno != EINTR) { code = IO; break; }
            if (waited == pid) { finished = 1; *exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status); kill(-pid, SIGKILL); }
        }
        struct timespec delay = {0, 1000000}; nanosleep(&delay, NULL);
    }
    if (!finished) { kill(-pid, SIGKILL); kill(pid, SIGKILL); while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {} }
done:
    for (int i = 0; i < 2; i++) if (input_fds[i] >= 0) close(input_fds[i]);
    for (int i = 0; i < 2; i++) if (exec_error[i] >= 0) close(exec_error[i]);
    for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) if (fds[i][j] >= 0) close(fds[i][j]);
    free(exe); free(directory); free(blob); return code;
}
#endif
int32_t glab_process_run_input(const uint8_t *program, int64_t plen, const uint8_t *cwd, int64_t clen,
    const uint8_t *args, int64_t alen, int64_t timeout, int64_t limit, uint64_t cancel,
    glab_process_sink out, void *oc, glab_process_sink err, void *ec, glab_process_input *input, int64_t *exit_code) {
    if (!exit_code) return INVALID;
    *exit_code = -1;
    if (!valid_text(program, plen, 0) || !valid_text(cwd, clen, 1) || alen < 0 || alen > 32768 ||
        (alen && (!args || args[alen - 1])) || timeout < 1 || timeout > 60000 || limit < 1 || limit > 2097152 || !out || !err ||
        (input && (!input->peek || !input->ack || !input->closed))) return INVALID;
    int count = 0; for (int64_t i = 0; i < alen; i++) if (!args[i]) count++;
    if (count > 64) return INVALID;
    glab_cancel_lease lease = NULL;
    if (cancel && !glab_cancel_acquire(cancel, &lease)) return INVALID;
    int32_t code = glab_cancel_check(lease) ? CANCELLED : run_platform(program, plen, cwd, clen, args, alen,
        timeout, limit, lease, out, oc, err, ec, input, exit_code);
    if (input) input->closed(input->context, code);
    glab_cancel_release(lease); return code;
}
int32_t glab_process_run(const uint8_t *program, int64_t plen, const uint8_t *cwd, int64_t clen,
    const uint8_t *args, int64_t alen, int64_t timeout, int64_t limit, uint64_t cancel,
    glab_process_sink out, void *oc, glab_process_sink err, void *ec, int64_t *exit_code) {
    return glab_process_run_input(program, plen, cwd, clen, args, alen, timeout, limit, cancel,
        out, oc, err, ec, NULL, exit_code);
}
