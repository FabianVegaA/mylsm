// Fs.read_dir_count / Fs.read_dir_at — indexed directory listing.
// Both skip "."/".." and names containing '\n' with the IDENTICAL rule, so
// count is a valid fuel bound for a 0..count-1 fetch sweep. Past-end fetch
// answers "" (readdir never yields empty names); the Bend side matches
// SNil{} structurally — no Maybe packing in C, no mutual recursion.

#include <dirent.h>

static int valid_name(char* nm) {
  return strcmp(nm, ".") != 0 && strcmp(nm, "..") != 0
    && strchr(nm, '\n') == NULL;
}

Term read_dir_count_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* path = io_cstr(e, f[0], &n);
  DIR* d = opendir(path);
  int err = errno;
  free(path);
  (void)w;
  if (!d) { return io_fail(e, err, NULL); }
  uint64_t c = 0;
  struct dirent* ent;
  while ((ent = readdir(d)) != NULL) {
    if (valid_name(ent->d_name)) { c += 1; }
  }
  closedir(d);
  return io_done(e, c);
}

static void __attribute__((constructor)) read_dir_count_use(void) {
  io_eff(CID(read_dir_count), read_dir_count_run, 0);
}

Term read_dir_at_run(Env e, Term* f, IoWork* w) {
  uint64_t n = 0;
  char* path = io_cstr(e, f[0], &n);
  uint64_t want = (uint64_t)f[1];
  DIR* d = opendir(path);
  int err = errno;
  free(path);
  (void)w;
  if (!d) { return io_fail(e, err, NULL); }
  uint64_t c = 0;
  struct dirent* ent;
  Term r = io_done(e, io_str(e, "", 0));
  while ((ent = readdir(d)) != NULL) {
    if (!valid_name(ent->d_name)) { continue; }
    if (c == want) {
      r = io_done(e, io_str(e, ent->d_name, strlen(ent->d_name)));
      break;
    }
    c += 1;
  }
  closedir(d);
  return r;
}

static void __attribute__((constructor)) read_dir_at_use(void) {
  io_eff(CID(read_dir_at), read_dir_at_run, 0);
}
