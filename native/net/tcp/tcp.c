/* No framing, response queues or application state belong in this transport. */
#include "net/tcp/tcp.h"
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET tcp_socket;
#define BAD_SOCKET INVALID_SOCKET
#define close_socket closesocket
static int would_block(void) { int e = WSAGetLastError(); return e == WSAEWOULDBLOCK || e == WSAEINTR; }
static int pending_connect(void) { int e = WSAGetLastError(); return e == WSAEWOULDBLOCK || e == WSAEINPROGRESS; }
static int nonblocking(tcp_socket s) { u_long on = 1; return ioctlsocket(s, FIONBIO, &on) == 0; }
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
typedef int tcp_socket;
#define BAD_SOCKET (-1)
#define close_socket close
static int would_block(void) { return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR; }
static int pending_connect(void) { return errno == EINPROGRESS || errno == EINTR; }
static int nonblocking(tcp_socket s) { int f = fcntl(s, F_GETFL, 0); return f >= 0 && fcntl(s, F_SETFL, f | O_NONBLOCK) == 0; }
#endif
typedef struct { tcp_socket socket; uint32_t generation; uint8_t live; } Entry;
static Entry entries[64];
static int64_t live_sockets, owners;
static Entry *lookup(uint64_t id) {
    uint32_t slot = (uint32_t)id;
    if (!slot || slot > 64) return 0;
    Entry *e = &entries[slot - 1];
    return e->live && e->generation == (uint32_t)(id >> 32) ? e : 0;
}
static uint64_t retain(tcp_socket socket) {
    for (uint32_t slot = 0; slot < 64; slot++) {
        Entry *e = &entries[slot];
        if (!e->live && e->generation != UINT32_MAX) {
            e->generation++; e->socket = socket; e->live = 1; live_sockets++;
            return ((uint64_t)e->generation << 32) | (slot + 1);
        }
    }
    close_socket(socket); return 0;
}
static int configure(tcp_socket s, int64_t send_buffer) {
    int on = 1;
    if (!nonblocking(s) || setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&on, sizeof(on))) return 0;
#ifdef SO_NOSIGPIPE
    if (setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, (const char *)&on, sizeof(on))) return 0;
#endif
    if (send_buffer) {
        int size = (int)send_buffer;
        if (setsockopt(s, SOL_SOCKET, SO_SNDBUF, (const char *)&size, sizeof(size))) return 0;
    }
    return 1;
}
uint8_t glab_tcp_init(void) {
    if (owners == 0) {
#ifdef _WIN32
        WSADATA data; if (WSAStartup(MAKEWORD(2, 2), &data)) return 0;
#endif
    }
    owners++; return 1;
}
uint8_t glab_tcp_shutdown(void) {
    if (owners == 0 || (owners == 1 && live_sockets)) return 0;
#ifdef _WIN32
    if (owners == 1 && WSACleanup()) return 0;
#endif
    owners--; return 1;
}
uint64_t glab_tcp_listen(int64_t requested_port, int64_t *port) {
    if (!owners || !port || requested_port < 0 || requested_port > 65535) return 0;
    tcp_socket s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    struct sockaddr_in address = {0};
    if (s == BAD_SOCKET) return 0;
    address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK); address.sin_port = htons((uint16_t)requested_port);
    if (!nonblocking(s) || bind(s, (const struct sockaddr *)&address, sizeof(address)) || listen(s, 16)) { close_socket(s); return 0; }
#ifdef _WIN32
    int size = sizeof(address);
#else
    socklen_t size = sizeof(address);
#endif
    if (getsockname(s, (struct sockaddr *)&address, &size)) { close_socket(s); return 0; }
    uint64_t id = retain(s); if (id) *port = ntohs(address.sin_port); return id;
}
uint64_t glab_tcp_accept(uint64_t listener, int64_t send_buffer, int32_t *code) {
    Entry *e = lookup(listener); *code = 2;
    if (!e || send_buffer < 0 || send_buffer > 1048576) return 0;
    tcp_socket s = accept(e->socket, 0, 0);
    if (s == BAD_SOCKET) { *code = would_block() ? 1 : 2; return 0; }
    if (!configure(s, send_buffer)) { close_socket(s); return 0; }
    uint64_t id = retain(s); *code = id ? 0 : 2; return id;
}
uint64_t glab_tcp_connect(int64_t port, int64_t timeout_ms, int32_t *code) {
    *code = 2;
    if (!owners || port < 1 || port > 65535 || timeout_ms < 1 || timeout_ms > 5000) return 0;
    tcp_socket s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == BAD_SOCKET) return 0;
    if (!configure(s, 0)) { close_socket(s); return 0; }
    struct sockaddr_in address = {0}; address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK); address.sin_port = htons((uint16_t)port);
    if (connect(s, (const struct sockaddr *)&address, sizeof(address))) {
        if (!pending_connect()) { close_socket(s); return 0; }
#ifndef _WIN32
        if (s >= FD_SETSIZE) { close_socket(s); return 0; }
#endif
        fd_set writes, errors; FD_ZERO(&writes); FD_ZERO(&errors); FD_SET(s, &writes); FD_SET(s, &errors);
        struct timeval wait; wait.tv_sec = (long)(timeout_ms / 1000); wait.tv_usec = (long)((timeout_ms % 1000) * 1000);
        int n = select((int)(s + 1), 0, &writes, &errors, &wait);
        int error = 0;
#ifdef _WIN32
        int size = sizeof(error);
#else
        socklen_t size = sizeof(error);
#endif
        if (n <= 0 || getsockopt(s, SOL_SOCKET, SO_ERROR, (char *)&error, &size) || error) { close_socket(s); return 0; }
    }
    uint64_t id = retain(s); *code = id ? 0 : 2; return id;
}
int64_t glab_tcp_receive(uint64_t id, uint8_t *out, int64_t capacity) {
    Entry *e = lookup(id); if (!e || !out || capacity < 1 || capacity > 4096) return -2;
    int n = (int)recv(e->socket, (char *)out, (int)capacity, 0); return n >= 0 ? n : would_block() ? -1 : -2;
}
int64_t glab_tcp_send(uint64_t id, const uint8_t *bytes, int64_t length) {
    Entry *e = lookup(id); if (!e || !bytes || length < 1 || length > 4096) return -2;
#ifdef MSG_NOSIGNAL
    int flags = MSG_NOSIGNAL;
#else
    int flags = 0;
#endif
    int n = (int)send(e->socket, (const char *)bytes, (int)length, flags); return n > 0 ? n : n == 0 ? -2 : would_block() ? -1 : -2;
}
uint8_t glab_tcp_close(uint64_t id) {
    Entry *e = lookup(id); if (!e || close_socket(e->socket)) return 0;
    e->live = 0; live_sockets--; return 1;
}
int64_t glab_tcp_live(void) { return live_sockets; }
