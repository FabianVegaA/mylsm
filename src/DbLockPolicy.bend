import Base
import ./DurableError.bend as DurableError

# Describes the pure outcome of one bounded lock-wait decision.
type WaitDecision is Data:
  LockAcquired{}
  LockRetry{sleep_ms: Nat}
  LockTimedOut{}
  LockFatal{}

# Recognizes the host errno values for lock contention.
def busy_code(+code: U32) -> Bool:
  U32.is_eq(code, 11) || U32.is_eq(code, 35)

# Recognizes the host errno for a missing path.
def missing_code(+code: U32) -> Bool:
  U32.is_eq(code, 2)

# Recognizes unavailable lock or FFI primitives on supported POSIX hosts.
def unsupported_code(+code: U32) -> Bool:
  U32.is_eq(code, 45) || U32.is_eq(code, 78) ||
    U32.is_eq(code, 95) || U32.is_eq(code, 38)

# Maps non-contention lock errors to NotFound or Io.
def classify_nonbusy_lock_error(
  missing: Bool,
  code: U32,
  message: String,
  operation: String,
  path: String,
) -> DurableError.Error:
  match missing:
    case True{}:
      DurableError.Error{DurableError.NotFound{}, operation, path, code, message}
    case False{}:
      DurableError.Error{DurableError.Io{}, operation, path, code, message}

def classify_lock.nonbusy.platform(
  unsupported: Bool,
  missing: Bool,
  code: U32,
  message: String,
  operation: String,
  path: String
) -> DurableError.Error:
  match unsupported:
    case True{}:
      DurableError.Error{DurableError.UnsupportedPlatform{}, operation,
        path, code, message}
    case False{}:
      classify_nonbusy_lock_error(missing, code, message, operation, path)

# Classifies non-contention lock failures before preserving host details.
def classify_lock_nonbusy(
  unsupported: Bool,
  missing: Bool,
  code: U32,
  message: String,
  operation: String,
  path: String
) -> DurableError.Error:
  classify_lock.nonbusy.platform(unsupported, missing, code, message,
    operation, path)

# Maps contention to Busy and retains host details.
def classify_lock_busy(busy: Bool, +code: U32, message: String, operation: String, path: String) -> DurableError.Error:
  match busy:
    case True{}:
      DurableError.Error{DurableError.Busy{}, operation, path, code, message}
    case False{}:
      classify_lock_nonbusy(unsupported_code(code), missing_code(code),
        code, message, operation, path)

# Maps lock errors using the pure platform policy.
def classify_lock_error(+code: U32, message: String, operation: String, path: String) -> DurableError.Error:
  classify_lock_busy(busy_code(code), code, message, operation, path)

# Chooses a bounded sleep or timeout after a contended lock attempt.
def busy_wait.remaining(remaining_ms: Nat, backoff_ms: Nat) -> WaitDecision:
  match remaining_ms:
    case 0n:
      LockTimedOut{}
    case 1n+rest:
      LockRetry{Nat.min(backoff_ms, Nat.add(1n, rest))}

# Chooses a bounded sleep or timeout after a contended lock attempt.
def busy_wait_decision(elapsed_ms: Nat, timeout_ms: Nat, backoff_ms: Nat) -> WaitDecision:
  busy_wait.remaining(Nat.sub(timeout_ms, elapsed_ms), backoff_ms)

# Selects acquired, retry, timeout, or fatal handling from raw lock facts.
def wait_decision(
  acquired: Bool,
  busy: Bool,
  elapsed_ms: Nat,
  timeout_ms: Nat,
  backoff_ms: Nat
) -> WaitDecision:
  Bool.pick(WaitDecision, acquired, LockAcquired{},
    Bool.pick(WaitDecision, busy,
      busy_wait_decision(elapsed_ms, timeout_ms, backoff_ms),
      LockFatal{}))

# Bounds the public timeout and nonzero backoff before any host effect.
def wait_options_valid(timeout_ms: U32, +backoff_ms: U32) -> Bool:
  U32.is_le(timeout_ms, 60000) && U32.is_lt(0, backoff_ms) && U32.is_le(backoff_ms, 1000)
