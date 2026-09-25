// Fs.make_dir — create a directory (0700 set separately via chmod).
// Fast metadata syscall: synchronous, like Base's file_close.c.

#include <sys/stat.h>

Term make_dir_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* path = io_cstr(e, f[0], &n);
  int rc = mkdir(path, 0700);
  int err = errno;
  free(path);
  (void)w;
  return rc == 0 ? io_done(e, term_pak(CID(Unit), 0)) : io_fail(e, err, NULL);
}

static void __attribute__((constructor)) make_dir_use(void) {
  io_eff(CID(make_dir), make_dir_run, 0);
}
