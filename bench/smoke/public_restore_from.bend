import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Unwraps a fixed binary fixture.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Projects equality from a packed-byte comparison.
def equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, valid): valid

# Reports successful close after checking the restored record.
def closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_RESTORE_FROM_PASSED")
    case Fail{_}: IO.die(Unit, 1, "file-backed restored database did not close")

def checked.value(
  handle: MyLSM.Bytes.Handle,
  valid: Bool
) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit, 1, "file-backed restore changed binary value")
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        closed(result)

# Checks the restored value bytes through the public API.
def checked(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): IO.die(Unit, 1, "file-backed restore lost its binary key")
    case (_, Done{None{}}): IO.die(Unit, 1, "file-backed restore omitted its binary key")
    case (handle, Done{Some{value}}):
      checked.value(handle, equal(Bytes.eq(value, Bytes.new(512))))

# Reads the restored key after reopening the database.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "file-backed restored database could not open")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
          MyLSM.Bytes.get(handle, packed(Bytes.from_hex("00000000")))
        checked(pair)

# Reopens a destination only after file-backed restore succeeds.
def restored(
  +destination: String,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "file-backed restore failed")
    case Done{Unit{}}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(destination)
        opened(result)

def main() -> IO(Unit):
  do IO<Unit>:
    bundle : String <- IO.try(String, Console.get_env("MYLSM_BACKUP_PATH"))
    destination : String <- IO.try(String, Console.get_env("MYLSM_RESTORE_DESTINATION"))
    check_path : String <- IO.try(String, Console.get_env("MYLSM_RESTORE_CHECK_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.restore_from(destination, bundle)
    restored(check_path, result)
