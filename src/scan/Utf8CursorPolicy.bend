import Base

# Keeps the terminal cursor failure independent from owned error details.
type Failure is Data:
  TextDecodeFailure{}
  ReaderFailure{}
  ResourceFailure{}
  ArgumentFailure{}

# Classifies each failure without losing its public category.
type FailureClass is Data:
  TextFailure{}
  StorageFailure{}
  ResourceLimitFailure{}
  InvalidArgumentFailure{}

# Retains the terminal failure category across repeated cursor reads.
def classify(failure: Failure) -> FailureClass:
  match failure:
    case TextDecodeFailure{}: TextFailure{}
    case ReaderFailure{}: StorageFailure{}
    case ResourceFailure{}: ResourceLimitFailure{}
    case ArgumentFailure{}: InvalidArgumentFailure{}

# Produces a stored cursor state and an output classification.
def duplicate(failure: Failure) -> Failure & Failure:
  match failure:
    case TextDecodeFailure{}: (TextDecodeFailure{}, TextDecodeFailure{})
    case ReaderFailure{}: (ReaderFailure{}, ReaderFailure{})
    case ResourceFailure{}: (ResourceFailure{}, ResourceFailure{})
    case ArgumentFailure{}: (ArgumentFailure{}, ArgumentFailure{})
