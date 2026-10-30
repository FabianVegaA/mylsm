import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Handles fail.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Handles equal.
def equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, valid): valid

# Handles packed.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Handles closed.
def closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("RESTORE_REOPEN_PASSED")
    case Fail{_}: fail("restored database close failed")

def value.checked(handle: MyLSM.Bytes.Handle, valid: Bool) -> IO(Unit):
  match valid:
    case False{}: fail("restored database value differs")
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        closed(result)

# Handles value.
def value(
  pair: MyLSM.Bytes.Handle &
    Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      value.checked(handle, equal(Bytes.eq(value, packed(Bytes.from_hex("00ff")))))
    case (_, _): fail("restored database key is missing")

# Handles opened.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: fail("restored database could not reopen")
    case Done{handle}:
      do IO<Unit>:
        result : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.get(handle, packed(Bytes.from_hex("006b")))
        value(result)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing(path)
    opened(result)
