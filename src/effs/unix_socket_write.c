#include <errno.h>
#include <stdlib.h>
#include <sys/socket.h>

Term unix_socket_write_run(Env e, Term* fields, IoWork* work) {
  int file = (int)io_hand_v(fields[0]);
  (void)work;
  u64 offset = (u64)fields[1];
  u64 length = (u64)fields[2];
  Term words = fields[3];
  u64 size = length;
  if (term_tag(words) != TAG_BUF ||
      offset > (4ull << blk_cls(words)) ||
      size > (4ull << blk_cls(words)) - offset) {
    term_drop(e, words);
    return io_tup(e, io_hand(file), io_fail(e, EINVAL, NULL));
  }
  char* data = malloc(size ? size : 1);
  if (data == NULL) {
    term_drop(e, words);
    return io_tup(e, io_hand(file), io_fail(e, ENOMEM, NULL));
  }
  u64 location = blk_loc(e.mem, words);
  for (u64 index = 0; index < size; index++) {
    data[index] = (char)(blk_read(e.mem, false, location,
      (u32)((offset + index) / 4)) >> (8 * ((offset + index) % 4)));
  }
  ssize_t sent = send(file, data, size,
#ifdef MSG_NOSIGNAL
    MSG_NOSIGNAL
#else
    0
#endif
  );
  int error = sent < 0 ? errno : 0;
  free(data);
  if (error != 0) {
    term_drop(e, words);
    return io_tup(e, io_hand(file), io_fail(e, error, NULL));
  }
  return io_tup(e, io_hand(file),
    io_done(e, io_tup(e, (Term)sent, words)));
}

static void __attribute__((constructor)) unix_socket_write_use(void) {
  io_eff(CID(unix_socket_write), unix_socket_write_run);
}
