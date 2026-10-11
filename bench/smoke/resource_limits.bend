import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/DurableBatchPolicy.bend as BatchPolicy
import ../../src/Fs.bend as Fs
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes

# Stops the resource fixture when an observed limit differs from its contract.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Decodes a fixed hexadecimal byte vector for the fixture.
def packed.result(result: Maybe<&1, PackedBytes.Bytes>) -> PackedBytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: PackedBytes.new(0)

# Decodes a fixed hexadecimal byte vector for the fixture.
def packed(hex: String) -> PackedBytes.Bytes:
  packed.result(PackedBytes.from_hex(hex))

# Builds a zero-filled byte value of the requested length.
def value(length: Nat) -> PackedBytes.Bytes:
  +packed_length = U32.from_nat(length)
  PackedBytes.Bytes{packed_length, PackedBytes.alloc(packed_length)}

# Builds two Put records with an exact encoded frame size near the cap.
def bounded.batch(excess: Nat) -> List<&1, MyLSM.Bytes.Mutation>:
  value_bytes = Nat.add(Nat.sub(BatchPolicy.max_batch_bytes(), 57n), excess)
  Con{MyLSM.BytesPut{packed("61"), value(value_bytes)},
    Con{MyLSM.BytesPut{packed("62"), value(0n)}, Nil{}}}

# Closes a handle after a successful operation.
def close.ok(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.pure(Unit, Unit{})
    case Fail{_}: fail("resource fixture write or close failed")

# Checks that a successful write survived reopen after a rejected request.
def verified.value(
  handle: MyLSM.Bytes.Handle,
  comparison: PackedBytes.Bytes & PackedBytes.Bytes & Bool
) -> IO(Unit):
  match comparison:
    case (_, _, True{}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        IO.print("RESOURCE_BATCH_LIMITS_PASSED")
    case _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("valid handle write was not durable after rejection")

# Checks that a successful write survived reopen after a rejected request.
def verified(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
    Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{found}}):
      verified.value(handle, PackedBytes.eq(found, packed("76")))
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("valid handle write could not be read after reopen")

# Reopens the database and verifies that the handle remained usable.
def reopened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: fail("resource fixture database could not reopen")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, packed("6f6b"))
        verified(pair)

# Closes the handle after the post-rejection write succeeds.
def write.usable(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  path: String
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        close.ok(closed)
        reopened_result : Result<&1, &1, MyLSM.Bytes.Error,
          MyLSM.Bytes.Handle> <- MyLSM.Bytes.open_existing(path)
        reopened(reopened_result)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("handle stopped accepting writes after resource rejection")

# Writes a valid record after the oversized request left the handle intact.
def handle.usable(handle: MyLSM.Bytes.Handle, path: String) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.put(handle, packed("6f6b"), packed("76"))
    write.usable(pair, path)

# Chooses whether the rejected request left the WAL byte-for-byte unchanged.
def wal.after.checked(
  db_handle: MyLSM.Bytes.Handle,
  path: String,
  unchanged: Bool
) -> IO(Unit):
  match unchanged:
    case True{}: handle.usable(db_handle, path)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(db_handle)
        fail("rejected batch changed the persisted WAL length")

# Checks persisted WAL length after the oversized request was rejected.
def wal.after(
  handle: MyLSM.Bytes.Handle,
  path: String,
  before: Nat,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Unit):
  match result:
    case Done{after}:
      wal.after.checked(handle, path, Nat.is_eq(before, after))
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("could not stat WAL after rejected batch")

# Requires a too-large encoded frame to return ResourceLimit before WAL append.
def above.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  +path: String,
  before: Nat
) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.ResourceLimit{}}):
      do IO<Unit>:
        after : Result<&1, &1, U32 & String, Nat> <-
          Fs.file_size(path ++ "/WAL")
        wal.after(handle, path, before, after)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("batch above the byte limit was not rejected as ResourceLimit")

# Captures WAL size immediately before submitting the oversized batch.
def reject.above(
  handle: MyLSM.Bytes.Handle,
  path: String,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Unit):
  match result:
    case Done{before}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, bounded.batch(2n))
        above.result(pair, path, before)
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("could not stat WAL before oversized batch")

# Starts the just-above-limit request after below and exact-boundary writes.
def reject.before(handle: MyLSM.Bytes.Handle, +path: String) -> IO(Unit):
  do IO<Unit>:
    before : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/WAL")
    reject.above(handle, path, before)

# Requires a frame exactly at the configured byte ceiling to be accepted.
def at.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  path: String
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}): reject.before(handle, path)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("batch at the encoded byte limit was rejected")

# Submits a batch whose encoded frame is exactly one byte below its ceiling.
def write.at(handle: MyLSM.Bytes.Handle, path: String) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.write_batch(handle, bounded.batch(1n))
    at.result(pair, path)

# Requires a frame below the configured byte ceiling to be accepted.
def below.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  path: String
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}): write.at(handle, path)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("batch below the encoded byte limit was rejected")

# Submits a batch whose encoded frame is exactly one byte below its ceiling.
def write.below(handle: MyLSM.Bytes.Handle, path: String) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.write_batch(handle, bounded.batch(0n))
    below.result(pair, path)

# Starts limit-boundary checks on a newly created byte database.
def created(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>,
  path: String
) -> IO(Unit):
  match result:
    case Done{handle}: write.below(handle, path)
    case Fail{_}: fail("could not create resource-limit fixture")

# Runs batch-size boundary checks against one temporary database.
def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.create(path)
    created(result, path)
