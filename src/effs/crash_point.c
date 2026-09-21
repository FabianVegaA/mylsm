// CrashPoint.stop — irreducible host boundary. Bend decides whether the named
// checkpoint is active; this effect only emits its witness and stops the process.

Term stop_run(Env e, Term* f, IoWork* w) {
  uint64_t length = 0;
  char* name = io_cstr(e, f[0], &length);
  (void)w;

#if defined(__APPLE__) || defined(__linux__)
  const char marker[] = "crash_point_reached=";
  int marker_ok = write(STDERR_FILENO, marker, sizeof(marker) - 1) == sizeof(marker) - 1
    && write(STDERR_FILENO, name, length) == length
    && write(STDERR_FILENO, "\n", 1) == 1;
  free(name);
  if (!marker_ok) {
    return io_fail(e, errno != 0 ? errno : EIO, NULL);
  }
  if (kill(getpid(), SIGSTOP) != 0) {
    return io_fail(e, errno, NULL);
  }
  return io_done(e, term_pak(CID_UNIT, 0));
#else
  free(name);
  return io_fail(e, ENOTSUP, NULL);
#endif
}

static void __attribute__((constructor)) stop_use(void) {
  io_eff(CID_STOP, stop_run, 0);
}
