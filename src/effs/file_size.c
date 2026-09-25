// Fs.file_size — read-only byte size via stat, mirroring exists.c.

#include <errno.h>
#include <sys/stat.h>

Term file_size_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* path = io_cstr(e, f[0], &n);
  struct stat st;
  int rc = stat(path, &st);
  int err = errno;
  free(path);
  (void)w;
  if (rc != 0) { return io_fail(e, err, NULL); }
  if (st.st_size < 0) { return io_fail(e, 5, NULL); }
  return io_done(e, (uint64_t)st.st_size);
}

static void __attribute__((constructor)) file_size_use(void) {
  io_eff(CID_FILE_SIZE, file_size_run, 0);
}
