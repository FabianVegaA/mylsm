import Base
import ./Manifest.bend as Manifest

# Lists the structured durable error categories.
type ErrorKind is Data:
  NotFound{}
  AlreadyExists{}
  Busy{}
  InvalidArgument{}
  UnsupportedFormat{}
  Corruption{}
  ResourceLimit{}
  Io{}
  CommitUnknown{}

# Carries operation, path, and host details with its category.
type Error is Data:
  Error{kind: ErrorKind, operation: String, path: String, host_code: U32, host_message: String}

# Records the failure that ended a database open.
type OpenCause is Data:
  MissingPath{}
  ExistingPath{}
  Locked{}
  InvalidInput{}
  UnknownFormat{}
  CorruptData{}
  LimitReached{}
  OpenHostFailure{code: U32, message: String}

# Identifies whether a write failed before or after append.
type WritePhase is Data:
  BeforeAppend{}
  AppendStarted{}

# Records the codec or host failure behind a write result.
type WriteCause is Data:
  ValidationFailure{}
  WriteLimitReached{}
  WriteHostFailure{code: U32, message: String}

# Builds an error with its structured host and operation details.
def error(kind: ErrorKind, operation: String, path: String, code: U32, message: String) -> Error:
  Error{kind, operation, path, code, message}

# Maps open causes to their public error categories.
def classify_open(cause: OpenCause, operation: String, path: String) -> Error:
  match cause:
    case MissingPath{}:
      error(NotFound{}, operation, path, 0, "")
    case ExistingPath{}:
      error(AlreadyExists{}, operation, path, 0, "")
    case Locked{}:
      error(Busy{}, operation, path, 0, "")
    case InvalidInput{}:
      error(InvalidArgument{}, operation, path, 0, "")
    case UnknownFormat{}:
      error(UnsupportedFormat{}, operation, path, 0, "")
    case CorruptData{}:
      error(Corruption{}, operation, path, 0, "")
    case LimitReached{}:
      error(ResourceLimit{}, operation, path, 0, "")
    case OpenHostFailure{code, message}:
      error(Io{}, operation, path, code, message)

def classify_recovery.limit(+code: U32, +message: String, +operation: String, +path: String) -> Error:
  Bool.pick(Error, U32.is_eq(code, Manifest.parse_limit_error_code()),
    error(ResourceLimit{}, operation, path, 0, "manifest size limit exceeded"),
    classify_open(OpenHostFailure{code, message}, operation, path))

def classify_recovery.corruption(+code: U32, +message: String, +operation: String, +path: String) -> Error:
  Bool.pick(Error, U32.is_eq(code, Manifest.malformed_error_code()),
    error(Corruption{}, operation, path, 0, "malformed manifest"),
    classify_recovery.limit(code, message, operation, path))

def classify_recovery.sst(+code: U32, +message: String, +operation: String, +path: String) -> Error:
  Bool.pick(Error, U32.is_eq(code, 4294967292),
    error(Corruption{}, operation, path, 0, "malformed SST"),
    classify_recovery.corruption(code, message, operation, path))

def classify_recovery.levels(+code: U32, +message: String, +operation: String, +path: String) -> Error:
  Bool.pick(Error, U32.is_eq(code, 5),
    error(Corruption{}, operation, path, 0, "invalid manifest names"),
    classify_recovery.sst(code, message, operation, path))

def classify_recovery.wal(+code: U32, +message: String, +operation: String, +path: String) -> Error:
  Bool.pick(Error, U32.is_eq(code, 4294967290),
    error(Corruption{}, operation, path, 0, "malformed WAL"),
    classify_recovery.levels(code, message, operation, path))

# Maps recovery failures to typed public errors.
def classify_recovery(+code: U32, +message: String, +operation: String, +path: String) -> Error:
  Bool.pick(Error, U32.is_eq(code, Manifest.unsupported_version_error_code()),
    error(UnsupportedFormat{}, operation, path, 0, "unsupported manifest version"),
    classify_recovery.wal(code, message, operation, path))

# Classifies failures that occur before WAL append begins.
def classify_write_before(cause: WriteCause, operation: String, path: String) -> Error:
  match cause:
    case ValidationFailure{}:
      error(InvalidArgument{}, operation, path, 0, "")
    case WriteLimitReached{}:
      error(ResourceLimit{}, operation, path, 0, "")
    case WriteHostFailure{code, message}:
      error(Io{}, operation, path, code, message)

# Classifies failures after append begins as CommitUnknown.
def classify_write_after(cause: WriteCause, operation: String, path: String) -> Error:
  match cause:
    case ValidationFailure{}:
      error(InvalidArgument{}, operation, path, 0, "")
    case WriteLimitReached{}:
      error(ResourceLimit{}, operation, path, 0, "")
    case WriteHostFailure{code, message}:
      error(CommitUnknown{}, operation, path, code, message)

# Selects the write error category from its append stage.
def classify_write(phase: WritePhase, cause: WriteCause, operation: String, path: String) -> Error:
  match phase:
    case BeforeAppend{}:
      classify_write_before(cause, operation, path)
    case AppendStarted{}:
      classify_write_after(cause, operation, path)
