import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the crash fixture when an expected outcome is missing.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def bytes.from_hex.result(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

def bytes.from_hex(value: String) -> Bytes.Bytes:
  bytes.from_hex.result(Bytes.from_hex(value))

def bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, (_, equal)): equal

def client.put.result(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (_, Fail{MyLSM.CommitUnknown{_, _}}):
      IO.print("COMMIT_UNKNOWN_RECEIVED")
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("expected CommitUnknown after owner response loss")

def client.opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Unit> <- MyLSM.Bytes.put(handle, bytes.from_hex("00ff"),
            bytes.from_hex("80fe"))
        client.put.result(pair)
    case Fail{_}: fail("could not connect to owner for crash test")

def read.valid(
  result: Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> Bool:
  match result:
    case Done{Some{value}}:
      bytes.equal(Bytes.eq(value, bytes.from_hex("80fe")))
    case _: False{}

def read.verify(
  handle: MyLSM.Bytes.Handle,
  valid: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        IO.print("COMMITTED_VALUE_RECOVERED")
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("owner crash lost or changed the acknowledged WAL value")

def verifier.read(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, result): read.verify(handle, read.valid(result))

def verifier.opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        value : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.get(handle, bytes.from_hex("00ff"))
        verifier.read(value)
    case Fail{_}: fail("database lock was not released after owner death")

def main.mode(path: String, mode: String) -> IO(Unit):
  match mode:
    case "client":
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing_wait(path, 1000, 10)
        client.opened(opened)
    case "verify":
      do IO<Unit>:
        opened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        verifier.opened(opened)
    case _: fail("unknown crash-test mode")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_CRASH_TEST_MODE"))
    main.mode(path, mode)
