import Base
import ../../src/DbLock.bend as DbLock
import ../../src/DurableError.bend as DurableError
import ../../src/Console.bend as Console

# Continues the release checked fixture step.
def release_checked(result: Result<&1, &1, DurableError.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "lock release failed")
    case Done{Unit{}}:
      IO.print("LOCK_RELEASED")

# Checks the is busy kind condition in this fixture.
def is_busy_kind(kind: DurableError.ErrorKind) -> Bool:
  match kind:
    case DurableError.Busy{}:
      True{}
    case _:
      False{}

# Checks the check busy kind condition in this fixture.
def check_busy_kind(is_busy: Bool) -> IO(Unit):
  match is_busy:
    case True{}:
      IO.print("LOCK_BUSY")
    case False{}:
      IO.die(Unit, U32.from_nat(1n), "lock returned the wrong error")

# Checks the check busy result condition in this fixture.
def check_busy_result(result: Result<&1, &1, DurableError.Error, DbLock.Lock>) -> IO(Unit):
  match result:
    case Fail{DurableError.Error{kind, _, _, _, _}}:
      check_busy_kind(is_busy_kind(kind))
    case Done{lock}:
      do IO<Unit>:
        _released : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", ".mylsm/build/lock-smoke/db")
        IO.die(Unit, U32.from_nat(1n), "duplicate lock acquisition succeeded")

# Continues the released after fixture step.
def released_after(hold: Bool, lock: DbLock.Lock) -> IO(Unit):
  match hold:
    case True{}:
      do IO<Unit>:
        IO.print("LOCK_ACQUIRED")
        IO.sleep(6000)
        released : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", ".mylsm/build/lock-smoke/db")
        release_checked(released)
    case False{}:
      do IO<Unit>:
        IO.print("LOCK_ACQUIRED")
        released : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", ".mylsm/build/lock-smoke/db")
        release_checked(released)

# Continues the acquired fixture step.
def acquired(hold: Bool, result: Result<&1, &1, DurableError.Error, DbLock.Lock>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "lock acquisition failed")
    case Done{lock}:
      released_after(hold, lock)

# Continues the same process result fixture step.
def same_process_result(lock: DbLock.Lock, result: Result<&1, &1, DurableError.Error, DbLock.Lock>) -> IO(Unit):
  match result:
    case Fail{DurableError.Error{kind, _, _, _, _}}:
      do IO<Unit>:
        _released : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", "")
        check_busy_kind(is_busy_kind(kind))
    case Done{second}:
      do IO<Unit>:
        _released_second : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(second, "close", "")
        _released_first : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", "")
        IO.die(Unit, U32.from_nat(1n), "same-process duplicate lock acquisition succeeded")

# Continues the same process acquired fixture step.
def same_process_acquired(result: Result<&1, &1, DurableError.Error, DbLock.Lock>, path: String) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "same-process initial lock acquisition failed")
    case Done{lock}:
      do IO<Unit>:
        second : Result<&1, &1, DurableError.Error, DbLock.Lock> <- DbLock.acquire(path, "open_existing")
        same_process_result(lock, second)

# Continues the same process open fixture step.
def same_process_open() -> IO(Unit):
  do IO<Unit>:
    first_path : String <- IO.try(String, Console.get_env("MYLSM_LOCK_PATH"))
    result : Result<&1, &1, DurableError.Error, DbLock.Lock> <- DbLock.acquire(first_path, "open_existing")
    second_path : String <- IO.try(String, Console.get_env("MYLSM_LOCK_PATH"))
    same_process_acquired(result, second_path)

# Continues the busy checked fixture step.
def busy_checked(is_busy: Bool, hold: Bool, result: Result<&1, &1, DurableError.Error, DbLock.Lock>) -> IO(Unit):
  match is_busy:
    case False{}:
      acquired(hold, result)
    case True{}:
      check_busy_result(result)

# Runs the dispatch step of this fixture.
def dispatch(same_process: Bool, busy: Bool, hold: Bool, path: String) -> IO(Unit):
  match same_process:
    case True{}:
      same_process_open()
    case False{}:
      do IO<Unit>:
        result : Result<&1, &1, DurableError.Error, DbLock.Lock> <- DbLock.acquire(path, "open_existing")
        busy_checked(busy, hold, result)

def main() -> IO(Unit):
  do IO<Unit>:
    same_process_mode : String <- IO.try(String, Console.get_env("MYLSM_LOCK_MODE"))
    busy_mode : String <- IO.try(String, Console.get_env("MYLSM_LOCK_MODE"))
    hold_mode : String <- IO.try(String, Console.get_env("MYLSM_LOCK_MODE"))
    path : String <- IO.try(String, Console.get_env("MYLSM_LOCK_PATH"))
    dispatch(String.eq(same_process_mode, "same-process"), String.eq(busy_mode, "busy"), String.eq(hold_mode, "hold"), path)
