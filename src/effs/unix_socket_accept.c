#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

Term unix_socket_accept_run(Env e, Term* f, IoWork* w) {
  int server = (int)io_hand(f[0]);
#if defined(__APPLE__)
  int client = accept(server, NULL, NULL);
  int err = client < 0 ? errno : 0;
  if (client >= 0 && fcntl(client, F_SETFD, FD_CLOEXEC) < 0) {
    err = errno;
    close(client);
    client = -1;
  }
#else
  int client = accept4(server, NULL, NULL, SOCK_CLOEXEC);
  int err = client < 0 ? errno : 0;
#endif
  (void)w;
  Term result = err == 0 ? io_done(e, io_hand(client))
    : io_fail(e, err, NULL);
  return io_tup(e, io_hand(server), result);
}

static void __attribute__((constructor)) unix_socket_accept_use(void) {
  io_eff(CID(unix_socket_accept), unix_socket_accept_run);
}
