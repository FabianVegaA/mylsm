import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/Console.bend as Console

# Handles closed.
def closed(result: Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_FRAME_DATABASE_READY")
    case Fail{_}: IO.die(Unit, 1, "owner frame fixture could not close database")

# Handles created.
def created(result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        result : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        closed(result)
    case Fail{_}: IO.die(Unit, 1, "owner frame fixture could not create database")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <- ByteDb.create(path)
    created(result)
