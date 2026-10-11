#ifndef GLAB_TCP_H
#define GLAB_TCP_H
#include <stdint.h>
/* Main-thread owned, generation-checked registry; IPv4 loopback only. */
uint8_t glab_tcp_init(void);
uint8_t glab_tcp_shutdown(void);
uint64_t glab_tcp_listen(int64_t requested_port, int64_t *port);
uint64_t glab_tcp_accept(uint64_t listener, int64_t send_buffer, int32_t *code);
uint64_t glab_tcp_connect(int64_t port, int64_t timeout_ms, int32_t *code);
int64_t glab_tcp_receive(uint64_t id, uint8_t *out, int64_t capacity);
int64_t glab_tcp_send(uint64_t id, const uint8_t *bytes, int64_t length);
uint8_t glab_tcp_close(uint64_t id);
int64_t glab_tcp_live(void);
#endif
