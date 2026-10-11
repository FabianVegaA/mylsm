import Base
import ../../src/ByteDurableDb.bend as ByteDurableDb
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the snapshot budget fixture after a failed assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Closes the retained handle after either budget-boundary result.
def finish(handle: ByteDurableDb.Handle, accepted: Bool) -> IO(Unit):
  match accepted:
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDurableDb.Error, Unit> <- ByteDurableDb.close(handle)
        fail("snapshot was not admitted at its exact byte budget")
    case True{}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDurableDb.Error, Unit> <- ByteDurableDb.close(handle)
        IO.print("SNAPSHOT_PREFLIGHT_PASSED")

def admitted.result(
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, List<&1, ByteMemTable.Entry>>
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}): finish(handle, False{})
    case (handle, Done{entries}):
      finish(handle, Nat.is_eq(List.length(&1, ByteMemTable.Entry, entries), 1n))

def rejected.result(
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, List<&1, ByteMemTable.Entry>>
) -> IO(Unit):
  match pair:
    case (handle, Fail{ByteDurableDb.ResourceLimit{}}):
      do IO<Unit>:
        accepted : ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error,
          List<&1, ByteMemTable.Entry>> <- ByteDurableDb.snapshot_limited(32n, handle)
        admitted.result(accepted)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDurableDb.Error, Unit> <- ByteDurableDb.close(handle)
        fail("snapshot preflight did not reject a budget below retained bytes")

def seeded.flushed(
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        rejected_pair : ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error,
          List<&1, ByteMemTable.Entry>> <- ByteDurableDb.snapshot_limited(31n, handle)
        rejected.result(rejected_pair)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDurableDb.Error, Unit> <- ByteDurableDb.close(handle)
        fail("snapshot preflight fixture flush failed")

def seeded.result(
  pair: ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.flush(handle)
        seeded.flushed(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDurableDb.Error, Unit> <- ByteDurableDb.close(handle)
        fail("snapshot preflight fixture seed failed")

def created.result(
  result: Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.Handle>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("snapshot preflight database creation failed")
    case Done{handle}:
      do IO<Unit>:
        seeded : ByteDurableDb.Handle & Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.put(handle, Bytes.new(0), Bytes.new(0))
        seeded.result(seeded)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    created : Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.Handle> <-
      ByteDurableDb.create(path)
    created.result(created)
