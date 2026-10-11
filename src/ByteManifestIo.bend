import Base
import ./ByteManifest.bend as Manifest
import ./Fs.bend as Fs
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Separates invalid manifest bytes from filesystem failures while opening it.
type Error is Data:
  Invalid{error: Manifest.Error}
  Host{code: U32, message: String}

def path.reverse(path: String, reversed: String) -> String:
  match path:
    case SNil{}: reversed
    case SCon{character, rest}: path.reverse(rest, SCon{character, reversed})

def path.clone(path: String) -> String:
  path.reverse(path.reverse(path, SNil{}), SNil{})

def read.result(
  result: Result<&1, &1, Manifest.Error, Manifest.ManifestValue>
) -> IO(Result<&1, &1, Error, Manifest.ManifestValue>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Manifest.ManifestValue>, Fail{Invalid{error}})
    case Done{value}:
      IO.pure(Result<&1, &1, Error, Manifest.ManifestValue>, Done{value})

def read.host(error: U32 & String) -> IO(Result<&1, &1, Error, Manifest.ManifestValue>):
  match error:
    case (code, message):
      IO.pure(Result<&1, &1, Error, Manifest.ManifestValue>, Fail{Host{code, message}})

def read.decoded(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, Error, Manifest.ManifestValue>):
  match pair:
    case (file, Fail{error}):
      do IO<Result<&1, &1, Error, Manifest.ManifestValue>>:
        _closed : Unit <- File.close(file)
        read.host(error)
    case (file, Done{bytes}):
      do IO<Result<&1, &1, Error, Manifest.ManifestValue>>:
        _closed : Unit <- File.close(file)
        read.result(Manifest.decode(bytes))

def read.sized(file: File, size: Nat) -> IO(Result<&1, &1, Error, Manifest.ManifestValue>):
  match size:
    case 56n:
      do IO<Result<&1, &1, Error, Manifest.ManifestValue>>:
        pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_at(file, 0, 56)
        read.decoded(pair)
    case 63n:
      do IO<Result<&1, &1, Error, Manifest.ManifestValue>>:
        pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_at(file, 0, 63)
        read.decoded(pair)
    case 60n:
      do IO<Result<&1, &1, Error, Manifest.ManifestValue>>:
        pair : File & Result<&1, &1, U32 & String, Bytes.Bytes> <- Fs.read_at(file, 0, 60)
        read.decoded(pair)
    case _:
      do IO<Result<&1, &1, Error, Manifest.ManifestValue>>:
        _closed : Unit <- File.close(file)
        read.result(Fail{Manifest.Malformed{}})

def read.size.result(
  file: File,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Result<&1, &1, Error, Manifest.ManifestValue>):
  match result:
    case Done{size}: read.sized(file, size)
    case Fail{error}:
      do IO<Result<&1, &1, Error, Manifest.ManifestValue>>:
        _closed : Unit <- File.close(file)
        read.host(error)

def read.path.opened(
  path: String,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, Error, Manifest.ManifestValue>):
  match opened:
    case Fail{error}:
      read.host(error)
    case Done{file}:
      do IO<Result<&1, &1, Error, Manifest.ManifestValue>>:
        size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path)
        read.size.result(file, size)

# Reads and validates one bounded generation-four or generation-five manifest.
def read(
  +path: String
) -> IO(Result<&1, &1, Error, Manifest.ManifestValue>):
  do IO<Result<&1, &1, Error, Manifest.ManifestValue>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read.path.opened(path, opened)

def write.directory.synced(
  directory: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}: Fs.fsync(directory)

def write.renamed(
  +directory: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        renamed : Result<&1, &1, U32 & String, Unit> <- Fs.rename(directory ++ "/MANIFEST.tmp", directory ++ "/MANIFEST")
        write.directory.synced(directory, renamed)

def write.closed(
  +directory: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{Unit{}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(directory ++ "/MANIFEST.tmp")
        write.renamed(directory, synced)

def write.file.synced(
  directory: String,
  result: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match result:
    case (file, result):
      do IO<Result<&1, &1, U32 & String, Unit>>:
        _closed : Unit <- File.close(file)
        write.closed(directory, result)

def write.bytes(
  directory: String,
  bytes: Bytes.Bytes,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{error}: IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{error})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        result : File & Result<&1, &1, U32 & String, Unit> <- Fs.write_bytes(file, bytes)
        write.file.synced(directory, result)

# Publishes a manifest through a synced temporary and atomic rename.
def write_atomic(
  +directory: String,
  value: Manifest.ManifestValue
) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(directory ++ "/MANIFEST.tmp", "w")
    write.bytes(directory, Manifest.encode(value), opened)
