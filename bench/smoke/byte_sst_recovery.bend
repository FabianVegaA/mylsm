import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Builds the packed bytes represented by a fixed hexadecimal fixture.
def packed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def finish.decide(valid: Bool & Bool) -> IO(Unit):
  match valid:
    case (True{}, True{}): IO.print("BYTE_SST_RECOVERY_PASSED")
    case (True{}, False{}):
      IO.die(Unit, 1, "recovered byte database close failed")
    case (False{}, _): IO.die(Unit, 1, "multi-block recovery lost an SST entry")

# Reports the result after releasing the recovered database handle.
def finish(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  valid: Bool
) -> IO(Unit):
  match result:
    case Done{Unit{}}: finish.decide((valid, True{}))
    case Fail{_}: finish.decide((valid, False{}))

# Reports whether multi-block byte SST recovery rebuilt both entries.
def checked.entries(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        finish(result, True{})
    case False{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        finish(result, False{})

def checked.deleted.stats.result(
  pair:
    MyLSM.Bytes.Handle &
      Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>
) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, payload_bytes, _, _, _}}):
      checked.entries(handle, Bool.and(Nat.is_eq(entries, 2n),
        Nat.is_eq(payload_bytes, 4n)))
    case (handle, Fail{_}): checked.entries(handle, False{})

def checked.deleted.stats(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      MyLSM.Bytes.Stats> <- MyLSM.Bytes.stats(handle)
    checked.deleted.stats.result(pair)

def checked.deleted(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      checked.deleted.stats(handle)
    case (handle, _): checked.entries(handle, False{})

def checked.replaced.count(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case False{}: checked.entries(handle, False{})
    case True{}:
      do IO<Unit>:
        removed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.delete(handle, Bytes.new(1))
        checked.deleted(removed)

def checked.replaced.stats.result(
  pair:
    MyLSM.Bytes.Handle &
      Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>
) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, payload_bytes, _, _, _}}):
      checked.replaced.count(handle, Bool.and(Nat.is_eq(entries, 3n),
        Nat.is_eq(payload_bytes, 600005n)))
    case (handle, Fail{_}): checked.entries(handle, False{})

def checked.replaced.stats(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      MyLSM.Bytes.Stats> <- MyLSM.Bytes.stats(handle)
    checked.replaced.stats.result(pair)

def checked.replaced(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      checked.replaced.stats(handle)
    case (handle, _): checked.entries(handle, False{})

def checked.after.write.count(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case False{}: checked.entries(handle, False{})
    case True{}:
      do IO<Unit>:
        replaced : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, packed(Bytes.from_hex("0000")), Bytes.new(0))
        checked.replaced(replaced)

def checked.after.write.result(
  pair:
    MyLSM.Bytes.Handle &
      Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>
) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, _, _, _, _}}):
      checked.after.write.count(handle, Nat.is_eq(entries, 3n))
    case (handle, Fail{_}): checked.entries(handle, False{})

def checked.after.write(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      MyLSM.Bytes.Stats> <- MyLSM.Bytes.stats(handle)
    checked.after.write.result(pair)

def checked.write(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      checked.after.write(handle)
    case (handle, _): checked.entries(handle, False{})

def checked.after.read.start(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case False{}: checked.entries(handle, False{})
    case True{}:
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, packed(Bytes.from_hex("0002")), Bytes.new(0))
        checked.write(written)

def checked.after.read.result(
  pair:
    MyLSM.Bytes.Handle &
      Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>
) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, _, _, _, _}}):
      checked.after.read.start(handle, Nat.is_eq(entries, 2n))
    case (handle, Fail{_}): checked.entries(handle, False{})

def checked.after.read(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      MyLSM.Bytes.Stats> <- MyLSM.Bytes.stats(handle)
    checked.after.read.result(pair)

def checked.read(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{_}}):
      checked.after.read(handle)
    case (handle, _): checked.entries(handle, False{})

def checked.count(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case False{}: checked.entries(handle, False{})
    case True{}:
      do IO<Unit>:
        found : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Maybe<&1, Bytes.Bytes>> <-
          MyLSM.Bytes.get(handle, packed(Bytes.from_hex("0000")))
        checked.read(found)

# Checks the canonical entry count produced by blockwise recovery.
def checked.result(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, _, _, _, _}}):
      checked.count(handle, Nat.is_eq(entries, 2n))
    case (handle, Fail{_}): checked.entries(handle, False{})

# Reads final counters and verifies the recovered database's canonical state.
def checked(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      MyLSM.Bytes.Stats> <- MyLSM.Bytes.stats(handle)
    checked.result(pair)

# Opens the multi-block fixture through the public byte API.
def opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "multi-block byte database recovery failed")
    case Done{handle}: checked(handle)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing(path)
    opened(result)
