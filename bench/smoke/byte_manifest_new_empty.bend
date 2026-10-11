import Base
import ../../mylsm.bend as MyLSM
import ../../src/ByteManifest.bend as ByteManifest
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Duplicates a path for independent create and manifest-read operations.
def path.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.pair(path: String) -> String & String:
  path.pair.go(path, SNil{}, SNil{})

def open.closed(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("GENERATION_FIVE_EMPTY_OPEN_PASSED")
    case Fail{_}: IO.die(Unit, 1, "new empty generation-five database did not reopen")

def database.opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        open.closed(closed)
    case Fail{_}: IO.die(Unit, 1, "new empty generation-five manifest did not open")

def manifest.decoded(
  path: String,
  decoded: Result<&1, &1, ByteManifest.Error, ByteManifest.ManifestValue>
) -> IO(Unit):
  match decoded:
    case Done{ByteManifest.GenerationEmpty{}}:
      do IO<Unit>:
        IO.print("GENERATION_FIVE_EMPTY_MANIFEST_PASSED")
        reopened : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.open_existing(path)
        database.opened(reopened)
    case _:
      IO.die(Unit, 1, "new empty database did not publish a generation-five manifest")

def manifest.read(
  path: String,
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Unit):
  match pair:
    case (file, Done{bytes}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        manifest.decoded(path, ByteManifest.decode(bytes))
    case (file, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(file)
        IO.die(Unit, 1, "new empty database manifest could not be read")

def manifest.file.opened(
  path: String,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Unit):
  match opened:
    case Done{file}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_bytes(file, 64)
        manifest.read(path, pair)
    case Fail{_}: IO.die(Unit, 1, "new empty database manifest could not be opened")

def created.closed(
  paths: String & String,
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match paths:
    case (open_path, inspect_path):
      match result:
        case Done{Unit{}}:
          do IO<Unit>:
            opened : Result<&1, &1, U32 & String, File> <-
              File.open(open_path ++ "/MANIFEST", "r")
            manifest.file.opened(inspect_path, opened)
        case Fail{_}: IO.die(Unit, 1, "new empty database did not close")

def database.created(
  pair: String & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match pair:
    case (path, Done{handle}):
      do IO<Unit>:
        paths : String & String <- IO.pure(String & String, path.pair(path))
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        created.closed(paths, closed)
    case (_, Fail{_}): IO.die(Unit, 1, "new empty database creation failed")

def main.paths(paths: String & String) -> IO(Unit):
  match paths:
    case (create_path, inspect_path):
      do IO<Unit>:
        created : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.create(create_path)
        database.created((inspect_path, created))

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    paths : String & String <- IO.pure(String & String, path.pair(path))
    main.paths(paths)
