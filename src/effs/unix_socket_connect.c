#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>

Term unix_socket_connect_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand(f[0]);
  uint64_t size = 0;
  char* path = io_cstr(e, f[1], &size);
  struct sockaddr_un address;
  memset(&address, 0, sizeof(address));
  size_t path_size = strlen(path);
  int rc = -1;
  int err = ENAMETOOLONG;
  if (path_size < sizeof(address.sun_path)) {
    address.sun_family = AF_UNIX;
    memcpy(address.sun_path, path, path_size + 1);
#if defined(__APPLE__)
    address.sun_len = (unsigned char)(offsetof(struct sockaddr_un, sun_path) + path_size + 1);
#endif
    rc = connect(fd, (struct sockaddr*)&address,
      (socklen_t)(offsetof(struct sockaddr_un, sun_path) + path_size + 1));
    err = rc == 0 ? 0 : errno;
  }
  free(path);
  (void)size;
  (void)w;
  Term result = err == 0 ? io_done(e, term_pak(CID(Unit), 0))
    : io_fail(e, err, NULL);
  return io_tup(e, io_hand(fd), result);
}

static void __attribute__((constructor)) unix_socket_connect_use(void) {
  io_eff(CID(unix_socket_connect), unix_socket_connect_run);
}
