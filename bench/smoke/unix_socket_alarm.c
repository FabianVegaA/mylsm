#include <errno.h>
#include <signal.h>
#include <unistd.h>

static void unix_socket_alarm_ignore(int signal_number) {
  (void)signal_number;
}

Term unix_socket_alarm_run(Env e, Term* f, IoWork* w) {
  struct sigaction action = {0};
  action.sa_handler = unix_socket_alarm_ignore;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGALRM, &action, NULL) < 0) {
    int error = errno;
    (void)f;
    (void)w;
    return io_fail(e, error, NULL);
  }
  alarm(1);
  (void)f;
  (void)w;
  return io_done(e, term_pak(CID_Unit, 0));
}

static void __attribute__((constructor)) unix_socket_alarm_use(void) {
  io_eff(CID(unix_socket_alarm), unix_socket_alarm_run);
}
