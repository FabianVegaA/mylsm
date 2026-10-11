#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

static Term files_compat_words(Env e, const unsigned char* bytes, u64 length) {
  u64 count = (length + 3) / 4;
  u64 depth = 0;
  Term zero = 0;
  while ((1ull << depth) < count) { depth++; }
  Term array = blk_new(e, false, depth, 0, 1, &zero);
  u64 location = blk_loc(e.mem, array);
  for (u64 index = 0; index < count; index++) {
    u32 word = 0;
    for (u64 byte = 0; byte < 4 && index * 4 + byte < length; byte++) {
      word |= (u32)bytes[index * 4 + byte] << (8 * byte);
    }
    blk_write(e.mem, false, location, (u32)index, word);
  }
  return io_tup(e, (Term)length, array);
}

static void files_compat_read_call(IoWork* work);
static Term files_compat_read_pack(Env e, IoWork* work);
static void files_compat_write_call(IoWork* work);
static Term files_compat_write_pack(Env e, IoWork* work);

Term files_compat_read_words_run(Env e, Term* fields, IoWork* work) {
  work->hand = (intptr_t)io_hand_v(fields[0]);
  work->size = (u64)fields[1] < 1048576 ? (u64)fields[1] : 1048576;
  work->data = io_mem(malloc(work->size ? work->size : 1));
  if (work->data == NULL) {
    return io_tup(e, io_hand(work->hand), io_fail(e, ENOMEM, NULL));
  }
  return io_work(work, files_compat_read_call, files_compat_read_pack);
}

static void files_compat_read_call(IoWork* work) {
  ssize_t count = read((int)work->hand, work->data, work->size);
  if (count < 0) {
    work->code = errno;
    return;
  }
  work->made = count;
  work->code = 0;
}

static Term files_compat_read_pack(Env e, IoWork* work) {
  Term result = work->code
    ? io_fail(e, work->code, NULL)
    : io_done(e, files_compat_words(e, (unsigned char*)work->data,
        (u64)work->made));
  free(work->data);
  return io_tup(e, io_hand(work->hand), result);
}

Term files_compat_write_words_run(Env e, Term* fields, IoWork* work) {
  (void)work;
  int file = (int)io_hand_v(fields[0]);
  u64 offset = (u64)fields[1];
  u64 length = (u64)fields[2];
  Term array = fields[3];
  bool invalid = term_tag(array) != TAG_BUF ||
    offset > (4ull << blk_cls(array)) ||
    length > (4ull << blk_cls(array)) - offset;
  if (invalid) {
    term_drop(e, array);
    return io_tup(e, io_hand(file), io_fail(e, EINVAL, NULL));
  }
  char* data = malloc(length ? length : 1);
  if (data == NULL) {
    term_drop(e, array);
    return io_tup(e, io_hand(file), io_fail(e, ENOMEM, NULL));
  }
  u64 location = blk_loc(e.mem, array);
  for (u64 index = 0; index < length; index++) {
    data[index] = (char)(blk_read(e.mem, false, location,
      (u32)((offset + index) / 4)) >> (8 * ((offset + index) % 4)));
  }
  ssize_t written = write(file, data, length);
  int error = written < 0 ? errno : 0;
  free(data);
  Term result;
  if (error != 0) {
    term_drop(e, array);
    result = io_fail(e, error, NULL);
  } else {
    result = io_done(e, io_tup(e, (Term)written, array));
  }
  return io_tup(e, io_hand(file), result);
}

Term files_compat_stat_run(Env e, Term* fields, IoWork* work) {
  u64 length = 0;
  char* path = io_cstr(e, fields[0], &length);
  struct stat info;
  int result = stat(path, &info);
  int error = errno;
  free(path);
  if (result != 0) { return io_fail(e, error, NULL); }
  u32 kind = S_ISREG(info.st_mode) ? 0 : S_ISDIR(info.st_mode) ? 1 : 2;
  return io_done(e, io_tup(e, kind, io_tup(e,
    (Term)(u32)info.st_size, (Term)(u32)info.st_mtime)));
}

Term files_compat_remove_run(Env e, Term* fields, IoWork* work) {
  u64 length = 0;
  char* path = io_cstr(e, fields[0], &length);
  int result = remove(path);
  int error = errno;
  free(path);
  return result == 0 ? io_done(e, term_pak(CID(Unit), 0))
    : io_fail(e, error, NULL);
}

Term files_compat_rename_run(Env e, Term* fields, IoWork* work) {
  u64 from_length = 0;
  u64 to_length = 0;
  char* from = io_cstr(e, fields[0], &from_length);
  char* to = io_cstr(e, fields[1], &to_length);
  int result = rename(from, to);
  int error = errno;
  free(from);
  free(to);
  return result == 0 ? io_done(e, term_pak(CID(Unit), 0))
    : io_fail(e, error, NULL);
}

static void files_compat_use(void) __attribute__((constructor));
static void files_compat_use(void) {
#ifdef CID(read.words)
  io_eff(CID(read.words), files_compat_read_words_run);
#endif
#ifdef CID(write.words.once)
  io_eff(CID(write.words.once), files_compat_write_words_run);
#endif
#ifdef CID(stat.raw)
  io_eff(CID(stat.raw), files_compat_stat_run);
#endif
#ifdef CID(remove)
  io_eff(CID(remove), files_compat_remove_run);
#endif
#ifdef CID(rename)
  io_eff(CID(rename), files_compat_rename_run);
#endif
}
