#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;

static void attached_free(char** values, size_t count) {
  if (values == NULL) { return; }
  for (size_t index = 0; index < count; index += 1) { free(values[index]); }
  free(values);
}

static int attached_arguments(Env e, Term list, char* program, char*** result, size_t* count) {
  size_t capacity = 8;
  char** values = calloc(capacity, sizeof(char*));
  if (values == NULL) { return ENOMEM; }
  values[0] = program;
  *count = 1;
  while (term_aux(list) == CID(Con)) {
    Term fields[2];
    spare_free(e, cls_fit(2), ctr_take(e, list, 2, fields));
    u64 length = 0;
    char* value = io_cstr(e, fields[0], &length);
    if (io_nul(value, length)) {
      free(value);
      attached_free(values, *count);
      return EINVAL;
    }
    if (*count + 1 >= capacity) {
      capacity *= 2;
      char** grown = realloc(values, capacity * sizeof(char*));
      if (grown == NULL) {
        free(value);
        attached_free(values, *count);
        return ENOMEM;
      }
      values = grown;
    }
    values[(*count)++] = value;
    list = fields[1];
  }
  values[*count] = NULL;
  *result = values;
  return 0;
}

static int attached_overrides(Env e, Term list, char*** result, size_t* count) {
  size_t capacity = 8;
  char** values = calloc(capacity, sizeof(char*));
  if (values == NULL) { return ENOMEM; }
  *count = 0;
  while (term_aux(list) == CID(Con)) {
    Term fields[2];
    Term pair[2];
    spare_free(e, cls_fit(2), ctr_take(e, list, 2, fields));
    spare_free(e, cls_fit(2), ctr_take(e, fields[0], 2, pair));
    u64 key_length = 0;
    u64 value_length = 0;
    char* key = io_cstr(e, pair[0], &key_length);
    char* value = io_cstr(e, pair[1], &value_length);
    if (key_length == 0 || io_nul(key, key_length) || memchr(key, '=', key_length) != NULL || io_nul(value, value_length)) {
      free(key);
      free(value);
      attached_free(values, *count);
      return EINVAL;
    }
    char* entry = malloc(key_length + value_length + 2);
    if (entry == NULL) {
      free(key);
      free(value);
      attached_free(values, *count);
      return ENOMEM;
    }
    memcpy(entry, key, key_length);
    entry[key_length] = '=';
    memcpy(entry + key_length + 1, value, value_length + 1);
    free(key);
    free(value);
    if (*count + 1 >= capacity) {
      capacity *= 2;
      char** grown = realloc(values, capacity * sizeof(char*));
      if (grown == NULL) {
        free(entry);
        attached_free(values, *count);
        return ENOMEM;
      }
      values = grown;
    }
    values[(*count)++] = entry;
    list = fields[1];
  }
  values[*count] = NULL;
  *result = values;
  return 0;
}

static bool attached_overridden(char* inherited, char** overrides, size_t count) {
  char* separator = strchr(inherited, '=');
  if (separator == NULL) { return false; }
  size_t length = (size_t)(separator - inherited);
  for (size_t index = 0; index < count; index += 1) {
    char* override_separator = strchr(overrides[index], '=');
    size_t override_length = (size_t)(override_separator - overrides[index]);
    if (override_length == length && memcmp(inherited, overrides[index], length) == 0) { return true; }
  }
  return false;
}

static char** attached_environment(char** overrides, size_t override_count) {
  size_t inherited_count = 0;
  while (environ[inherited_count] != NULL) { inherited_count += 1; }
  char** values = calloc(inherited_count + override_count + 1, sizeof(char*));
  if (values == NULL) { return NULL; }
  size_t count = 0;
  for (size_t index = 0; index < inherited_count; index += 1) {
    if (!attached_overridden(environ[index], overrides, override_count)) { values[count++] = environ[index]; }
  }
  for (size_t index = 0; index < override_count; index += 1) { values[count++] = overrides[index]; }
  return values;
}

Term run_run(Env e, Term* fields, IoWork* work) {
  (void)work;
  u64 program_length = 0;
  char* program = io_cstr(e, fields[0], &program_length);
  bool invalid_program = program_length == 0 || io_nul(program, program_length);
  int error = invalid_program ? EINVAL : 0;
  char** argv = NULL;
  char** overrides = NULL;
  char** child_env = NULL;
  size_t argc = 0;
  size_t override_count = 0;
  if (error == 0) { error = attached_arguments(e, fields[1], program, &argv, &argc); }
  if (invalid_program) { free(program); }
  if (error == 0) { error = attached_overrides(e, fields[2], &overrides, &override_count); }
  if (error == 0) {
    child_env = attached_environment(overrides, override_count);
    if (child_env == NULL) { error = ENOMEM; }
  }
  char* log_path = NULL;
  if (term_aux(fields[3]) == CID(Some)) {
    Term part[1];
    spare_free(e, cls_fit(1), ctr_take(e, fields[3], 1, part));
    u64 length = 0;
    log_path = io_cstr(e, part[0], &length);
    if (io_nul(log_path, length)) { error = EINVAL; }
  }
  int log_fd = -1;
  posix_spawn_file_actions_t actions;
  bool actions_ready = false;
  if (error == 0 && log_path != NULL) {
    log_fd = open(log_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (log_fd < 0) { error = errno; }
  }
  if (error == 0 && log_fd >= 0) {
    error = posix_spawn_file_actions_init(&actions);
    actions_ready = error == 0;
    if (error == 0) { error = posix_spawn_file_actions_adddup2(&actions, log_fd, STDOUT_FILENO); }
    if (error == 0) { error = posix_spawn_file_actions_adddup2(&actions, log_fd, STDERR_FILENO); }
    if (error == 0) { error = posix_spawn_file_actions_addclose(&actions, log_fd); }
  }
  pid_t child = -1;
  if (error == 0) { error = posix_spawnp(&child, program, actions_ready ? &actions : NULL, NULL, argv, child_env); }
  if (actions_ready) { posix_spawn_file_actions_destroy(&actions); }
  if (log_fd >= 0) { close(log_fd); }
  free(log_path);
  free(child_env);
  attached_free(overrides, override_count);
  attached_free(argv, argc);
  if (error != 0) { return io_fail(e, error, NULL); }
  int status = 0;
  while (waitpid(child, &status, 0) < 0) {
    if (errno != EINTR) { return io_fail(e, errno, NULL); }
  }
  return io_done(e, (Term)(u32)(WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status)));
}

static void __attribute__((constructor)) attached_run_use(void) {
  io_eff(CID(run), run_run);
}
