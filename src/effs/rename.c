// Fs.rename — atomic file rename (Manifest publish primitive).
// Fast metadata syscall: synchronous, like Base's file_close.c.

Term rename_run(Env e, Term* f, IoWork* w) {
  uint64_t n0 = 0, n1 = 0;
  char* oldp = io_cstr(e, f[0], &n0);
  char* newp = io_cstr(e, f[1], &n1);
  int rc = rename(oldp, newp);
  int err = errno;
  free(oldp);
  free(newp);
  (void)w;
  return rc == 0 ? io_done(e, term_pak(CID_UNIT, 0)) : io_fail(e, err, NULL);
}

static void __attribute__((constructor)) rename_use(void) {
  io_eff(CID_RENAME, rename_run, 0);
}
