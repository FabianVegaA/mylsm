import Base
import ../DbLock.bend as DbLock
import ../DurableError.bend as DurableError
import ../Fs.bend as Fs
import ../StorageBytes.bend as StorageBytes
import ./FormatInspect.bend as FormatInspect
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Separates lock ownership failures from read-only filesystem failures.
type Error is Data:
  Lock{error: DurableError.Error}
  Host{code: U32, message: String}
  ResourceLimit{}

def identity.unknown() -> FormatInspect.Identity:
  FormatInspect.Identity{"unknown", "unknown", 0}

def inspection.resource_limit() -> FormatInspect.Inspection:
  FormatInspect.Inspection{identity.unknown(), FormatInspect.ResourceLimit{}}

def read.failed.released(
  error: U32 & String,
  result: Result<&1, &1, DurableError.Error, Unit>
) -> Result<&1, &1, Error, FormatInspect.Inspection>:
  match error:
    case (code, message):
      match result:
        case Fail{lock_error}: Fail{Lock{lock_error}}
        case Done{Unit{}}: Fail{Host{code, message}}

def read.success.released(
  bytes: Bytes.Bytes,
  result: Result<&1, &1, DurableError.Error, Unit>
) -> Result<&1, &1, Error, FormatInspect.Inspection>:
  match result:
    case Fail{error}: Fail{Lock{error}}
    case Done{Unit{}}:
      Done{FormatInspect.inspect_manifest_bytes(bytes)}

def read.result(
  +path: String,
  lock: DbLock.Lock,
  file_result: File & Result<&1, &1, U32 & String, Bytes.Bytes>
) -> IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  match file_result:
    case (file, Fail{error}):
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        _closed : Unit <- File.close(file)
        released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "inspect", path)
        return read.failed.released(error, released)
    case (file, Done{bytes}):
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        _closed : Unit <- File.close(file)
        released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "inspect", path)
        return read.success.released(bytes, released)

def read.opened(
  +path: String,
  lock: DbLock.Lock,
  size: Nat,
  opened: Result<&1, &1, U32 & String, File>
) -> IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  match opened:
    case Fail{error}:
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "inspect", path)
        return read.failed.released(error, released)
    case Done{file}:
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        result : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, 0, U32.from_nat(size))
        read.result(path, lock, result)

def read.limit.released(
  result: Result<&1, &1, DurableError.Error, Unit>
) -> IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, FormatInspect.Inspection>, Fail{Lock{error}})
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, Error, FormatInspect.Inspection>,
        Done{inspection.resource_limit()})

def read.size.checked(
  +path: String,
  lock: DbLock.Lock,
  +size: Nat,
  within_limit: Bool
) -> IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  match within_limit:
    case True{}:
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        opened : Result<&1, &1, U32 & String, File> <-
          File.open(path ++ "/MANIFEST", "r")
        read.opened(path, lock, size, opened)
    case False{}:
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "inspect", path)
        read.limit.released(released)

def read.size(
  +path: String,
  lock: DbLock.Lock,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  match result:
    case Fail{error}:
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "inspect", path)
        return read.failed.released(error, released)
    case Done{+size}:
      read.size.checked(path, lock, size,
        Nat.is_le(size, U32.to_nat(StorageBytes.MAX_MANIFEST_BYTES())))

def inspect.locked(
  +path: String,
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>
) -> IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, FormatInspect.Inspection>, Fail{Lock{error}})
    case Done{lock}:
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/MANIFEST")
        read.size(path, lock, size)

def inspect.lock.error(
  error: U32 & String
) -> IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  match error:
    case (code, message):
      IO.pure(Result<&1, &1, Error, FormatInspect.Inspection>,
        Fail{Host{code, message}})

def inspect.lock.present(
  +path: String,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  match result:
    case Fail{error}:
      inspect.lock.error(error)
    case Done{False{}}:
      IO.pure(Result<&1, &1, Error, FormatInspect.Inspection>,
        Fail{Host{2, "database LOCK file is missing"}})
    case Done{True{}}:
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        acquired : Result<&1, &1, DurableError.Error, DbLock.Lock> <-
          DbLock.acquire(path, "inspect")
        inspect.locked(path, acquired)

def inspect.canonical(
  result: Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  match result:
    case Fail{error}:
      match error:
        case (code, message):
          IO.pure(Result<&1, &1, Error, FormatInspect.Inspection>,
            Fail{Host{code, message}})
    case Done{+path}:
      do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path ++ "/LOCK")
        inspect.lock.present(path, exists)

# Reads and validates a database manifest under an existing exclusive lock.
def inspect(
  +path: String
) ->
  IO(Result<&1, &1, Error, FormatInspect.Inspection>):
  do IO<Result<&1, &1, Error, FormatInspect.Inspection>>:
    canonical : Result<&1, &1, U32 & String, String> <- Fs.canonical_path(path)
    inspect.canonical(canonical)
