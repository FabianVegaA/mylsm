// Console.read_line — bounded synchronous line input without the trailing '\n'.
// EOF returns an empty string. Lines longer than 1 MiB fail with EFBIG.

#define READ_LINE_MAX (1024u * 1024u)

Term read_line_run(Env e, Term* f, IoWork* w) {
  size_t cap = 256;
  size_t len = 0;
  char* data = malloc(cap);
  (void)f;
  (void)w;
  if (!data) { return io_fail(e, ENOMEM, NULL); }

  for (;;) {
    unsigned char byte = 0;
    ssize_t got;
    do {
      got = read(STDIN_FILENO, &byte, 1);
    } while (got < 0 && errno == EINTR);
    if (got < 0) {
      int err = errno != 0 ? errno : EIO;
      free(data);
      return io_fail(e, err, NULL);
    }
    if (got == 0) { break; }
    int ch = (int)byte;
    if (ch == '\n') { break; }
    if (len == READ_LINE_MAX) {
      free(data);
      return io_fail(e, EFBIG, NULL);
    }
    if (len == cap) {
      size_t next = cap * 2;
      if (next > READ_LINE_MAX) { next = READ_LINE_MAX; }
      char* grown = realloc(data, next);
      if (!grown) {
        free(data);
        return io_fail(e, ENOMEM, NULL);
      }
      data = grown;
      cap = next;
    }
    data[len++] = (char)ch;
  }

  Term result = io_done(e, io_str(e, data, len));
  free(data);
  return result;
}

static void __attribute__((constructor)) read_line_use(void) {
  io_eff(CID(read_line), read_line_run, 0);
}
