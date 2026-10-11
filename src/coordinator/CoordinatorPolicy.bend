import Base

# Represents the owner lifecycle around lock, recovery, endpoint, and shutdown.
type State is Data:
  Starting{}
  Locked{}
  Recovered{}
  Serving{}
  Stopping{}
  EndpointRemoved{}
  Closed{}
  Failed{}

# Represents one external result or requested lifecycle action.
type OwnerEvent is Data:
  AcquireLock{}
  RecoveryComplete{}
  PublishEndpoint{}
  BeginShutdown{}
  RemoveEndpoint{}
  ReleaseLock{}
  Failure{}

# Returns the next legal state or rejects an out-of-order event.
type Decision is Data:
  Advance{state: State}
  Reject{}

# Classifies durable failures before mapping them into wire statuses.
type FailureKind is Data:
  BusyFailure{}
  TimeoutFailure{}
  NotFoundFailure{}
  InvalidArgumentFailure{}
  AlreadyExistsFailure{}
  UnsupportedPlatformFailure{}
  ResourceLimitFailure{}
  CorruptionFailure{}
  IoFailure{}
  CommitUnknownFailure{}

# Defines the typed response statuses available to coordinator clients.
type ReplyStatus is Data:
  SuccessStatus{}
  InvalidArgumentStatus{}
  AlreadyExistsStatus{}
  UnsupportedPlatformStatus{}
  NotFoundStatus{}
  BusyStatus{}
  TimeoutStatus{}
  ResourceLimitStatus{}
  CorruptionStatus{}
  IoStatus{}
  CommitUnknownStatus{}

# Records whether the open path acquired, contended on, or failed to acquire the lock.
type LockOutcome is Data:
  LockAcquired{}
  LockBusy{}
  LockFailed{}

# Records whether canonical endpoint inspection found a live candidate.
type EndpointOutcome is Data:
  EndpointPresent{}
  EndpointMissing{}
  EndpointFailed{}

# Selects local ownership, remote use, or a typed open failure.
type OpenRole is Data:
  LocalOwner{}
  ExistingOwnerClient{}
  ReturnBusy{}
  PropagateOpenFailure{}

# Chooses local ownership or an established endpoint from lock observations.
def open.role(lock: LockOutcome, endpoint: EndpointOutcome) -> OpenRole:
  match lock:
    case LockAcquired{}: LocalOwner{}
    case LockBusy{}:
      match endpoint:
        case EndpointPresent{}: ExistingOwnerClient{}
        case EndpointMissing{}: ReturnBusy{}
        case EndpointFailed{}: PropagateOpenFailure{}
    case LockFailed{}: PropagateOpenFailure{}

def failure.status(kind: FailureKind) -> ReplyStatus:
  match kind:
    case BusyFailure{}: BusyStatus{}
    case TimeoutFailure{}: TimeoutStatus{}
    case NotFoundFailure{}: NotFoundStatus{}
    case InvalidArgumentFailure{}: InvalidArgumentStatus{}
    case AlreadyExistsFailure{}: AlreadyExistsStatus{}
    case UnsupportedPlatformFailure{}: UnsupportedPlatformStatus{}
    case ResourceLimitFailure{}: ResourceLimitStatus{}
    case CorruptionFailure{}: CorruptionStatus{}
    case IoFailure{}: IoStatus{}
    case CommitUnknownFailure{}: CommitUnknownStatus{}

# Applies one lifecycle event without performing host effects.
def step(state: State, event: OwnerEvent) -> Decision:
  match state:
    case Starting{}:
      match event:
        case AcquireLock{}: Advance{Locked{}}
        case Failure{}: Advance{Failed{}}
        case _: Reject{}
    case Locked{}:
      match event:
        case RecoveryComplete{}: Advance{Recovered{}}
        case Failure{}: Advance{Failed{}}
        case _: Reject{}
    case Recovered{}:
      match event:
        case PublishEndpoint{}: Advance{Serving{}}
        case Failure{}: Advance{Failed{}}
        case _: Reject{}
    case Serving{}:
      match event:
        case BeginShutdown{}: Advance{Stopping{}}
        case Failure{}: Advance{Failed{}}
        case _: Reject{}
    case Stopping{}:
      match event:
        case RemoveEndpoint{}: Advance{EndpointRemoved{}}
        case Failure{}: Advance{Failed{}}
        case _: Reject{}
    case EndpointRemoved{}:
      match event:
        case ReleaseLock{}: Advance{Closed{}}
        case Failure{}: Advance{Failed{}}
        case _: Reject{}
    case Closed{}: Reject{}
    case Failed{}: Reject{}
