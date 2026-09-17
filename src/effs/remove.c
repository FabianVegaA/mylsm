// Fs.remove — unlink a file (WAL segment / compacted input cleanup).
// Fast metadata syscall: synchronous, like Base's file_close.c.

Term remove_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* path = io_cstr(e, f[0], &n);
  int rc = unlink(path);
  int err = errno;
  free(path);
  (void)w;
  return rc == 0 ? io_done(e, term_pak(CID_UNIT, 0)) : io_fail(e, err, NULL);
}

static void __attribute__((constructor)) remove_use(void) {
  io_eff(CID_REMOVE, remove_run, 0);
}
