import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the fixture at its first restored owner-view mismatch.
def require(valid: Bool, message: String) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def bytes.from_hex.result(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Decodes one fixed hexadecimal key or expected value.
def expected(value: String) -> Bytes.Bytes:
  bytes.from_hex.result(Bytes.from_hex(value))

# Extracts the comparison result while preserving byte buffers.
def equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, valid): valid

# Reports that the restored database released its lock successfully.
def closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("PUBLIC_OWNER_BACKUP_RESTORE_PASSED")
    case Fail{_}: IO.die(Unit, 1, "restored owner view did not close")

def value.checked.match(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        closed(result)
    case False{}: IO.die(Unit, 1, "owner backup changed the binary value")


def value.checked(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match result:
    case Done{Some{value}}:
      value.checked.match(handle,
        equal(Bytes.eq(value, expected("80ff00"))))
    case _: IO.die(Unit, 1, "owner backup omitted its binary key")

def value.pair(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, result): value.checked(handle, result)

def database.opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        value : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.get(handle, expected("00ff"))
        value.pair(value)
    case Fail{_}: IO.die(Unit, 1, "restored owner backup did not reopen")

# Reopens only after restore publishes the owner snapshot successfully.
def restored(
  destination: String,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(destination)
        database.opened(opened)
    case Fail{_}: IO.die(Unit, 1, "owner backup restore failed")

def main.restore(
  destination: String,
  check_path: String,
  bundle: String
) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
      MyLSM.Bytes.restore_from(destination, bundle)
    restored(check_path, result)

def main() -> IO(Unit):
  do IO<Unit>:
    bundle : String <- IO.try(String, Console.get_env("MYLSM_BACKUP_PATH"))
    destination : String <-
      IO.try(String, Console.get_env("MYLSM_RESTORE_DESTINATION"))
    check_path : String <-
      IO.try(String, Console.get_env("MYLSM_RESTORE_CHECK_PATH"))
    main.restore(destination, check_path, bundle)
