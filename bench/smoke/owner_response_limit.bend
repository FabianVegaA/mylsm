import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes

# Stops the smoke with a failure message.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def bytes.parsed(result: Maybe<&1, PackedBytes.Bytes>) -> PackedBytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: PackedBytes.new(0)

# Decodes a hexadecimal fixture into bytes.
def bytes(hex: String) -> PackedBytes.Bytes:
  bytes.parsed(PackedBytes.from_hex(hex))

def big.key() -> PackedBytes.Bytes:
  bytes("626967")

def after.key() -> PackedBytes.Bytes:
  bytes("6166746572")

def after.value() -> PackedBytes.Bytes:
  bytes("6f6b")

# Prints the stage marker after the handle closes.
def closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  message: String) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print(message)
    case Fail{_}: fail("owner response limit handle close failed")

def close.with(handle: MyLSM.Bytes.Handle, message: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.close(handle)
    closed(result, message)

def setup.written(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      close.with(handle, "OWNER_RESPONSE_LIMIT_SETUP")
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("local write of the oversized value failed")

def setup.created(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, big.key(), PackedBytes.new(8192))
        setup.written(pair)
    case Fail{_}: fail("owner response limit database create failed")

# Creates the database and writes a value larger than the response limit.
def setup(path: String) -> IO(Unit):
  do IO<Unit>:
    created : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.create(path)
    setup.created(created)

def value.equal(pair: PackedBytes.Bytes & PackedBytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

def after.checked(handle: MyLSM.Bytes.Handle, matches: Bool) -> IO(Unit):
  match matches:
    case True{}: close.with(handle, "OWNER_RESPONSE_LIMIT_CLIENT")
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("value written after the limit was not read back")

def after.read(
  pair:
    MyLSM.Bytes.Handle &
      Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      after.checked(handle,
        value.equal(PackedBytes.eq(value, after.value())))
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("read after the limit failed")

def after.written(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        read : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, after.key())
        after.read(read)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("write after the oversized read failed")

def big.read(
  pair:
    MyLSM.Bytes.Handle &
      Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.ResourceLimit{}}):
      do IO<Unit>:
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.put(handle, after.key(), after.value())
        after.written(written)
    case (handle, Fail{MyLSM.CommitUnknown{_, _}}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("oversized read reported CommitUnknown")
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("oversized read did not report ResourceLimit")

def client.opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        read : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
          MyLSM.Bytes.get(handle, big.key())
        big.read(read)
    case Fail{_}: fail("remote open through the owner failed")

# Reads the large value through the owner and checks the handle still works.
def client(path: String) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing(path)
    client.opened(opened)

def run.mode(mode: String, path: String) -> IO(Unit):
  match mode:
    case "setup": setup(path)
    case "client": client(path)
    case _: fail("unknown owner response limit mode")

def main() -> IO(Unit):
  do IO<Unit>:
    mode : String <- IO.try(String, Console.get_env("MYLSM_RESPONSE_LIMIT_MODE"))
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    run.mode(mode, path)
