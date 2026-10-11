import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Uses a zero-length buffer when a fixed fixture value cannot be decoded.
def parsed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Decodes the fixture's readable hexadecimal keys.
def bytes(hex: String) -> Bytes.Bytes:
  parsed(Bytes.from_hex(hex))

# Closes the database before reporting the fixture outcome.
def closed(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.print("BYTE_SST_BATCH_STATS_PASSED")
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "atomic batch did not reconcile visible SST stats")

def checked.stats.result(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, payload_bytes}}):
      closed(handle, Nat.is_eq(entries, 2n) && Nat.is_eq(payload_bytes, 8n))
    case (handle, Fail{_}): closed(handle, False{})

def checked.stats(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      MyLSM.Bytes.Stats> <- MyLSM.Bytes.stats(handle)
    checked.stats.result(pair)

def checked.batch(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}): checked.stats(handle)
    case (handle, Fail{_}): closed(handle, False{})

def checked.initial(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        result : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, Con{
            MyLSM.BytesPut{bytes("610062"), Bytes.new(0)},
            Con{MyLSM.BytesDelete{bytes("610062")},
              Con{MyLSM.BytesPut{bytes("01"), Bytes.new(0)},
                Con{MyLSM.BytesDelete{bytes("00ff")}, Nil{}}}}
          })
        checked.batch(result)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "initial SST stats did not match the fixture")

def initial.stats.result(pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Stats>) -> IO(Unit):
  match pair:
    case (handle, Done{MyLSM.ByteStats{entries, payload_bytes}}):
      checked.initial(handle,
        Nat.is_eq(entries, 3n) && Nat.is_eq(payload_bytes, 15n))
    case (handle, Fail{_}): closed(handle, False{})

def initial.stats(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      MyLSM.Bytes.Stats> <- MyLSM.Bytes.stats(handle)
    initial.stats.result(pair)

# Starts the accounting checks after opening the recovered fixture.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "atomic batch stats fixture open failed")
    case Done{handle}: initial.stats(handle)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing(path)
    opened(result)
