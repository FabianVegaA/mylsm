import Base
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/Wal.bend as Wal
import ../../src/transfer/MigrateIo.bend as MigrateIo
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Terminates the fixture with a readable failure reason.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def fixture.frame(result: Result<&1, &1, Wal.Error, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Done{bytes}: Bytes.concat([Wal.log_header(), bytes])
    case Fail{_}: Bytes.new(0)

def write.closed.result(
  result: Result<&1, &1, U32 & String, Unit>,
  message: String
) -> IO(Unit):
  match result:
    case Fail{_}: fail(message)
    case Done{Unit{}}: IO.pure(Unit, Unit{})

def write.closed(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  message: String
) -> IO(Unit):
  match pair:
    case (file, result):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        write.closed.result(result, message)

def write.opened(
  opened: Result<&1, &1, U32 & String, File>,
  bytes: Bytes.Bytes
) -> IO(Unit):
  match opened:
    case Fail{_}: fail("could not create legacy WAL fixture")
    case Done{file}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        write.closed(pair, "could not write legacy WAL fixture")

# Writes fixture bytes through the repository's host filesystem boundary.
def write(path: String, bytes: Bytes.Bytes) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    write.opened(opened, bytes)

def verify.result(result: Result<&1, &1, MigrateIo.Error, Nat>) -> IO(Unit):
  match result:
    case Done{1n}: IO.print("LEGACY_WAL_READ_ONLY_PASSED")
    case Done{_}: fail("legacy WAL verifier returned the wrong frame count")
    case Fail{_}: fail("legacy WAL verifier rejected a valid source")

def verify.invalid(result: Result<&1, &1, MigrateIo.Error, Nat>) -> IO(Unit):
  match result:
    case Done{_}: fail("legacy WAL verifier accepted malformed source")
    case Fail{MigrateIo.InvalidLegacyWal{}}: IO.print("LEGACY_WAL_REJECTION_PASSED")
    case Fail{_}: fail("legacy WAL verifier returned the wrong error")

def fixture.create(+directory: String) -> IO(Unit):
  do IO<Unit>:
    write(directory ++ "/LOCK", Bytes.new(0))
    write(directory ++ "/WAL", fixture.frame(Wal.encode_frame(
      Wal.Batch{Con{Wal.Put{"legacy", "value"}, Nil{}}})))
    IO.print("LEGACY_WAL_FIXTURE_CREATED")

def fixture.corrupt(directory: String) -> IO(Unit):
  write(directory ++ "/WAL", Bytes.new(0))

def mode.is_create(mode: String) -> Bool:
  String.eq(mode, "create")

def mode.is_invalid(mode: String) -> Bool:
  String.eq(mode, "verify-invalid")

def verify.dispatch(
  result: Result<&1, &1, MigrateIo.Error, Nat>,
  invalid: Bool
) -> IO(Unit):
  match invalid:
    case True{}: verify.invalid(result)
    case False{}: verify.result(result)

def mode.run(+directory: String, create: Bool, corrupt: Bool, invalid: Bool) -> IO(Unit):
  match create:
    case True{}: fixture.create(directory)
    case False{}:
      match corrupt:
        case True{}: fixture.corrupt(directory)
        case False{}:
          do IO<Unit>:
            result : Result<&1, &1, MigrateIo.Error, Nat> <-
              MigrateIo.verify_legacy_wal(directory)
            verify.dispatch(result, invalid)

def main() -> IO(Unit):
  do IO<Unit>:
    +directory : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    +mode : String <- IO.try(String, Console.get_env("MYLSM_FIXTURE_MODE"))
    mode.run(directory, mode.is_create(mode), String.eq(mode, "corrupt"),
      mode.is_invalid(mode))
