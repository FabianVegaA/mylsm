// Fs.chmod — set permission bits (0600 files / 0700 dirs, spec §8).
// Fast metadata syscall: synchronous, like Base's file_close.c.

#include <sys/stat.h>

Term chmod_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* path = io_cstr(e, f[0], &n);
  uint32_t bits = f[1] < 010000 ? (uint32_t)f[1] : 0600;
  int rc = chmod(path, (mode_t)bits);
  int err = errno;
  free(path);
  (void)w;
  return rc == 0 ? io_done(e, term_pak(CID(Unit), 0)) : io_fail(e, err, NULL);
}

static void __attribute__((constructor)) chmod_use(void) {
  io_eff(CID(chmod), chmod_run, 0);
}
