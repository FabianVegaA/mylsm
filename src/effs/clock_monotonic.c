#include <errno.h>
#include <stdint.h>
#include <time.h>

Term clock_monotonic_run(Env e, Term* f, IoWork* w) {
  struct timespec now;
  (void)f;
  (void)w;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
    return io_fail(e, errno, NULL);
  }
  uint64_t micros = (uint64_t)now.tv_sec * 1000000ULL + (uint64_t)now.tv_nsec / 1000ULL;
  return io_done(e, micros);
}

static void __attribute__((constructor)) clock_monotonic_use(void) {
  io_eff(CID(clock_monotonic), clock_monotonic_run);
}
