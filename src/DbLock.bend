import Base
import ./DurableError.bend as DurableError
import ./DbLockPolicy.bend as Policy

# Owns the open LOCK file until release.
type Lock is Type:
  Lock{file: File}

# Builds the stable LOCK path for a database directory.
def lock_path(path: String) -> String:
  path ++ "/LOCK"

def DbLock.try_lock(file: File) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  import "./effs/db_lock.c"
  import "./effs/db_lock.js"

def DbLock.try_unlock(file: File) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  import "./effs/db_unlock.c"
  import "./effs/db_unlock.js"

# Classifies a failure to open the LOCK file.
def open_failed(error: U32 & String, operation: String, path: String) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match error:
    case (code, message):
      IO.pure(Result<&1, &1, DurableError.Error, Lock>,
        Fail{Policy.classify_lock_error(code, message, operation, path)})

# Closes the file and classifies a failed lock attempt.
def lock_failed(
  file: File,
  error: U32 & String,
  operation: String,
  path: String
) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match error:
    case (code, message):
      do IO<Result<&1, &1, DurableError.Error, Lock>>:
        _closed : Unit <- File.close(file)
        return Fail{Policy.classify_lock_error(code, message, operation, path)}

# Returns an owned lock on success or closes the failed handle.
def lock_result(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  operation: String,
  path: String
) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match pair:
    case (file, Fail{error}):
      lock_failed(file, error, operation, path)
    case (file, Done{Unit{}}):
      IO.pure(Result<&1, &1, DurableError.Error, Lock>, Done{Lock{file}})

# Attempts the nonblocking OS lock on the open file.
def lock_file(file: File, operation: String, path: String) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  do IO<Result<&1, &1, DurableError.Error, Lock>>:
    pair : File & Result<&1, &1, U32 & String, Unit> <- DbLock.try_lock(file)
    lock_result(pair, operation, path)

# Locks the opened file or classifies its open error.
def opened(
  result: Result<&1, &1, U32 & String, File>,
  operation: String,
  path: String
) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match result:
    case Fail{error}:
      open_failed(error, operation, path)
    case Done{file}:
      lock_file(file, operation, path)

# Opens the stable LOCK file and acquires its OS lock.
def acquire(+path: String, operation: String) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  do IO<Result<&1, &1, DurableError.Error, Lock>>:
    result : Result<&1, &1, U32 & String, File> <- File.open(lock_path(path), "a")
    opened(result, operation, path)

# Closes the file and preserves the unlock error.
def release_failed(
  file: File,
  error: U32 & String,
  operation: String,
  path: String
) -> IO(Result<&1, &1, DurableError.Error, Unit>):
  match error:
    case (code, message):
      do IO<Result<&1, &1, DurableError.Error, Unit>>:
        _closed : Unit <- File.close(file)
        return Fail{DurableError.classify_open(DurableError.OpenHostFailure{code, message}, operation, path)}

# Closes the file after a successful unlock.
def release_succeeded(file: File) -> IO(Result<&1, &1, DurableError.Error, Unit>):
  do IO<Result<&1, &1, DurableError.Error, Unit>>:
    _closed : Unit <- File.close(file)
    return Done{Unit{}}

# Closes the file after either unlock result.
def released(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  operation: String,
  path: String
) -> IO(Result<&1, &1, DurableError.Error, Unit>):
  match pair:
    case (file, Fail{error}):
      release_failed(file, error, operation, path)
    case (file, Done{Unit{}}):
      release_succeeded(file)

# Unlocks the file and closes it after the result.
def unlock_file(file: File, operation: String, path: String) -> IO(Result<&1, &1, DurableError.Error, Unit>):
  do IO<Result<&1, &1, DurableError.Error, Unit>>:
    pair : File & Result<&1, &1, U32 & String, Unit> <- DbLock.try_unlock(file)
    released(pair, operation, path)

# Consumes the lock and releases its file handle.
def release(lock: Lock, operation: String, path: String) -> IO(Result<&1, &1, DurableError.Error, Unit>):
  match lock:
    case Lock{file}:
      unlock_file(file, operation, path)
