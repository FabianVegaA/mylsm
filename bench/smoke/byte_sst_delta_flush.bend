import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes

def bytes.parsed(result: Maybe<&1, PackedBytes.Bytes>) -> PackedBytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: PackedBytes.new(0)

# Decodes a fixed hexadecimal vector for the SST-delta fixture.
def bytes(hex: String) -> PackedBytes.Bytes:
  bytes.parsed(PackedBytes.from_hex(hex))

def byte.equal(pair: PackedBytes.Bytes & PackedBytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, same): same

def check.old.value(value: Maybe<&1, PackedBytes.Bytes>) -> Bool:
  match value:
    case Some{found}: byte.equal(PackedBytes.eq(found, bytes("80ff00")))
    case None{}: False{}

def require.old.value(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "flush must retain SST records beneath the WAL delta")

# Checks an old SST value after a new delta mutation has been flushed.
def finish(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match result:
    case Done{value}:
      do IO<Unit>:
        _valid : Unit <- require.old.value(check.old.value(value))
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.print("BYTE_SST_DELTA_FLUSH_PASSED")
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "read after delta flush failed")

def after.read(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, result): finish(handle, result)

def after.flush(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        read : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, bytes("610062"))
        _checked : Unit <- after.read(read)
        return Unit{}
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "delta flush failed")

def after.put(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        _done : Unit <- after.flush(flushed)
        return Unit{}
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "delta write failed")

# Reopens the SST-only fixture and starts the delta write/flush sequence.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, bytes("6672657368"), bytes("6e6577"))
        _done : Unit <- after.put(written)
        return Unit{}
    case Fail{_}: IO.die(Unit, 1, "SST-only reopen failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing(path)
    opened(result)
