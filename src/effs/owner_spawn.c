#include <errno.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/types.h>

extern char** environ;

static void owner_spawn_arguments_free(char** argv, u32 count) {
  for (u32 index = 0; index < count; index += 1) {
    free(argv[index]);
  }
  free(argv);
}

Term owner_spawn_run(Env e, Term* fields, IoWork* work) {
  (void)work;
  u32 capacity = 8;
  u32 count = 0;
  int error = 0;
  char** argv = io_mem(calloc(capacity, sizeof(char*)));
  Term arguments = fields[0];
  while (term_aux(arguments) == CID_CON && error == 0) {
    Term pair[2];
    spare_free(e, cls_fit(2), ctr_take(e, arguments, 2, pair));
    u64 length = 0;
    char* value = io_cstr(e, pair[0], &length);
    if (io_nul(value, length)) {
      free(value);
      error = EINVAL;
    } else {
      if (count + 1 >= capacity) {
        capacity *= 2;
        argv = io_mem(realloc(argv, capacity * sizeof(char*)));
      }
      argv[count++] = value;
    }
    arguments = pair[1];
  }
  if (count == 0 && error == 0) {
    error = EINVAL;
  }
  argv[count] = NULL;
  pid_t child = -1;
  posix_spawn_file_actions_t actions;
  posix_spawnattr_t attributes;
  bool actions_ready = false;
  bool attributes_ready = false;
  if (error == 0) {
    error = posix_spawn_file_actions_init(&actions);
    actions_ready = error == 0;
  }
#if defined(__APPLE__)
  if (error == 0) {
    error = posix_spawnattr_init(&attributes);
    attributes_ready = error == 0;
    if (error == 0) {
      error = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT);
    }
  }
#elif defined(__GLIBC__) && defined(__GLIBC_PREREQ) && __GLIBC_PREREQ(2, 34)
  if (error == 0) {
    error = posix_spawn_file_actions_addclosefrom_np(&actions, 3);
  }
#else
  if (error == 0) {
    error = ENOTSUP;
  }
#endif
  if (error == 0) {
#if defined(__APPLE__)
    error = posix_spawn(&child, argv[0], &actions, &attributes, argv, environ);
#else
    error = posix_spawn(&child, argv[0], &actions, NULL, argv, environ);
#endif
  }
  if (attributes_ready) {
    posix_spawnattr_destroy(&attributes);
  }
  if (actions_ready) {
    posix_spawn_file_actions_destroy(&actions);
  }
  owner_spawn_arguments_free(argv, count);
  return error == 0 ? io_done(e, (Term)(u32)child) : io_fail(e, error, NULL);
}

static void __attribute__((constructor)) owner_spawn_use(void) {
  io_eff(CID(owner_spawn), owner_spawn_run);
}
