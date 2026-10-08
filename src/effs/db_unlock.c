#include <errno.h>
#include <sys/file.h>

Term db_unlock_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand_v(f[0]);
  (void)w;
  int rc = flock(fd, LOCK_UN);
  Term result = rc == 0 ? io_done(e, term_pak(CID(Unit), 0)) : io_fail(e, errno, NULL);
  return io_tup(e, io_hand(fd), result);
}

__attribute__((constructor)) static void db_unlock_use(void) {
  io_eff(CID(DbLock.try_unlock), db_unlock_run);
}
