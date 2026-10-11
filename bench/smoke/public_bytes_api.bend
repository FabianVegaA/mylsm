import Base
import ../../mylsm.bend as MyLSM

import ../../src/Console.bend as Console
import ../../src/DurableBatchPolicy.bend as BatchPolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes

def bytes.parsed(result: Maybe<&1, PackedBytes.Bytes>) -> PackedBytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: PackedBytes.new(0)

# Decodes a closed hexadecimal fixture into its packed bytes.
def bytes(hex: String) -> PackedBytes.Bytes:
  bytes.parsed(PackedBytes.from_hex(hex))

def equal.result(pair: PackedBytes.Bytes & PackedBytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

def verify.read.post.value(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.print("PUBLIC_BYTES_RECOVERED")
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte WAL tail was not recovered")

def verify.read.post.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      verify.read.post.value(handle, equal.result(PackedBytes.eq(value, bytes("77616c"))))
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte WAL tail is missing")

def verify.read.post(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
      MyLSM.Bytes.get(handle, bytes("706f7374"))
    verify.read.post.result(pair)

def verify.read.tombstone.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{None{}}):
      verify.read.post(handle)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte SST did not retain its tombstone")

def verify.read.tombstone(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
      MyLSM.Bytes.get(handle, bytes("64656164"))
    verify.read.tombstone.result(pair)

def verify.read.value(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}: verify.read.tombstone(handle)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte API changed stored bytes")

def verify.read(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      verify.read.value(handle, equal.result(PackedBytes.eq(value, bytes("80ff00"))))
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte API did not recover the key")

def checked.write.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_BYTES_WRITTEN")
    case Fail{_}: IO.die(Unit, 1, "public byte API close failed")

def checked.stats.valid(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        checked.write.closed(closed)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "byte stats did not report the canonical live table")

def checked.stats.result(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, payload_bytes}}):
      checked.stats.valid(handle, Nat.is_eq(entries, 3n) && Nat.is_eq(payload_bytes, 15n))
    case (handle, Fail{_}): checked.stats.valid(handle, False{})

def checked.write.after.flush(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        stats : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          MyLSM.Bytes.Stats> <- MyLSM.Bytes.stats(handle)
        checked.stats.result(stats)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte post-flush write failed")

def checked.write.compacted(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, bytes("706f7374"), bytes("77616c"))
        checked.write.after.flush(written)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte SST compaction failed")

def checked.write.flushed(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        compacted : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.compact(handle)
        checked.write.compacted(compacted)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte SST flush failed")

def checked.write(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.flush(handle)
        checked.write.flushed(flushed)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte API write failed")

def create.write.valid(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.write_batch(handle, Con{
        MyLSM.BytesPut{bytes("610062"), bytes("80ff00")},
        Con{MyLSM.BytesPut{bytes("00ff"), bytes("")},
          Con{MyLSM.BytesPut{bytes("64656164"), bytes("6f6c64")},
            Con{MyLSM.BytesDelete{bytes("64656164")}, Nil{}}}}
      })
    checked.write(pair)

# Builds one more mutation than the public batch limit.
def oversized.batch(fuel: Nat) -> List<&1, MyLSM.Bytes.Mutation>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest:
      Con{MyLSM.BytesPut{bytes("oversized"), bytes("value")},
        oversized.batch(rest)}

# Confirms the oversized request is rejected before the valid write continues.
def create.batch.rejected(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{MyLSM.InvalidArgument{}}:
      create.write.valid(handle)
    case _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "public byte API accepted an oversized batch")

def create.write.oversized.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (next_handle, outcome): create.batch.rejected(next_handle, outcome)

def create.write.oversized(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.write_batch(handle,
        oversized.batch(Nat.add(BatchPolicy.max_batch_count(), 1n)))
    create.write.oversized.result(result)

def create.result(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      create.write.oversized(handle)
    case Fail{_}: IO.die(Unit, 1, "public byte API create failed")

def open.result(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, bytes("610062"))
        verify.read(pair)
    case Fail{_}: IO.die(Unit, 1, "public byte API reopen failed")

# Runs either the persistence or recovery half of the fixture.
def run(path: String, mode: String) -> IO(Unit):
  match mode:
    case "create":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <- MyLSM.Bytes.create(path)
        create.result(result)
    case _:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <- MyLSM.Bytes.open_existing_wait(path, 1000, 10)
        open.result(result)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_BYTES_MODE"))
    run(path, mode)
