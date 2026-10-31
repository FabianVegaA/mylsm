import Base
import ../../ByteDurableDb.bend as ByteDb
import ../../ResourceOptions.bend as ResourceOptions
import ../Protocol.bend as Protocol
import ../CoordinatorPolicy.bend as Policy
import ../OwnerSnapshotStore.bend as SnapshotStore
import ../OwnerCursorStore.bend as CursorStore
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries the state for ReplyContext.
type ReplyContext is Type:
  ReplyContext{version: U32 & U32,
    generation: U32 & U32, request_id: U32 & U32,
    options: ResourceOptions.Options}

# Carries the durable handle and owner resources through one completed request.
type DispatchResult is Type:
  DispatchResult{handle: ByteDb.Handle, snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, response: Protocol.Response}

def reply.options.pair(
  context: ReplyContext
) -> ReplyContext & ResourceOptions.Options:
  match context:
    case ReplyContext{versions, generations, request_ids, +options}:
      (ReplyContext{versions, generations, request_ids, options}, options)

def reply.response(
  context: ReplyContext,
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes
) -> Protocol.Response:
  match context:
    case ReplyContext{versions, generations, request_ids, _}:
      match versions:
        case (version, _):
          match generations:
            case (generation, _):
              match request_ids:
                case (request_id, _):
                  Protocol.Response{version, generation, request_id, status,
                    payload}

def error.kind(error: ByteDb.Error) -> Policy.FailureKind:
  match error:
    case ByteDb.Busy{}: Policy.BusyFailure{}
    case ByteDb.Timeout{}: Policy.TimeoutFailure{}
    case ByteDb.NotFound{}: Policy.NotFoundFailure{}
    case ByteDb.AlreadyExists{}: Policy.AlreadyExistsFailure{}
    case ByteDb.InvalidArgument{}: Policy.InvalidArgumentFailure{}
    case ByteDb.UnsupportedPlatform{}: Policy.UnsupportedPlatformFailure{}
    case ByteDb.ResourceLimit{}: Policy.ResourceLimitFailure{}
    case ByteDb.Corruption{_}: Policy.CorruptionFailure{}
    case ByteDb.Io{_, _}: Policy.IoFailure{}
    case ByteDb.CommitUnknown{_, _}: Policy.CommitUnknownFailure{}

def reply.status(status: Policy.ReplyStatus) -> Protocol.ResponseStatus:
  match status:
    case Policy.SuccessStatus{}: Protocol.Success{}
    case Policy.InvalidArgumentStatus{}: Protocol.InvalidArgument{}
    case Policy.AlreadyExistsStatus{}: Protocol.AlreadyExists{}
    case Policy.UnsupportedPlatformStatus{}: Protocol.UnsupportedPlatform{}
    case Policy.NotFoundStatus{}: Protocol.NotFound{}
    case Policy.BusyStatus{}: Protocol.Busy{}
    case Policy.TimeoutStatus{}: Protocol.Timeout{}
    case Policy.ResourceLimitStatus{}: Protocol.ResponseResourceLimit{}
    case Policy.CorruptionStatus{}: Protocol.Corruption{}
    case Policy.IoStatus{}: Protocol.IoFailure{}
    case Policy.CommitUnknownStatus{}: Protocol.CommitUnknown{}

def error.status(error: ByteDb.Error) -> Protocol.ResponseStatus:
  reply.status(Policy.failure.status(error.kind(error)))

def dispatch.result(
  pair: ByteDb.Handle & Protocol.Response,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> DispatchResult:
  match pair:
    case (handle, response): DispatchResult{handle, snapshots, cursors, response}
