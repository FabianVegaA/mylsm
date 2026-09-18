// Fs.fsync — open(O_RDONLY) + fsync + close as one durable-sync operation.
// O_RDONLY (not O_RDWR) so directory fsync works too: rename durability
// needs fsyncing the containing directory on both Linux and macOS.
// Mirrors Base's file_write.c shape: async worker, io_done/io_fail pack.

static void fsync_call(IoWork* w) {
  int fd = open(w->data, O_RDONLY);
  int rc = fd < 0 ? -1 : fsync(fd);
  if (fd >= 0) { close(fd); }
  io_sys_end(w, rc);
}

static Term fsync_pack(Env e, IoWork* w) {
  Term r = w->code != 0 ? io_fail(e, w->code, NULL)
    : io_done(e, term_pak(CID_UNIT, 0));
  free(w->data);
  return r;
}

Term fsync_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  return io_work(w, fsync_call, fsync_pack);
}

static void __attribute__((constructor)) fsync_use(void) {
  io_eff(CID_FSYNC, fsync_run, 0);
}
