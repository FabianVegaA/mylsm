import Base
import ./DurableError.bend as DurableError

# Recognizes the host errno values for lock contention.
def busy_code(+code: U32) -> Bool:
  U32.is_eq(code, 11) || U32.is_eq(code, 35)

# Recognizes the host errno for a missing path.
def missing_code(+code: U32) -> Bool:
  U32.is_eq(code, 2)

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

# Maps contention to Busy and retains host details.
def classify_lock_busy(busy: Bool, +code: U32, message: String, operation: String, path: String) -> DurableError.Error:
  match busy:
    case True{}:
      DurableError.Error{DurableError.Busy{}, operation, path, code, message}
    case False{}:
      classify_nonbusy_lock_error(missing_code(code), code, message, operation, path)

# Maps lock errors using the pure platform policy.
def classify_lock_error(+code: U32, message: String, operation: String, path: String) -> DurableError.Error:
  classify_lock_busy(busy_code(code), code, message, operation, path)
