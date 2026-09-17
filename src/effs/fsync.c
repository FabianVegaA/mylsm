// Fs.fsync — open(O_RDWR) + fsync + close as one durable-sync operation.
// Mirrors Base's file_write.c shape: async worker, io_done/io_fail pack.

static void fsync_call(IoWork* w) {
  int fd = open(w->data, O_RDWR);
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
