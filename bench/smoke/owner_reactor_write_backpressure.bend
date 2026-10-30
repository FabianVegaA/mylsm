import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def setup.finished(result: Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_REACTOR_DATABASE_READY")
    case Fail{_}: IO.die(Unit, 1, "reactor fixture close failed")

def setup.key(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def setup.closed(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        setup.finished(closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "reactor fixture value write failed")

def setup.created(
  result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        written : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.put(handle, setup.key(Bytes.from_hex("626967")),
            Bytes.new(8388608))
        setup.closed(written)
    case Fail{_}:
      IO.die(Unit, 1, "reactor fixture database creation failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <- ByteDb.create(path)
    setup.created(result)
