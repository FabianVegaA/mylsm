#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

Term unix_socket_create_run(Env e, Term* f, IoWork* w) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  int err = fd < 0 ? errno : 0;
#if defined(SO_NOSIGPIPE)
  int no_sigpipe = 1;
  if (fd >= 0 && setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe,
      sizeof(no_sigpipe)) < 0) {
    err = errno;
    close(fd);
    fd = -1;
  }
#endif
  if (fd >= 0 && fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) {
    err = errno;
    close(fd);
    fd = -1;
  }
  (void)f;
  (void)w;
  return err != 0 ? io_fail(e, err, NULL) : io_done(e, io_hand(fd));
}

static void __attribute__((constructor)) unix_socket_create_use(void) {
  io_eff(CID(unix_socket_create), unix_socket_create_run);
}
