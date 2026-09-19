// Fs.exists — distinguish an absent path from metadata failures.

#include <errno.h>
#include <sys/stat.h>

Term exists_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* path = io_cstr(e, f[0], &n);
  struct stat st;
  int rc = stat(path, &st);
  int err = errno;
  free(path);
  (void)w;
  if (rc == 0) {
    return io_done(e, term_pak(CID_TRUE, 0));
  }
  if (err == ENOENT) {
    return io_done(e, term_pak(CID_FALSE, 0));
  }
  return io_fail(e, err, NULL);
}

static void __attribute__((constructor)) exists_use(void) {
  io_eff(CID_EXISTS, exists_run, 0);
}
