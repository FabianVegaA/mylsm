import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/Console.bend as Console

# Reports successful lock release by the process after owner shutdown.
def closed(result: Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_LOCK_REACQUIRED")
    case Fail{_}: IO.die(Unit, 1, "database close failed after owner reacquisition")

# Reopens the database after owner exit to verify process-lock reacquisition.
def opened(result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "database lock was not released by owner shutdown")
    case Done{handle}:
      do IO<Unit>:
        result : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        closed(result)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <-
      ByteDb.open_existing(path)
    opened(result)
