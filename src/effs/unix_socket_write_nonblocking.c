#include <errno.h>
#include <stdlib.h>
#include <sys/socket.h>

Term unix_socket_write_nonblocking_run(Env e, Term* fields, IoWork* work) {
  int file = (int)io_hand_v(fields[0]);
  uint64_t offset = (uint64_t)fields[1];
  uint64_t length = (uint64_t)fields[2];
  Term words = fields[3];
  if (term_tag(words) != TAG_BUF ||
      offset > (4ull << blk_cls(words)) ||
      length > (4ull << blk_cls(words)) - offset) {
    (void)work;
    return io_tup(e, io_hand(file),
      io_tup(e, words, io_fail(e, EINVAL, NULL)));
  }
  char* data = malloc(length ? length : 1);
  if (data == NULL) {
    (void)work;
    return io_tup(e, io_hand(file),
      io_tup(e, words, io_fail(e, ENOMEM, NULL)));
  }
  u64 location = blk_loc(e.mem, words);
  for (u64 index = 0; index < length; index++) {
    data[index] = (char)(blk_read(e.mem, false, location,
      (u32)((offset + index) / 4)) >> (8 * ((offset + index) % 4)));
  }
  ssize_t sent = send(file, data, length,
#ifdef MSG_NOSIGNAL
    MSG_NOSIGNAL
#else
    0
#endif
  );
  int error = sent < 0 ? errno : 0;
  free(data);
  (void)work;
  return error != 0
    ? io_tup(e, io_hand(file), io_tup(e, words, io_fail(e, error, NULL)))
    : io_tup(e, io_hand(file), io_tup(e, words, io_done(e, (Term)sent)));
}

static void unix_socket_write_nonblocking_use(void) {
  io_eff(CID(unix_socket_write_nonblocking),
    unix_socket_write_nonblocking_run);
}

__attribute__((constructor)) static void unix_socket_write_nonblocking_init(void) {
  unix_socket_write_nonblocking_use();
}
