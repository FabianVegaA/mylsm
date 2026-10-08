// Fs.make_dir — create a directory (0700 set separately via chmod).
// Fast metadata syscall: synchronous, like Base's file_close.c.

#define MYLSM_IO_EFF_PICK(_1, _2, _3, NAME, ...) NAME
#define MYLSM_IO_EFF_2(name, run) io_eff(name, run)
#define MYLSM_IO_EFF_3(name, run, legacy) io_eff(name, run)
#define io_eff(...) MYLSM_IO_EFF_PICK(__VA_ARGS__, MYLSM_IO_EFF_3, MYLSM_IO_EFF_2)(__VA_ARGS__)

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
  io_eff(CID(make_dir), make_dir_run);
}
