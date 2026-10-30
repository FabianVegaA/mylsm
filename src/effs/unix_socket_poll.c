#include <errno.h>
#include <poll.h>

Term unix_socket_poll_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand(f[0]);
  uint64_t requested = (uint64_t)f[1];
  uint64_t timeout = (uint64_t)f[2];
  struct pollfd descriptor = {
    .fd = fd,
    .events = (short)requested,
    .revents = 0
  };
  int wait_ms = timeout > 2147483647u ? 2147483647 : (int)timeout;
  int rc = poll(&descriptor, 1, wait_ms);
  int err = rc < 0 ? errno : 0;
  uint32_t ready = rc > 0 ? (uint16_t)descriptor.revents : 0;
  (void)w;
  Term result = err == 0 ? io_done(e, ready) : io_fail(e, err, NULL);
  return io_tup(e, io_hand(fd), result);
}

static void __attribute__((constructor)) unix_socket_poll_use(void) {
  io_eff(CID(unix_socket_poll), unix_socket_poll_run);
}
