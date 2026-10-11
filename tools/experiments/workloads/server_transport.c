/* Experiment-only transport. Framing, routing, state and pending writes live in Goose. */
#include <stdint.h>
#include <limits.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET exp_socket;
#define BAD_SOCKET INVALID_SOCKET
#define close_socket closesocket
static int would_block(void) { return WSAGetLastError() == WSAEWOULDBLOCK; }
static int nonblocking(exp_socket s) { u_long on = 1; return ioctlsocket(s, FIONBIO, &on) == 0; }
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
typedef int exp_socket;
#define BAD_SOCKET (-1)
#define close_socket close
static int would_block(void) { return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR; }
static int nonblocking(exp_socket s) { int flags = fcntl(s, F_GETFL, 0); return flags >= 0 && fcntl(s, F_SETFL, flags | O_NONBLOCK) == 0; }
#endif
static int64_t live_sockets;
static uint64_t encoded(exp_socket s) { return (uint64_t)s + 1; }
static exp_socket decoded(uint64_t s) { return (exp_socket)(s - 1); }
uint8_t exp_server_init(void) {
#ifdef _WIN32
    WSADATA data;
    return WSAStartup(MAKEWORD(2, 2), &data) == 0;
#else
    return 1;
#endif
}
uint64_t exp_server_listen(int64_t *port) {
    exp_socket s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    struct sockaddr_in address = {0};
    if (s == BAD_SOCKET) return 0;
    address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK); address.sin_port = 0;
    if (!nonblocking(s) || bind(s, (const struct sockaddr *)&address, sizeof(address)) || listen(s, 8)) { close_socket(s); return 0; }
#ifdef _WIN32
    int size = sizeof(address);
#else
    socklen_t size = sizeof(address);
#endif
    if (getsockname(s, (struct sockaddr *)&address, &size)) { close_socket(s); return 0; }
    *port = ntohs(address.sin_port); live_sockets++; return encoded(s);
}
uint64_t exp_server_accept(uint64_t listener, int32_t *code) {
    exp_socket s = accept(decoded(listener), 0, 0);
    if (s == BAD_SOCKET) { *code = would_block() ? 1 : 2; return 0; }
    /* A small requested send buffer makes real kernel backpressure observable
       in the bounded lab workload; the OS may round the actual capacity. */
    int on = 1, send_buffer = 4096;
    if (!nonblocking(s) || setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&on, sizeof(on)) ||
        setsockopt(s, SOL_SOCKET, SO_SNDBUF, (const char *)&send_buffer, sizeof(send_buffer))) { close_socket(s); *code = 2; return 0; }
    *code = 0; live_sockets++; return encoded(s);
}
int64_t exp_server_receive(uint64_t socket_id, uint8_t *out, int64_t capacity) {
    if (!socket_id || capacity < 1 || capacity > 4096) return -2;
    int n = (int)recv(decoded(socket_id), (char *)out, (int)capacity, 0);
    return n >= 0 ? n : would_block() ? -1 : -2;
}
int64_t exp_server_send(uint64_t socket_id, const uint8_t *bytes, int64_t length) {
    if (!socket_id || length < 1 || length > 4096) return -2;
#if defined(MSG_NOSIGNAL) && !defined(_WIN32)
    int flags = MSG_NOSIGNAL;
#else
    int flags = 0;
#endif
    int n = (int)send(decoded(socket_id), (const char *)bytes, (int)length, flags);
    return n > 0 ? n : n == 0 ? -2 : would_block() ? -1 : -2;
}
uint8_t exp_server_close(uint64_t socket_id) {
    if (!socket_id || close_socket(decoded(socket_id))) return 0;
    live_sockets--; return 1;
}
int64_t exp_server_live(void) { return live_sockets; }
uint8_t exp_server_shutdown(void) {
    if (live_sockets) return 0;
#ifdef _WIN32
    return WSACleanup() == 0;
#else
    return 1;
#endif
}
