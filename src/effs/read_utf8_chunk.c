// Fs.read_utf8_chunk — positional reads ending on a complete UTF-8 boundary.

#include <errno.h>
#include <stdio.h>

static size_t utf8_safe_prefix(const unsigned char* data, size_t n) {
  if (n == 0) { return 0; }
  size_t lead = n - 1;
  while (lead > 0 && (data[lead] & 0xC0) == 0x80) { lead -= 1; }
  unsigned char c = data[lead];
  size_t need = c < 0x80 ? 1 : (c & 0xE0) == 0xC0 ? 2 : (c & 0xF0) == 0xE0 ? 3 : (c & 0xF8) == 0xF0 ? 4 : 1;
  return n - lead < need ? lead : n;
}

Term read_utf8_chunk_run(Env e, Term* f, IoWork* w) {
  uint64_t path_len = 0;
  char* path = io_cstr(e, f[0], &path_len);
  uint64_t offset = (uint64_t)f[1];
  uint64_t requested = (uint64_t)f[2];
  (void)w;
  if (requested == 0 || requested > 0xFFFFFFFFULL) {
    free(path);
    return io_fail(e, EINVAL, NULL);
  }
  FILE* file = fopen(path, "rb");
  int err = errno;
  free(path);
  if (!file) { return io_fail(e, err, NULL); }
  if (fseeko(file, (off_t)offset, SEEK_SET) != 0) {
    err = errno;
    fclose(file);
    return io_fail(e, err, NULL);
  }
  unsigned char* data = malloc((size_t)requested);
  if (!data) {
    fclose(file);
    return io_fail(e, ENOMEM, NULL);
  }
  size_t got = fread(data, 1, (size_t)requested, file);
  if (ferror(file)) {
    err = errno ? errno : EIO;
    free(data);
    fclose(file);
    return io_fail(e, err, NULL);
  }
  int at_eof = feof(file);
  fclose(file);
  size_t safe = at_eof ? got : utf8_safe_prefix(data, got);
  char header[32];
  int header_len = snprintf(header, sizeof(header), "%zu;", safe);
  size_t total = (size_t)header_len + safe;
  char* out = malloc(total ? total : 1);
  if (!out) {
    free(data);
    return io_fail(e, ENOMEM, NULL);
  }
  memcpy(out, header, (size_t)header_len);
  if (safe > 0) { memcpy(out + header_len, data, safe); }
  Term result = io_done(e, io_str(e, out, total));
  free(out);
  free(data);
  return result;
}

static void __attribute__((constructor)) read_utf8_chunk_use(void) {
  io_eff(CID_READ_UTF8_CHUNK, read_utf8_chunk_run, 0);
}
