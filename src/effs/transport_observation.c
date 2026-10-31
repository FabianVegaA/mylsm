Term emit_run(Env e, Term* f, IoWork* w) {
  uint64_t length = 0;
  char* line = io_cstr(e, f[0], &length);
  (void)w;
  ssize_t written = write(STDERR_FILENO, line, length);
  int error = errno;
  free(line);
  if (written < 0 || (uint64_t)written != length) {
    return io_fail(e, written < 0 ? error : EIO, NULL);
  }
  return io_done(e, term_pak(CID(Unit), 0));
}

static void __attribute__((constructor)) emit_use(void) {
  io_eff(CID(emit), emit_run);
}
