#include <errno.h>
#include <stdint.h>
#include <unistd.h>

Term truncate_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* path = io_cstr(e, f[0], &n);
  uint64_t offset = (uint64_t)f[1];
  int rc = offset > INT64_MAX ? -1 : truncate(path, (off_t)offset);
  int err = offset > INT64_MAX ? EOVERFLOW : errno;
  free(path);
  (void)w;
  return rc == 0 ? io_done(e, term_pak(CID(Unit), 0)) : io_fail(e, err, NULL);
}

static void __attribute__((constructor)) truncate_use(void) {
  io_eff(CID(truncate), truncate_run);
}
