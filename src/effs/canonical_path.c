#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

Term canonical_path_run(Env e, Term* f, IoWork* w) {
  uint64_t size = 0;
  char* input = io_cstr(e, f[0], &size);
  char* output = realpath(input, NULL);
  int err = errno;
  free(input);
  (void)w;
  if (output == NULL) { return io_fail(e, err, NULL); }
  Term result = io_done(e, io_str(e, output, strlen(output)));
  free(output);
  return result;
}

static void canonical_path_use(void) __attribute__((constructor));
static void canonical_path_use(void) {
  io_eff(CID(canonical_path), canonical_path_run);
}
