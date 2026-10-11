#include <errno.h>
#include <stdint.h>
#include <time.h>

Term sleep_ms_run(Env e, Term* f, IoWork* w) {
  uint64_t millis = (uint64_t)f[0];
  struct timespec delay = {
    .tv_sec = (time_t)(millis / 1000ULL),
    .tv_nsec = (long)((millis % 1000ULL) * 1000000ULL)
  };
  (void)w;
  if (nanosleep(&delay, NULL) != 0) {
    return io_fail(e, errno, NULL);
  }
  return io_done(e, term_pak(CID(Unit), 0));
}

static void __attribute__((constructor)) sleep_ms_use(void) {
  io_eff(CID(sleep_ms), sleep_ms_run);
}
