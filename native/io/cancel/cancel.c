#include "io/cancel/cancel.h"
#include <stddef.h>
#include <limits.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
static SRWLOCK gate = SRWLOCK_INIT;
static void lock(void) { AcquireSRWLockExclusive(&gate); }
static void unlock(void) { ReleaseSRWLockExclusive(&gate); }
#else
#include <pthread.h>
static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static void lock(void) { pthread_mutex_lock(&gate); }
static void unlock(void) { pthread_mutex_unlock(&gate); }
#endif

enum { GLAB_CANCEL_SLOTS = 64 };
struct glab_cancel_entry { uint32_t generation, leases; uint8_t live, requested; };
static struct glab_cancel_entry entries[GLAB_CANCEL_SLOTS];

/* Caller holds the gate; generation never wraps into an old handle. */
static glab_cancel_lease lookup(uint64_t id) {
    uint32_t slot = (uint32_t)id, gen = (uint32_t)(id >> 32);
    if (!slot || slot > GLAB_CANCEL_SLOTS || !gen) return NULL;
    glab_cancel_lease e = &entries[slot - 1];
    return e->live && e->generation == gen ? e : NULL;
}
uint64_t glab_cancel_create(void) {
    uint64_t id = 0; lock();
    for (uint32_t i = 0; i < GLAB_CANCEL_SLOTS; ++i) {
        glab_cancel_lease e = &entries[i];
        if (e->live || e->leases || e->generation == UINT32_MAX) continue;
        e->generation++; e->live = 1; e->requested = 0;
        id = ((uint64_t)e->generation << 32) | (i + 1); break;
    }
    unlock(); return id;
}
uint8_t glab_cancel_valid(uint64_t id) { lock(); uint8_t ok = lookup(id) != NULL; unlock(); return ok; }
uint8_t glab_cancel_request(uint64_t id) {
    lock(); glab_cancel_lease e = lookup(id); if (e) e->requested = 1;
    unlock(); return e != NULL;
}
uint8_t glab_cancel_requested(uint64_t id) {
    lock(); glab_cancel_lease e = lookup(id); uint8_t requested = e && e->requested;
    unlock(); return requested;
}
uint8_t glab_cancel_destroy(uint64_t id) {
    lock(); glab_cancel_lease e = lookup(id);
    if (e) { e->live = 0; e->requested = 1; }
    unlock(); return e != NULL;
}
uint8_t glab_cancel_acquire(uint64_t id, glab_cancel_lease *lease) {
    *lease = NULL; lock(); glab_cancel_lease e = lookup(id);
    if (e && e->leases < UINT32_MAX) { e->leases++; *lease = e; }
    unlock(); return *lease != NULL;
}
uint8_t glab_cancel_check(glab_cancel_lease lease) {
    if (!lease) return 0;
    lock(); uint8_t requested = lease->requested; unlock(); return requested;
}
void glab_cancel_release(glab_cancel_lease lease) {
    if (!lease) return;
    lock(); if (lease->leases) lease->leases--; unlock();
}
