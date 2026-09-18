// Console.get_env — copy an environment value into a Bend string.
// Missing variables return an empty string; the getenv pointer never escapes.

Term get_env_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* name = io_cstr(e, f[0], &n);
  const char* value = getenv(name);
  Term result = io_done(e, io_str(e, value != NULL ? value : "", value != NULL ? strlen(value) : 0));
  free(name);
  (void)w;
  return result;
}

static void __attribute__((constructor)) get_env_use(void) {
  io_eff(CID_GET_ENV, get_env_run, 0);
}
