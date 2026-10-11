#include <errno.h>
#include <stdlib.h>
#include <sys/socket.h>

static Term unix_socket_words(Env e, const unsigned char* bytes, u64 length) {
  u64 count = (length + 3) / 4;
  u64 depth = 0;
  Term zero = 0;
  while ((1ull << depth) < count) {
    depth++;
  }
  Term array = blk_new(e, false, depth, 0, 1, &zero);
  u64 location = blk_loc(e.mem, array);
  for (u64 index = 0; index < count; index++) {
    u32 word = 0;
    for (u64 offset = 0; offset < 4 && index * 4 + offset < length; offset++) {
      word |= (u32)bytes[index * 4 + offset] << (8 * offset);
    }
    blk_write(e.mem, false, location, (u32)index, word);
  }
  return io_tup(e, (Term)length, array);
}

static void unix_socket_read_call(IoWork* work) {
  ssize_t count = recv((int)work->hand, work->data, work->size, 0);
  if (count < 0) {
    work->code = errno;
    return;
  }
  work->made = count;
  work->code = 0;
}

static Term unix_socket_read_pack(Env e, IoWork* work) {
  Term value = work->code ? 0 : unix_socket_words(e,
    (unsigned char*)work->data, (u64)work->made);
  free(work->data);
  Term result = work->code
    ? io_fail(e, work->code, NULL)
    : io_done(e, value);
  return io_tup(e, io_hand(work->hand), result);
}

Term unix_socket_read_run(Env e, Term* fields, IoWork* work) {
  work->hand = (intptr_t)io_hand_v(fields[0]);
  work->size = (u64)fields[1];
  work->data = io_mem(malloc(work->size ? work->size : 1));
  if (work->data == NULL) {
    return io_tup(e, io_hand(work->hand), io_fail(e, ENOMEM, NULL));
  }
  return io_work(work, unix_socket_read_call, unix_socket_read_pack);
}

static void __attribute__((constructor)) unix_socket_read_use(void) {
  io_eff(CID(unix_socket_read), unix_socket_read_run);
}
