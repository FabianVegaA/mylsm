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

# Creates the binary value that forces the WAL writer across a chunk boundary.
def value.expected() -> Bytes.Bytes:
  Bytes.new(131072)

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
            value.expected())
        client.put.result(pair)
    case Fail{_}: fail("could not connect to owner for crash test")

def read.valid(
  result: Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>,
  expected_present: Bool
) -> Bool:
  match result:
    case Done{Some{value}}:
      Bool.and(expected_present,
        bytes.equal(Bytes.eq(value, value.expected())))
    case Done{None{}}: Bool.not(expected_present)
    case Fail{_}: False{}

# Duplicates an expectation flag for independent verification branches.
def bool.clone.pair(value: Bool) -> Bool & Bool:
  match value:
    case True{}: (True{}, True{})
    case False{}: (False{}, False{})

# Confirms the recovered key state against the requested crash boundary.
def read.verify.present(
  handle: MyLSM.Bytes.Handle,
  expected_present: Bool
) -> IO(Unit):
  match expected_present:
    case True{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        IO.print("COMMITTED_VALUE_RECOVERED")
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        IO.print("UNCOMMITTED_VALUE_ABSENT")

def read.verify(
  handle: MyLSM.Bytes.Handle,
  valid: Bool,
  expected_present: Bool
) -> IO(Unit):
  match valid:
    case True{}:
      read.verify.present(handle, expected_present)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("owner crash lost or changed the acknowledged WAL value")

def verifier.read.cloned(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>,
  expected: Bool & Bool
) -> IO(Unit):
  match pair:
    case (handle, result):
      match expected:
        case (for_read, for_verify): read.verify(handle,
          read.valid(result, for_read), for_verify)

def verifier.read(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>,
  expected_present: Bool
) -> IO(Unit):
  verifier.read.cloned(pair, bool.clone.pair(expected_present))

def verifier.opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>,
  expected_present: Bool
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        value : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Maybe<&1, Bytes.Bytes>> <-
            MyLSM.Bytes.get(handle, bytes.from_hex("00ff"))
        verifier.read(value, expected_present)
    case Fail{_}: fail("database lock was not released after owner death")

def main.mode(path: String, mode: String, expected_present: Bool) -> IO(Unit):
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
        verifier.opened(opened, expected_present)
    case _: fail("unknown crash-test mode")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_CRASH_TEST_MODE"))
    expected : String <- IO.try(String, Console.get_env("MYLSM_EXPECT_PRESENT"))
    main.mode(path, mode, String.eq(expected, "yes"))
