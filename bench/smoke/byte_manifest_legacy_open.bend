import Base
import ../../mylsm.bend as MyLSM
import ../../src/ByteManifest.bend as ByteManifest
import ../../src/ByteManifestIo.bend as ByteManifestIo
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.parsed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Decodes a closed hexadecimal test value into packed bytes.
def bytes(hex: String) -> Bytes.Bytes:
  bytes.parsed(Bytes.from_hex(hex))

def equal.result(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

def path.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.pair(path: String) -> String & String:
  path.pair.go(path, SNil{}, SNil{})

# Stops this fixture when a legacy-compatibility expectation fails.
def require(valid: Bool, message: String) -> IO(Unit):
  match valid:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

def result.closed(
  valid: Bool,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        require(valid, "generation-four database was not readable through its legacy manifest")
        IO.print("LEGACY_MANIFEST_OPEN_PASSED")
    case Fail{_}: IO.die(Unit, 1, "generation-four database did not close")

def value.read(
  pair:
    MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, Done{Some{value}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        result.closed(equal.result(Bytes.eq(value, bytes("80ff00"))), closed)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "generation-four SST value was not recovered")

def database.opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle &
          Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>> <-
          MyLSM.Bytes.get(handle, bytes("610062"))
        value.read(pair)
    case Fail{_}: IO.die(Unit, 1, "generation-four manifest was not accepted")

def manifest.written(
  path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        database : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        database.opened(database)
    case Fail{_}: IO.die(Unit, 1, "generation-four manifest fixture could not be written")

def main.paths(pair: String & String) -> IO(Unit):
  match pair:
    case (for_write, for_open):
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, Unit> <-
          ByteManifestIo.write_atomic(for_write, ByteManifest.HasSst{})
        manifest.written(for_open, result)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    paths : String & String <- IO.pure(String & String, path.pair(path))
    main.paths(paths)
