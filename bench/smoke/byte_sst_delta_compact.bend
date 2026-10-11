import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes

def bytes.parsed(result: Maybe<&1, PackedBytes.Bytes>) -> PackedBytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: PackedBytes.new(0)

# Decodes a fixed hexadecimal vector for the compaction fixture.
def bytes(hex: String) -> PackedBytes.Bytes:
  bytes.parsed(PackedBytes.from_hex(hex))

def byte.equal(pair: PackedBytes.Bytes & PackedBytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, same): same

def check.old.value(value: Maybe<&1, PackedBytes.Bytes>) -> Bool:
  match value:
    case Some{found}: byte.equal(PackedBytes.eq(found, bytes("80ff00")))
    case None{}: False{}

def check.fresh.deleted(value: Maybe<&1, PackedBytes.Bytes>) -> Bool:
  match value:
    case None{}: True{}
    case Some{_}: False{}

def checked.fresh(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{value}):
      match value:
        case None{}:
          do IO<Unit>:
            _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
            IO.print("BYTE_SST_DELTA_COMPACT_PASSED")
        case Some{_}:
          do IO<Unit>:
            _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
            IO.die(Unit, 1, "compaction retained a tombstoned WAL key")
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "read after delta compaction failed")


def checked.valid(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        read : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, bytes("6672657368"))
        _checked : Unit <- checked.fresh(read)
        return Unit{}
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "compaction must retain SST records beneath the WAL delta")

# Verifies that compaction retained an older SST value.
def checked(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match result:
    case Done{value}:
      checked.valid(handle, check.old.value(value))
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "read after delta compaction failed")

def checked.read(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, result): checked(handle, result)

# Reads the old value after the compaction operation completes.
def compacted(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        read : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, bytes("610062"))
        _checked : Unit <- checked.read(read)
        return Unit{}
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "SST-only compaction failed")

def deleted.read(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{value}):
      match value:
        case None{}:
          do IO<Unit>:
            result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
              MyLSM.Bytes.compact(handle)
            _checked : Unit <- compacted(result)
            return Unit{}
        case Some{_}:
          do IO<Unit>:
            _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
            IO.die(Unit, 1, "a WAL tombstone must hide the SST value")
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "read after WAL tombstone failed")

# Checks that a WAL tombstone hides the value retained in the SST.
def deleted(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        read : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, bytes("6672657368"))
        _checked : Unit <- deleted.read(read)
        return Unit{}
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "WAL tombstone write failed")

# Opens the persisted SST and runs compaction over its WAL delta.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.delete(handle, bytes("6672657368"))
        _checked : Unit <- deleted(result)
        return Unit{}
    case Fail{_}: IO.die(Unit, 1, "SST-only reopen failed before compaction")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing(path)
    opened(result)
