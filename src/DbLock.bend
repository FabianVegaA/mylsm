import Base
import ./DurableError.bend as DurableError
import ./DbLockPolicy.bend as Policy
import ./Fs.bend as Fs

# Owns the open LOCK file until release.
type Lock is Type:
  Lock{file: File}

# Determines whether a clock sample selects backoff or deadline validation.
type WaitPurpose is Data:
  ChooseDelay{}
  CheckDeadline{}

# Carries the raw result of one nonblocking lock attempt.
type AttemptDecision is Type:
  Contended{}
  Failed{error: U32 & String}

# Carries file ownership through the single recursive wait state machine.
type WaitState is Type:
  TryLock{file: File, started_ns: Nat, timeout_ms: Nat, backoff_ms: U32,
    operation: String, path: String}
  LockAttempt{pair: File & Result<&1, &1, U32 & String, Unit>,
    started_ns: Nat, timeout_ms: Nat, backoff_ms: U32, operation: String, path: String}
  ReadClock{file: File, started_ns: Nat, timeout_ms: Nat, backoff_ms: U32,
    operation: String, path: String, purpose: WaitPurpose}
  ClockSample{file: File, started_ns: Nat, timeout_ms: Nat, backoff_ms: U32,
    operation: String, path: String, purpose: WaitPurpose,
    result: Result<&1, &1, U32 & String, Nat>}
  Pause{file: File, started_ns: Nat, timeout_ms: Nat, backoff_ms: U32,
    operation: String, path: String, duration_ms: U32}
  PauseResult{file: File, started_ns: Nat, timeout_ms: Nat, backoff_ms: U32,
    operation: String, path: String,
    result: Result<&1, &1, U32 & String, Unit>}
  WaitFatal{file: File, error: U32 & String, operation: String, path: String}
  WaitExpired{file: File, operation: String, path: String}


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

# Closes the lock file and returns a distinct timeout error.
def wait.timeout(file: File, operation: String, path: String) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  do IO<Result<&1, &1, DurableError.Error, Lock>>:
    _closed : Unit <- File.close(file)
    return Fail{DurableError.Error{DurableError.Timeout{}, operation, path, 0,
      "lock acquisition timed out"}}

# Closes the lock file and classifies a clock or sleep host failure.
def wait.host_error(
  file: File,
  error: U32 & String,
  operation: String,
  path: String
) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match error:
    case (code, message):
      do IO<Result<&1, &1, DurableError.Error, Lock>>:
        _closed : Unit <- File.close(file)
        return Fail{DurableError.classify_open(
          DurableError.OpenHostFailure{code, message}, operation, path)}

# Separates contention from fatal lock errors while preserving host details.
def wait.attempt.decision(error: U32 & String) -> AttemptDecision:
  match error:
    case (+code, message):
      Bool.pick(AttemptDecision, Policy.busy_code(code),
        Contended{}, Failed{(code, message)})

# Converts a raw lock failure into the next owned state.
def wait.attempt.state(
  decision: AttemptDecision,
  file: File,
  started_ns: Nat,
  timeout_ms: Nat,
  backoff_ms: U32,
  operation: String,
  path: String
) -> WaitState:
  match decision:
    case Contended{}:
      ReadClock{file, started_ns, timeout_ms, backoff_ms,
        operation, path, ChooseDelay{}}
    case Failed{error}:
      WaitFatal{file, error, operation, path}

# Converts backoff policy into either one sleep or a terminal state.
def wait.delay.state(
  decision: Policy.WaitDecision,
  file: File,
  started_ns: Nat,
  timeout_ms: Nat,
  backoff_ms: U32,
  operation: String,
  path: String
) -> WaitState:
  match decision:
    case Policy.LockRetry{sleep_ms}:
      Pause{file, started_ns, timeout_ms, backoff_ms, operation, path,
        U32.from_nat(sleep_ms)}
    case _:
      WaitExpired{file, operation, path}

# Converts a post-sleep deadline sample into a retry or timeout state.
def wait.deadline.state(
  remaining_ms: Nat,
  file: File,
  started_ns: Nat,
  timeout_ms: Nat,
  backoff_ms: U32,
  operation: String,
  path: String
) -> WaitState:
  match remaining_ms:
    case 0n:
      WaitExpired{file, operation, path}
    case 1n+_:
      TryLock{file, started_ns, timeout_ms, backoff_ms, operation, path}

# Selects backoff or deadline logic from a monotonic elapsed-time sample.
def wait.clock.decision(
  purpose: WaitPurpose,
  file: File,
  started_ns: Nat,
  +timeout_ms: Nat,
  +backoff_ms: U32,
  operation: String,
  path: String,
  elapsed_ms: Nat
) -> WaitState:
  match purpose:
    case ChooseDelay{}:
      wait.delay.state(Policy.busy_wait_decision(elapsed_ms, timeout_ms,
        U32.to_nat(backoff_ms)), file, started_ns, timeout_ms, backoff_ms,
        operation, path)
    case CheckDeadline{}:
      wait.deadline.state(Nat.sub(timeout_ms, elapsed_ms), file, started_ns,
        timeout_ms, backoff_ms, operation, path)

# Closes a handle if the finite retry budget is unexpectedly exhausted.
def wait.exhausted(state: WaitState) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match state:
    case TryLock{file, _, _, _, operation, path}:
      wait.timeout(file, operation, path)
    case LockAttempt{pair, _, _, _, operation, path}:
      match pair:
        case (file, _):
          wait.timeout(file, operation, path)
    case ReadClock{file, _, _, _, operation, path, _}:
      wait.timeout(file, operation, path)
    case ClockSample{file, _, _, _, operation, path, _, _}:
      wait.timeout(file, operation, path)
    case Pause{file, _, _, _, operation, path, _}:
      wait.timeout(file, operation, path)
    case PauseResult{file, _, _, _, operation, path, _}:
      wait.timeout(file, operation, path)
    case WaitFatal{file, _, operation, path}:
      wait.timeout(file, operation, path)
    case WaitExpired{file, operation, path}:
      wait.timeout(file, operation, path)

# Runs lock, clock, and sleep transitions with one decreasing structural fuel.
def wait.loop(fuel: Nat, state: WaitState) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match fuel:
    case 0n:
      wait.exhausted(state)
    case 1n+rest:
      match state:
        case TryLock{file, started_ns, timeout_ms, backoff_ms, operation, path}:
          do IO<Result<&1, &1, DurableError.Error, Lock>>:
            pair : File & Result<&1, &1, U32 & String, Unit> <- DbLock.try_lock(file)
            wait.loop(rest, LockAttempt{pair, started_ns, timeout_ms,
              backoff_ms, operation, path})
        case LockAttempt{pair, started_ns, timeout_ms, backoff_ms, operation, path}:
          match pair:
            case (file, Done{Unit{}}):
              IO.pure(Result<&1, &1, DurableError.Error, Lock>, Done{Lock{file}})
            case (file, Fail{error}):
              wait.loop(rest, wait.attempt.state(wait.attempt.decision(error),
                file, started_ns, timeout_ms, backoff_ms, operation, path))
        case ReadClock{file, started_ns, timeout_ms, backoff_ms, operation, path, purpose}:
          do IO<Result<&1, &1, DurableError.Error, Lock>>:
            result : Result<&1, &1, U32 & String, Nat> <- Fs.clock_monotonic()
            wait.loop(rest, ClockSample{file, started_ns, timeout_ms,
              backoff_ms, operation, path, purpose, result})
        case ClockSample{file, +started_ns, +timeout_ms, +backoff_ms,
            operation, path, purpose, result}:
          match result:
            case Fail{error}:
              wait.host_error(file, error, operation, path)
            case Done{now_ns}:
              +elapsed_ns = Nat.sub(now_ns, started_ns)
              +elapsed_ms = Nat.div(elapsed_ns, 1000000n)
              wait.loop(rest, wait.clock.decision(purpose, file, started_ns,
                timeout_ms, backoff_ms, operation, path, elapsed_ms))
        case Pause{file, started_ns, timeout_ms, backoff_ms, operation, path, duration_ms}:
          do IO<Result<&1, &1, DurableError.Error, Lock>>:
            result : Result<&1, &1, U32 & String, Unit> <- Fs.sleep_ms(duration_ms)
            wait.loop(rest, PauseResult{file, started_ns, timeout_ms,
              backoff_ms, operation, path, result})
        case PauseResult{file, started_ns, timeout_ms, backoff_ms, operation, path, result}:
          match result:
            case Fail{error}:
              wait.host_error(file, error, operation, path)
            case Done{Unit{}}:
              wait.loop(rest, ReadClock{file, started_ns, timeout_ms,
                backoff_ms, operation, path, CheckDeadline{}})
        case WaitFatal{file, error, operation, path}:
          lock_failed(file, error, operation, path)
        case WaitExpired{file, operation, path}:
          wait.timeout(file, operation, path)

# Begins retries after validating the monotonic clock source.
def acquire_wait.started(
  file: File,
  operation: String,
  path: String,
  timeout_ms: U32,
  backoff_ms: U32,
  result: Result<&1, &1, U32 & String, Nat>
) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match result:
    case Fail{error}:
      wait.host_error(file, error, operation, path)
    case Done{started_ns}:
      +timeout = U32.to_nat(timeout_ms)
      fuel = Nat.add(Nat.mul(timeout, 8n), 8n)
      wait.loop(fuel, TryLock{file, started_ns, timeout, backoff_ms,
        operation, path})

# Opens the stable lock file and samples the monotonic start time.
def acquire_wait.opened(
  result: Result<&1, &1, U32 & String, File>,
  operation: String,
  path: String,
  timeout_ms: U32,
  backoff_ms: U32
) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match result:
    case Fail{error}:
      open_failed(error, operation, path)
    case Done{file}:
      do IO<Result<&1, &1, DurableError.Error, Lock>>:
        started : Result<&1, &1, U32 & String, Nat> <- Fs.clock_monotonic()
        acquire_wait.started(file, operation, path, timeout_ms, backoff_ms, started)

# Opens and waits only after the pure option validation succeeds.
def acquire_wait.valid(
  valid: Bool,
  +path: String,
  operation: String,
  +timeout_ms: U32,
  +backoff_ms: U32
) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  match valid:
    case False{}:
      IO.pure(Result<&1, &1, DurableError.Error, Lock>,
        Fail{DurableError.classify_open(DurableError.InvalidInput{}, operation, path)})
    case True{}:
      do IO<Result<&1, &1, DurableError.Error, Lock>>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(lock_path(path), "a")
        acquire_wait.opened(opened, operation, path, timeout_ms, backoff_ms)

# Acquires the lock immediately or waits with a finite monotonic timeout.
def acquire_wait(
  +path: String,
  operation: String,
  +timeout_ms: U32,
  +backoff_ms: U32
) -> IO(Result<&1, &1, DurableError.Error, Lock>):
  acquire_wait.valid(Policy.wait_options_valid(timeout_ms, backoff_ms),
    path, operation, timeout_ms, backoff_ms)
