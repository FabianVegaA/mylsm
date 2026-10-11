import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Creates and closes the database used by lock-wait process tests.
def create_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "lock-wait fixture database creation failed")
    case Done{handle}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.print("DATABASE_READY")

# Holds the process lock long enough for timeout and waiting clients.
def hold_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "lock-wait fixture owner failed to open")
    case Done{handle}:
      do IO<Unit>:
        IO.print("OWNER_LOCKED")
        IO.sleep(800)
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.print("OWNER_RELEASED")

# Checks that the returned public error is the timeout category.
def timeout_result.kind(is_timeout: Bool) -> IO(Unit):
  match is_timeout:
    case True{}:
      IO.print("OPEN_TIMED_OUT")
    case False{}:
      IO.die(Unit, 1, "open wait returned a non-timeout error")

# Checks a public open timeout and closes any unexpected successful handle.
def timeout_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{error}:
      timeout_result.kind(MyLSM.error_is_timeout(error))
    case Done{handle}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "open wait acquired a lock after its deadline")

# Checks that a public timed open succeeds after the owner releases.
def wait_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "open wait failed after the owner released")
    case Done{handle}:
      do IO<Unit>:
        IO.print("OPEN_ACQUIRED")
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.print("OPEN_RELEASED")

# Selects timeout or successful timed open.
def wait_mode(is_timeout: Bool, path: String) -> IO(Unit):
  match is_timeout:
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <-
          MyLSM.open_existing_wait(path, 100, 10)
        timeout_result(result)
    case False{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <-
          MyLSM.open_existing_wait(path, 2000, 10)
        wait_result(result)

# Selects the database owner or timed-open client role.
def hold_mode(is_hold: Bool, mode: String, path: String) -> IO(Unit):
  match is_hold:
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        hold_result(result)
    case False{}:
      wait_mode(String.eq(mode, "timeout"), path)

# Selects database setup or the lock-wait process roles.
def setup_mode(is_create: Bool, +mode: String, path: String) -> IO(Unit):
  match is_create:
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.create(path)
        create_result(result)
    case False{}:
      hold_mode(String.eq(mode, "hold"), mode, path)

# Dispatches one process role for the lock-wait integration fixture.
def run(+mode: String, path: String) -> IO(Unit):
  setup_mode(String.eq(mode, "create"), mode, path)

def main() -> IO(Unit):
  do IO<Unit>:
    mode : String <- IO.try(String, Console.get_env("MYLSM_WAIT_MODE"))
    path : String <- IO.try(String, Console.get_env("MYLSM_WAIT_PATH"))
    run(mode, path)
