#include <errno.h>
#include <fcntl.h>

Term unix_socket_nonblocking_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand(f[0]);
  int flags = fcntl(fd, F_GETFL);
  int err = flags < 0 ? errno : 0;
  if (err == 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    err = errno;
  }
  if (err == 0) {
    int descriptor_flags = fcntl(fd, F_GETFD);
    err = descriptor_flags < 0 ? errno : 0;
    if (err == 0 && fcntl(fd, F_SETFD, descriptor_flags | FD_CLOEXEC) < 0) {
      err = errno;
    }
  }
  (void)w;
  Term result = err == 0 ? io_done(e, term_pak(CID(Unit), 0))
    : io_fail(e, err, NULL);
  return io_tup(e, io_hand(fd), result);
}

static void __attribute__((constructor)) unix_socket_nonblocking_use(void) {
  io_eff(CID(unix_socket_nonblocking), unix_socket_nonblocking_run);
}
