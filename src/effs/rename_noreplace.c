#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#if defined(__linux__)
#include <linux/fs.h>
#include <sys/syscall.h>
#endif

Term rename_noreplace_run(Env e, Term* f, IoWork* w) {
  u64 old_size = 0;
  u64 new_size = 0;
  char* old_path = io_cstr(e, f[0], &old_size);
  char* new_path = io_cstr(e, f[1], &new_size);
  (void)w;
#if defined(__APPLE__)
  int rc = renamex_np(old_path, new_path, RENAME_EXCL);
#elif defined(__linux__)
  int rc = (int)syscall(SYS_renameat2, AT_FDCWD, old_path, AT_FDCWD,
    new_path, RENAME_NOREPLACE);
#else
  errno = ENOTSUP;
  int rc = -1;
#endif
  int error = rc == 0 ? 0 : errno;
  free(old_path);
  free(new_path);
  return error == 0
    ? io_done(e, term_pak(CID(Unit), 0))
    : io_fail(e, error, NULL);
}

static void __attribute__((constructor)) rename_noreplace_use(void) {
  io_eff(CID(rename_noreplace), rename_noreplace_run);
}
