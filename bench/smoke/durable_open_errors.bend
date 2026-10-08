import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM

# Lists public error categories checked by the open fixture.
type ExpectedKind is Data:
  Valid{}
  Unsupported{}
  Corrupt{}
  Missing{}
  IoFailure{}

# Continues the expected kind fixture step.
def expected_kind(kind: MyLSM.ErrorKind, expected: ExpectedKind) -> Bool:
  match kind expected:
    case MyLSM.IoError{} Valid{}: False{}
    case MyLSM.UnsupportedFormatError{} Unsupported{}: True{}
    case MyLSM.CorruptionError{} Corrupt{}: True{}
    case MyLSM.NotFoundError{} Missing{}: True{}
    case MyLSM.IoError{} IoFailure{}: True{}
    case _ _: False{}

# Continues the expected result fixture step.
def expected_result(error: MyLSM.Error, expected: ExpectedKind) -> Bool:
  match error:
    case MyLSM.Error{kind, _, _, _, _}:
      expected_kind(kind, expected)

def error_result.checked(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("OPEN_ERROR_" ++ label)
    case False{}:
      IO.die(Unit, 1, "open returned the wrong public error")

# Continues the error result fixture step.
def error_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>, expected: ExpectedKind, label: String) -> IO(Unit):
  match result:
    case Fail{error}:
      error_result.checked(expected_result(error, expected), label)
    case Done{handle}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "invalid manifest opened successfully")

# Continues the expectation fixture step.
def expectation(name: String) -> ExpectedKind:
  match name:
    case "valid_0_4": Valid{}
    case "unsupported": Unsupported{}
    case "corrupt": Corrupt{}
    case "io": IoFailure{}
    case _: Missing{}

# Continues the valid closed result fixture step.
def valid_closed_result(result: Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OPEN_VALID")
    case Fail{_}: IO.die(Unit, 1, "valid Manifest handle did not close")

# Continues the valid result fixture step.
def valid_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Fail{MyLSM.Error{_, _, _, _, host_message}}:
      do IO<Unit>:
        IO.print("OPEN_VALID_ERROR " ++ host_message)
        IO.die(Unit, 1, "valid Manifest did not open")
    case Done{handle}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        valid_closed_result(closed)

# Runs the open result step of this fixture.
def open_result(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>, expected: ExpectedKind, label: String) -> IO(Unit):
  match expected:
    case Valid{}:
      valid_result(result)
    case _:
      error_result(result, expected, label)

# Runs the seeded closed step of this fixture.
def seeded_closed(result: Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      IO.print("OPEN_SST_SEEDED")
    case Fail{_}:
      IO.die(Unit, 1, "SST seed close failed")

# Runs the seeded flushed step of this fixture.
def seeded_flushed(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        seeded_closed(closed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "SST seed flush failed")

# Runs the seeded written step of this fixture.
def seeded_written(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>) -> IO(Unit):
  match pair:
    case (handle, Done{_}):
      do IO<Unit>:
        flushed : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.flush(handle)
        seeded_flushed(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "SST seed write failed")

# Runs the seeded created step of this fixture.
def seeded_created(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        written : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.put(handle, "sst-seed", "value")
        seeded_written(written)
    case Fail{_}:
      IO.die(Unit, 1, "SST seed create failed")

# Runs the run mode step of this fixture.
def run_mode(path: String, mode: String, expected: ExpectedKind, label: String) -> IO(Unit):
  match mode:
    case "seed_sst":
      do IO<Unit>:
        created : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.create(path)
        seeded_created(created)
    case _:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        open_result(result, expected, label)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_OPEN_MODE"))
    +expected_name : String <- IO.try(String, Console.get_env("MYLSM_EXPECTED_ERROR"))
    run_mode(path, mode, expectation(expected_name), expected_name)
