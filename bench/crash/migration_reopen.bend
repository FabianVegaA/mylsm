import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/Console.bend as Console

# Stops verification if a published migration cannot be reopened.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Closes a reopened migration and emits the verification marker.
def closed(result: Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: fail("published migration close failed")
    case Done{Unit{}}: IO.print("MIGRATION_REOPEN_PASSED")

# Closes the database after successful reopen.
def opened(result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: fail("published migration could not be reopened")
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
