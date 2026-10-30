import Base
import ../../src/ByteDurableDb.bend as ByteDb
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/ByteWal.bend as ByteWal
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Closes the database after confirming the published SST replaced its delta.
def closed(result: Result<&1, &1, ByteDb.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("BYTE_FLUSH_CLEARS_DELTA_PASSED")
    case Fail{_}: IO.die(Unit, 1, "byte SST fixture close failed")

# Preserves public visible totals after replacing the delta with an SST.
def flushed.length.tombstoned(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, U32>>
) -> IO(Unit):
  match pair:
    case (handle, Done{None{}}):
      do IO<Unit>:
        result : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        closed(result)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "delta tombstone did not hide the SST value length")

def flushed.length.deleted(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        measured : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, U32>> <-
          ByteDb.value_length(handle, Bytes.new(4))
        flushed.length.tombstoned(measured)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "delta tombstone fixture write failed")

def flushed.length.absent(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, U32>>
) -> IO(Unit):
  match pair:
    case (handle, Done{None{}}):
      do IO<Unit>:
        deleted : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.delete(handle, Bytes.new(4))
        flushed.length.deleted(deleted)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "absent SST key returned a value length")

def flushed.length.stats.valid(handle: ByteDb.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        absent : ByteDb.Handle & Result<&1, &1, ByteDb.Error,
          Maybe<&1, U32>> <- ByteDb.value_length(handle, Bytes.new(3))
        flushed.length.absent(absent)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "metadata lookup changed persisted database statistics")

def flushed.length.stats.after(
  pair: ByteDb.Handle & ByteDb.Stats,
  length: U32,
  expected_entries: Nat,
  expected_payload: Nat
) -> IO(Unit):
  match pair:
    case (handle, ByteDb.Stats{entries, payload_bytes}):
      flushed.length.stats.valid(handle,
        U32.is_eq(length, 16) && Nat.is_eq(entries, expected_entries) &&
          Nat.is_eq(payload_bytes, expected_payload))

def flushed.length.present(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, U32>>,
  expected_entries: Nat,
  expected_payload: Nat
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{length}}):
      flushed.length.stats.after(ByteDb.stats(handle), length,
        expected_entries, expected_payload)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "SST metadata did not find the published key")


def flushed.stats.checked(handle: ByteDb.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "flush lost visible SST statistics")
    case True{}:
      do IO<Unit>:
        measured : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, U32>> <-
          ByteDb.value_length(handle, Bytes.new(4))
        flushed.length.present(measured, 1n, 20n)

# Requires the compacted SST record totals to remain visible after flush.
def flushed.stats(pair: ByteDb.Handle & ByteDb.Stats) -> IO(Unit):
  match pair:
    case (handle, ByteDb.Stats{entries, payload_bytes}):
      flushed.stats.checked(handle,
        Nat.is_eq(entries, 1n) && Nat.is_eq(payload_bytes, 20n))

# Checks the raw delta and closes the returned database handle.
def flushed.handle(handle: ByteDb.Handle) -> IO(Unit):
  match handle:
    case ByteDb.Handle{path, lock, ByteMemTable.Table{entries}, state, stats}:
      match entries:
        case Nil{}:
          flushed.stats(ByteDb.stats(
            ByteDb.Handle{path, lock, ByteMemTable.Table{Nil{}}, state, stats}))
        case Con{_, _}:
          IO.die(Unit, 1, "flush retained entries already published to SST")

# Checks the returned raw handle after its SST and WAL checkpoint publish.
def flushed(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}): flushed.handle(handle)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "byte SST flush failed")

# Writes a single byte record before flushing the active delta.
def written.length.equal(handle: ByteDb.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "delta metadata returned the wrong value length")
    case True{}:
      do IO<Unit>:
        result : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.flush(handle)
        flushed(result)

# Creates a database and seeds one byte record for the flush transition.
def written.length.checked(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, U32>>
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{length}}):
      written.length.equal(handle, U32.is_eq(length, 16))
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "delta metadata did not find the live value")


# Handles written.
def written(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        measured : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, U32>> <-
          ByteDb.value_length(handle, Bytes.new(4))
        written.length.checked(measured)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
        IO.die(Unit, 1, "byte SST fixture write failed")


# Handles created.
def created(
  result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.write_batch(handle,
            Con{ByteWal.Put{Bytes.new(4), Bytes.new(16)}, Nil{}})
        written(pair)
    case Fail{_}: IO.die(Unit, 1, "byte SST fixture database create failed")

# Runs the flush delta regression against a fresh temporary database path.
def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <- ByteDb.create(path)
    created(result)
