#include <errno.h>
#include <limits.h>
#include <sys/socket.h>

Term unix_socket_listen_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand(f[0]);
  uint64_t backlog = (uint64_t)f[1];
  int rc = backlog > INT_MAX ? -1 : listen(fd, (int)backlog);
  int err = backlog > INT_MAX ? EINVAL : (rc == 0 ? 0 : errno);
  (void)w;
  Term result = err == 0 ? io_done(e, term_pak(CID(Unit), 0))
    : io_fail(e, err, NULL);
  return io_tup(e, io_hand(fd), result);
}

static void __attribute__((constructor)) unix_socket_listen_use(void) {
  io_eff(CID(unix_socket_listen), unix_socket_listen_run);
}
