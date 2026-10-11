import Base
import ../ByteDurableDb.bend as ByteDb
import ../StorageBytes.bend as StorageBytes
import ./Operation.bend as Operation
import ./Protocol.bend as Protocol
import ./CoordinatorPolicy.bend as Policy
import ./OwnerGeneration.bend as Generation
import ./Io.bend as Io
import ./UnixSocketIo.bend as UnixSocket
import ./OwnerSnapshotStore.bend as SnapshotStore
import ./OwnerCursorStore.bend as CursorStore
import ../scan/VisibleCursor.bend as VisibleCursor
import ../scan/RangeCursor.bend as RangeCursor
import ../ByteMemTable.bend as ByteMemTable
import ./CursorCodec.bend as CursorCodec
import ../Fs.bend as Fs
import ../CrashPoint.bend as CrashPoint
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Retains request identifiers while the owner prepares a response.
type ReplyContext is Type:
  ReplyContext{version: U32 & U32,
    generation: U32 & U32, request_id: U32 & U32}

# Carries the durable handle and owner resources through one completed request.
type DispatchResult is Type:
  DispatchResult{handle: ByteDb.Handle, snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, response: Protocol.Response}

# Owns the listening socket, durable handle, endpoint, and lifecycle state.
type ServiceState is Type:
  Serving{server: File, handle: ByteDb.Handle, endpoint: String,
    generation: U32, snapshots: SnapshotStore.Store, cursors: CursorStore.Store}
  Stopping{server: File, handle: ByteDb.Handle, endpoint: String,
    reason: String, cursors: CursorStore.Store}

# Carries one bounded owner-cursor read across visible-source steps.
type CursorReadState is Type:
  CursorReadNeed{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, context: ReplyContext, cursor_id: U32,
    release_id: U32, cursor: VisibleCursor.Cursor}
  CursorReadStep{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, context: ReplyContext, cursor_id: U32,
    release_id: U32, step: VisibleCursor.Step}

def reply.response(
  context: ReplyContext,
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes
) -> Protocol.Response:
  match context:
    case ReplyContext{versions, generations, request_ids}:
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

def write.response(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>,
  context: ReplyContext
) -> IO(ByteDb.Handle & Protocol.Response):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<ByteDb.Handle & Protocol.Response>:
        _after_apply : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("owner.after_apply")
        _before_response : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("owner.before_response")
        _checkpoint : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("owner.after_mutation.before_response")
        return (handle, reply.response(context, Protocol.Success{}, Bytes.new(0)))
    case (handle, Fail{error}):
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, error.status(error), Bytes.new(0))))

def get.response(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>,
  context: ReplyContext
) -> ByteDb.Handle & Protocol.Response:
  match pair:
    case (handle, Fail{error}):
      (handle, reply.response(context, error.status(error), Bytes.new(0)))
    case (handle, Done{None{}}):
      (handle, reply.response(context, Protocol.NotFound{}, Bytes.new(0)))
    case (handle, Done{Some{value}}):
      (handle, reply.response(context, Protocol.Success{}, value))

def stats.response.encoded(
  handle: ByteDb.Handle,
  context: ReplyContext,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> ByteDb.Handle & Protocol.Response:
  match result:
    case Done{payload}:
      (handle, reply.response(context, Protocol.Success{}, payload))
    case Fail{_}:
      (handle, reply.response(context, Protocol.ResponseResourceLimit{},
        Bytes.new(0)))

def stats.response(
  handle: ByteDb.Handle,
  stats: ByteDb.Stats,
  context: ReplyContext
) -> ByteDb.Handle & Protocol.Response:
  match stats:
    case ByteDb.Stats{entries, payload_bytes}:
      stats.response.encoded(handle, context,
        StorageBytes.from_string(Nat.show(entries) ++ ":" ++
          Nat.show(payload_bytes)))

def dispatch.stats(
  pair: ByteDb.Handle & ByteDb.Stats,
  context: ReplyContext
) -> IO(ByteDb.Handle & Protocol.Response):
  match pair:
    case (handle, snapshot):
      IO.pure(ByteDb.Handle & Protocol.Response,
        stats.response(handle, snapshot, context))

def dispatch.result(
  pair: ByteDb.Handle & Protocol.Response,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> DispatchResult:
  match pair:
    case (handle, response): DispatchResult{handle, snapshots, cursors, response}

def snapshot.generation(value: Maybe<&1, U32>) -> Nat:
  match value:
    case None{}: 0n
    case Some{generation}: U32.to_nat(generation)

def snapshot.open.result(
  handle: ByteDb.Handle,
  context: ReplyContext,
  cursors: CursorStore.Store,
  result: SnapshotStore.OpenResult
) -> DispatchResult:
  match result:
    case SnapshotStore.RootStored{store, snapshot_id}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Success{},
          Protocol.snapshot.id.bytes(snapshot_id))}
    case SnapshotStore.RootRejected{store}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))}

def snapshot.open.root.copies(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  cursors: CursorStore.Store,
  roots: ByteDb.SnapshotRoot & ByteDb.SnapshotRoot
) -> DispatchResult:
  match roots:
    case (generation_root, retained_root):
      match generation_root:
        case ByteDb.SnapshotRoot{_, sst_generation, _, _}:
          snapshot.open.result(handle, context, cursors,
            SnapshotStore.open.root(snapshots, retained_root,
              snapshot.generation(sst_generation), (64n, 67108864n)))

def snapshot.open.captured(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, ByteDb.SnapshotRoot>,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  cursors: CursorStore.Store
) -> DispatchResult:
  match pair:
    case (handle, Fail{error}):
      dispatch.result((handle, reply.response(context, error.status(error),
        Bytes.new(0))), snapshots, cursors)
    case (handle, Done{root}):
      snapshot.open.root.copies(handle, snapshots, context, cursors,
        ByteDb.snapshot.root.clone(root))

def snapshot.open(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  cursors: CursorStore.Store
) -> IO(DispatchResult):
  do IO<DispatchResult>:
    captured : ByteDb.Handle &
      Result<&1, &1, ByteDb.Error, ByteDb.SnapshotRoot> <-
        ByteDb.snapshot_root_limited(67108864n, handle)
    return snapshot.open.captured(captured, snapshots, context, cursors)

def snapshot.get.result(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  result: Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>
) -> DispatchResult:
  match result:
    case Fail{error}:
      DispatchResult{handle, snapshots, cursors,
        reply.response(context, error.status(error), Bytes.new(0))}
    case Done{None{}}:
      DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.NotFound{}, Bytes.new(0))}
    case Done{Some{value}}:
      DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.Success{}, value)}

def snapshot.get.lookup(
  handle: ByteDb.Handle,
  context: ReplyContext,
  cursors: CursorStore.Store,
  key: Bytes.Bytes,
  lookup: SnapshotStore.LookupResult
) -> IO(DispatchResult):
  match lookup:
    case SnapshotStore.RootFound{store, root}:
      do IO<DispatchResult>:
        result : Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>> <-
          ByteDb.snapshot.root.get(root, key)
        return snapshot.get.result(handle, store, cursors, context, result)
    case SnapshotStore.RootMissing{store}:
      IO.pure(DispatchResult, DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.get(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshot_id: U32,
  key: Bytes.Bytes
) -> IO(DispatchResult):
  snapshot.get.lookup(handle, context, cursors, key,
    SnapshotStore.lookup.root(snapshots, snapshot_id))

# Maps a close decision to success, Busy, or an unknown-token response.
def snapshot.close.result(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  result: SnapshotStore.CloseResult
) -> DispatchResult:
  match result:
    case SnapshotStore.RootClosed{store}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Success{}, Bytes.new(0))}
    case SnapshotStore.RootCloseBusy{store}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Busy{}, Bytes.new(0))}
    case SnapshotStore.RootCloseMissing{store}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))}

# Closes one owner snapshot token through the aggregate retention registry.
def snapshot.close(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshot_id: U32
) -> IO(DispatchResult):
  IO.pure(DispatchResult, snapshot.close.result(handle, cursors, context,
    SnapshotStore.close(snapshots, snapshot_id)))

def snapshot.cursor.open.register(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_ids: U32 & U32 & U32,
  cursor: VisibleCursor.Cursor
) -> IO(DispatchResult):
  match cursor_ids:
    case (store_id, (response_id, _)):
      IO.pure(DispatchResult, DispatchResult{handle, snapshots,
        CursorStore.insert(cursors, store_id, cursor),
        reply.response(context, Protocol.Success{},
          Protocol.snapshot.id.bytes(response_id))})

def snapshot.cursor.open.failed(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  error: ByteDb.Error,
  released: SnapshotStore.CursorCloseResult
) -> DispatchResult:
  match released:
    case SnapshotStore.CursorReleased{updated, _}:
      DispatchResult{handle, updated, cursors,
        reply.response(context, error.status(error), Bytes.new(0))}
    case SnapshotStore.CursorReleaseRejected{updated}:
      DispatchResult{handle, updated, cursors,
        reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.opened(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32,
  opened: Result<&1, &1, ByteDb.Error, VisibleCursor.Cursor>
) -> IO(DispatchResult):
  match opened:
    case Fail{error}:
      IO.pure(DispatchResult, snapshot.cursor.open.failed(handle, cursors,
        context, error,
        SnapshotStore.cursor.close(snapshots, cursor_id)))
    case Done{cursor}:
      snapshot.cursor.open.register(handle, snapshots, cursors, context,
        Protocol.u32.duplicate.triple(cursor_id), cursor)

def snapshot.cursor.open.admitted(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  root: ByteDb.SnapshotRoot,
  bounds: RangeCursor.Bounds,
  decision: SnapshotStore.CursorOpenResult
) -> IO(DispatchResult):
  match decision:
    case SnapshotStore.CursorRejected{store}:
      IO.pure(DispatchResult, DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})
    case SnapshotStore.CursorStored{store, cursor_id}:
      do IO<DispatchResult>:
        opened : Result<&1, &1, ByteDb.Error, VisibleCursor.Cursor> <-
          ByteDb.snapshot.root.cursor.open(root, bounds)
        dispatched : DispatchResult <-
          snapshot.cursor.opened(handle, store, cursors, context, cursor_id,
            opened)
        return dispatched

def snapshot.cursor.open.lookup(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshot_id: U32,
  bounds: RangeCursor.Bounds,
  lookup: SnapshotStore.LookupResult
) -> IO(DispatchResult):
  match lookup:
    case SnapshotStore.RootFound{store, root}:
      snapshot.cursor.open.admitted(handle, cursors, context, root, bounds,
        SnapshotStore.cursor.open(store, snapshot_id, 64n))
    case SnapshotStore.RootMissing{store}:
      IO.pure(DispatchResult, DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.cursor.open.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  bounds: RangeCursor.Bounds,
  ids: U32 & U32 & U32
) -> IO(DispatchResult):
  match ids:
    case (lookup_id, (retained_id, _)):
      snapshot.cursor.open.lookup(handle, cursors, context, retained_id, bounds,
        SnapshotStore.lookup.root(snapshots, lookup_id))

def snapshot.cursor.open(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  snapshot_id: U32,
  bounds: RangeCursor.Bounds
) -> IO(DispatchResult):
  snapshot.cursor.open.ids(handle, snapshots, cursors, context, bounds,
    Protocol.u32.duplicate.triple(snapshot_id))

def snapshot.cursor.next.response(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  frame: CursorCodec.Frame
) -> DispatchResult:
  DispatchResult{handle, snapshots, cursors,
    reply.response(context, Protocol.Success{}, CursorCodec.encode(frame))}

def snapshot.cursor.next.item(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32,
  key: Bytes.Bytes,
  value: Bytes.Bytes,
  cursor: VisibleCursor.Cursor
) -> DispatchResult:
  snapshot.cursor.next.response(handle, snapshots,
    CursorStore.reinsert(cursors, cursor_id, cursor), context,
    CursorCodec.CursorItem{key, value})

def snapshot.cursor.next.terminal(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  released: SnapshotStore.CursorCloseResult,
  frame: CursorCodec.Frame
) -> DispatchResult:
  match released:
    case SnapshotStore.CursorReleased{store, _}:
      snapshot.cursor.next.response(handle, store, cursors, context, frame)
    case SnapshotStore.CursorReleaseRejected{store}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.next.terminal.error(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  released: SnapshotStore.CursorCloseResult
) -> DispatchResult:
  match released:
    case SnapshotStore.CursorReleased{store, _}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.IoFailure{}, Bytes.new(0))}
    case SnapshotStore.CursorReleaseRejected{store}:
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.next.loop(
  fuel: Nat,
  state: CursorReadState
) -> IO(DispatchResult):
  match fuel:
    case 0n:
      match state:
        case CursorReadNeed{handle, snapshots, cursors, context, cursor_id,
            _, cursor}:
          IO.pure(DispatchResult, DispatchResult{handle, snapshots,
            CursorStore.reinsert(cursors, cursor_id, cursor),
            reply.response(context, Protocol.ResponseResourceLimit{},
              Bytes.new(0))})
        case CursorReadStep{handle, snapshots, cursors, context, cursor_id,
            release_id, step}:
          match step:
            case VisibleCursor.Item{entry, cursor}:
              match entry:
                case ByteMemTable.Entry{key, value}:
                  match value:
                    case Some{bytes}:
                      IO.pure(DispatchResult, snapshot.cursor.next.item(handle,
                        snapshots, cursors, context, cursor_id, key, bytes,
                        cursor))
                    case None{}:
                      IO.pure(DispatchResult, DispatchResult{handle, snapshots,
                        CursorStore.reinsert(cursors, cursor_id, cursor),
                        reply.response(context, Protocol.ResponseResourceLimit{},
                          Bytes.new(0))})
            case VisibleCursor.Skip{cursor}:
              IO.pure(DispatchResult, DispatchResult{handle, snapshots,
                CursorStore.reinsert(cursors, cursor_id, cursor),
                reply.response(context, Protocol.ResponseResourceLimit{},
                  Bytes.new(0))})
            case VisibleCursor.End{}:
              IO.pure(DispatchResult, snapshot.cursor.next.terminal(handle,
                cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id),
                CursorCodec.CursorEnd{}))
            case VisibleCursor.Error{_}:
              IO.pure(DispatchResult, snapshot.cursor.next.terminal.error(
                handle, cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id)))
    case 1n+rest:
      match state:
        case CursorReadNeed{handle, snapshots, cursors, context, cursor_id,
            release_id, cursor}:
          do IO<DispatchResult>:
            step : VisibleCursor.Step <- VisibleCursor.next(cursor)
            snapshot.cursor.next.loop(rest, CursorReadStep{handle, snapshots,
              cursors, context, cursor_id, release_id, step})
        case CursorReadStep{handle, snapshots, cursors, context, cursor_id,
            release_id, step}:
          match step:
            case VisibleCursor.Item{entry, cursor}:
              match entry:
                case ByteMemTable.Entry{key, value}:
                  match value:
                    case Some{bytes}:
                      IO.pure(DispatchResult, snapshot.cursor.next.item(handle,
                        snapshots, cursors, context, cursor_id, key, bytes,
                        cursor))
                    case None{}:
                      snapshot.cursor.next.loop(rest, CursorReadNeed{handle,
                        snapshots, cursors, context, cursor_id, release_id,
                        cursor})
            case VisibleCursor.Skip{cursor}:
              snapshot.cursor.next.loop(rest, CursorReadNeed{handle, snapshots,
                cursors, context, cursor_id, release_id, cursor})
            case VisibleCursor.End{}:
              IO.pure(DispatchResult, snapshot.cursor.next.terminal(handle,
                cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id),
                CursorCodec.CursorEnd{}))
            case VisibleCursor.Error{_}:
              IO.pure(DispatchResult, snapshot.cursor.next.terminal.error(
                handle, cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id)))

def snapshot.cursor.next.taken(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  ids: U32 & U32,
  result: CursorStore.TakeResult
) -> IO(DispatchResult):
  match ids:
    case (cursor_id, release_id):
      match result:
        case CursorStore.Taken{store, cursor}:
          snapshot.cursor.next.loop(4096n, CursorReadNeed{handle, snapshots,
            store, context, cursor_id, release_id, cursor})
        case CursorStore.NotFound{store}:
          IO.pure(DispatchResult, DispatchResult{handle, snapshots, store,
            reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.cursor.next.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  ids: U32 & U32 & U32
) -> IO(DispatchResult):
  match ids:
    case (take_id, (cursor_id, release_id)):
      snapshot.cursor.next.taken(handle, snapshots, context,
        (cursor_id, release_id), CursorStore.take(cursors, take_id))

def snapshot.cursor.next(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32
) -> IO(DispatchResult):
  snapshot.cursor.next.ids(handle, snapshots, cursors, context,
    Protocol.u32.duplicate.triple(cursor_id))

def snapshot.cursor.close.success(
  closed: Result<&1, &1, U32 & String, Unit>
) -> Bool:
  match closed:
    case Done{Unit{}}: True{}
    case Fail{_}: False{}

def snapshot.cursor.close.result(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: ReplyContext,
  outcome: Bool & SnapshotStore.CursorCloseResult
) -> DispatchResult:
  match outcome:
    case (True{}, SnapshotStore.CursorReleased{store, _}):
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Success{}, Bytes.new(0))}
    case (False{}, SnapshotStore.CursorReleased{store, _}):
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.IoFailure{}, Bytes.new(0))}
    case (_, SnapshotStore.CursorReleaseRejected{store}):
      DispatchResult{handle, store, cursors,
        reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.close.closed(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32,
  closed: Result<&1, &1, U32 & String, Unit>
) -> IO(DispatchResult):
  IO.pure(DispatchResult, snapshot.cursor.close.result(handle, cursors,
    context, (snapshot.cursor.close.success(closed),
      SnapshotStore.cursor.close(snapshots, cursor_id))))

def snapshot.cursor.close.taken(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: ReplyContext,
  cursor_id: U32,
  result: CursorStore.TakeResult
) -> IO(DispatchResult):
  match result:
    case CursorStore.Taken{store, cursor}:
      do IO<DispatchResult>:
        closed : Result<&1, &1, U32 & String, Unit> <-
          VisibleCursor.close(cursor)
        result : DispatchResult <- snapshot.cursor.close.closed(handle,
          snapshots, store, context, cursor_id, closed)
        return result
    case CursorStore.NotFound{store}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, store,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.cursor.close.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  ids: U32 & U32 & U32
) -> IO(DispatchResult):
  match ids:
    case (take_id, (release_id, _)):
      snapshot.cursor.close.taken(handle, snapshots, context,
        release_id, CursorStore.take(cursors, take_id))

def snapshot.cursor.close(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  cursor_id: U32
) -> IO(DispatchResult):
  snapshot.cursor.close.ids(handle, snapshots, cursors, context,
    Protocol.u32.duplicate.triple(cursor_id))

def dispatch.operation(
  handle: ByteDb.Handle,
  context: ReplyContext,
  operation: Operation.Operation
) -> IO(ByteDb.Handle & Protocol.Response):
  match operation:
    case Operation.Get{key}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error,
          Maybe<&1, Bytes.Bytes>> <- ByteDb.get(handle, key)
        return get.response(pair, context)
    case Operation.Put{key, value}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.put(handle, key, value)
        write.response(pair, context)
    case Operation.Delete{key}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.delete(handle, key)
        write.response(pair, context)
    case Operation.WriteBatch{mutations}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.write_batch(handle, mutations)
        write.response(pair, context)
    case Operation.Flush{}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.flush(handle)
        write.response(pair, context)
    case Operation.Compact{}:
      do IO<ByteDb.Handle & Protocol.Response>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.compact(handle)
        write.response(pair, context)
    case Operation.Stats{}:
      dispatch.stats(ByteDb.stats(handle), context)
    case Operation.SnapshotOpen{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotGet{_, _}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotClose{_}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorOpen{_, _}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorNext{_}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorClose{_}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))

def dispatch.decoded.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  decision: Operation.Decision
) -> IO(DispatchResult):
  match decision:
    case Operation.Decoded{Operation.SnapshotOpen{}}:
      snapshot.open(handle, snapshots, context, cursors)
    case Operation.Decoded{Operation.SnapshotGet{snapshot_id, key}}:
      snapshot.get(handle, snapshots, cursors, context, snapshot_id, key)
    case Operation.Decoded{Operation.SnapshotClose{snapshot_id}}:
      snapshot.close(handle, snapshots, cursors, context, snapshot_id)
    case Operation.Decoded{Operation.SnapshotCursorOpen{snapshot_id, bounds}}:
      snapshot.cursor.open(handle, snapshots, cursors, context, snapshot_id,
        bounds)
    case Operation.Decoded{Operation.SnapshotCursorNext{cursor_id}}:
      snapshot.cursor.next(handle, snapshots, cursors, context, cursor_id)
    case Operation.Decoded{Operation.SnapshotCursorClose{cursor_id}}:
      snapshot.cursor.close(handle, snapshots, cursors, context, cursor_id)
    case Operation.Decoded{operation}:
      do IO<DispatchResult>:
        pair : ByteDb.Handle & Protocol.Response <-
          dispatch.operation(handle, context, operation)
        return dispatch.result(pair, snapshots, cursors)
    case Operation.MalformedArguments{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Operation.UnsupportedOperation{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def dispatch.decoded(
  handle: ByteDb.Handle,
  context: ReplyContext,
  decision: Operation.Decision
) -> IO(ByteDb.Handle & Protocol.Response):
  match decision:
    case Operation.Decoded{operation}:
      dispatch.operation(handle, context, operation)
    case Operation.MalformedArguments{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{},
          Bytes.new(0))))
    case Operation.UnsupportedOperation{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{},
          Bytes.new(0))))

def dispatch.validated(
  handle: ByteDb.Handle,
  context: ReplyContext,
  decision: Protocol.Decision
) -> IO(ByteDb.Handle & Protocol.Response):
  match decision:
    case Protocol.Accepted{_, operation_code, payload}:
      dispatch.decoded(handle, context,
        Operation.decode.payload(operation_code, payload))
    case Protocol.VersionMismatch{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Protocol.StaleGeneration{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Protocol.UnsupportedRequestOperation{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Protocol.ResourceLimit{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))))

def dispatch.validated.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: ReplyContext,
  decision: Protocol.Decision
) -> IO(DispatchResult):
  match decision:
    case Protocol.Accepted{_, operation_code, payload}:
      dispatch.decoded.state(handle, snapshots, cursors, context,
        Operation.decode.payload(operation_code, payload))
    case Protocol.VersionMismatch{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Protocol.StaleGeneration{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Protocol.UnsupportedRequestOperation{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Protocol.ResourceLimit{}:
      IO.pure(DispatchResult, DispatchResult{handle, snapshots, cursors,
        reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})

def dispatch.request.copies(
  handle: ByteDb.Handle,
  versions: U32 & U32 & U32,
  generations: U32 & U32 & U32,
  request_ids: U32 & U32 & U32,
  operation_code: U32,
  payload: Bytes.Bytes,
  active_generations: U32 & U32
) -> IO(ByteDb.Handle & Protocol.Response):
  match versions:
    case (version, (response_version, response_version_hold)):
      match generations:
        case (generation, (_, response_generation_hold)):
          match request_ids:
            case (request_id, (response_id, response_id_hold)):
              match active_generations:
                case (response_generation, active_generation):
                  dispatch.validated(handle,
                    ReplyContext{(response_version, response_version_hold),
                      (Generation.response.generation(response_generation),
                        response_generation_hold),
                      (response_id, response_id_hold)},
                    Protocol.validate(
                      Protocol.Request{version, generation, request_id,
                        operation_code, payload},
                      1, active_generation, Protocol.max_payload_bytes()))

def dispatch.request.copies.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  versions: U32 & U32 & U32,
  generations: U32 & U32 & U32,
  request_ids: U32 & U32 & U32,
  operation_code: U32,
  payload: Bytes.Bytes,
  active_generations: U32 & U32
) -> IO(DispatchResult):
  match versions:
    case (version, (response_version, response_version_hold)):
      match generations:
        case (generation, (_, response_generation_hold)):
          match request_ids:
            case (request_id, (response_id, response_id_hold)):
              match active_generations:
                case (response_generation, active_generation):
                  dispatch.validated.state(handle, snapshots, cursors,
                    ReplyContext{(response_version, response_version_hold),
                      (Generation.response.generation(response_generation),
                        response_generation_hold),
                      (response_id, response_id_hold)},
                    Protocol.validate(
                      Protocol.Request{version, generation, request_id,
                        operation_code, payload},
                      1, active_generation, Protocol.max_payload_bytes()))

def u32.duplicate.pair.from(triple: U32 & U32 & U32) -> U32 & U32:
  match triple:
    case (first, (second, _)): (first, second)

def u32.duplicate.pair(value: U32) -> U32 & U32:
  u32.duplicate.pair.from(Protocol.u32.duplicate.triple(value))

def dispatch.request(
  handle: ByteDb.Handle,
  request: Protocol.Request,
  active_generation: U32
) -> IO(ByteDb.Handle & Protocol.Response):
  match request:
    case Protocol.Request{version, generation, request_id, operation_code, payload}:
      dispatch.request.copies(handle,
        Protocol.u32.duplicate.triple(version),
        Protocol.u32.duplicate.triple(generation),
        Protocol.u32.duplicate.triple(request_id), operation_code, payload,
        u32.duplicate.pair(active_generation))

def dispatch.request.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  active_generation: U32
) -> IO(DispatchResult):
  match request:
    case Protocol.Request{version, generation, request_id, operation_code, payload}:
      dispatch.request.copies.state(handle, snapshots, cursors,
        Protocol.u32.duplicate.triple(version),
        Protocol.u32.duplicate.triple(generation),
        Protocol.u32.duplicate.triple(request_id), operation_code, payload,
        u32.duplicate.pair(active_generation))

def serve.closed(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> IO(ByteDb.Handle & SnapshotStore.Store & CursorStore.Store):
  match pair:
    case (connection, _):
      do IO<ByteDb.Handle & SnapshotStore.Store & CursorStore.Store>:
        _closed : Unit <- File.close(connection)
        return (handle, snapshots, cursors)

def serve.response(
  connection: File,
  result: DispatchResult
) -> IO(ByteDb.Handle & SnapshotStore.Store & CursorStore.Store):
  match result:
    case DispatchResult{handle, snapshots, cursors, response}:
      do IO<ByteDb.Handle & SnapshotStore.Store & CursorStore.Store>:
        written : File & Result<&1, &1, U32 & String, Unit> <-
          Io.write_all(connection, Protocol.encode_response(response))
        serve.closed(written, handle, snapshots, cursors)

def serve.request.result(
  pair: File & Result<&1, &1, Io.Error, Protocol.Request>,
  handle: ByteDb.Handle,
  active_generation: U32,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> IO(ByteDb.Handle & SnapshotStore.Store & CursorStore.Store):
  match pair:
    case (connection, Fail{_}):
      do IO<ByteDb.Handle & SnapshotStore.Store & CursorStore.Store>:
        _closed : Unit <- File.close(connection)
        return (handle, snapshots, cursors)
    case (connection, Done{request}):
      do IO<ByteDb.Handle & SnapshotStore.Store & CursorStore.Store>:
        dispatched : DispatchResult <-
          dispatch.request.state(handle, snapshots, cursors, request,
            active_generation)
        serve.response(connection, dispatched)

def serve.once(
  handle: ByteDb.Handle,
  connection: File,
  active_generation: U32,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> IO(ByteDb.Handle & SnapshotStore.Store & CursorStore.Store):
  do IO<ByteDb.Handle & SnapshotStore.Store & CursorStore.Store>:
    request : File & Result<&1, &1, Io.Error, Protocol.Request> <-
      Io.read_request(connection)
    serve.request.result(request, handle, active_generation, snapshots, cursors)

def serve.accepted.updated(
  server: File,
  endpoint: String,
  generation: U32,
  updated: ByteDb.Handle & SnapshotStore.Store & CursorStore.Store
) -> ServiceState:
  match updated:
    case (handle, (snapshots, cursors)):
      Serving{server, handle, endpoint, generation, snapshots, cursors}

def serve.accepted.connection(
  server: File,
  connection: File,
  handle: ByteDb.Handle,
  endpoint: String,
  generations: U32 & U32 & U32,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> IO(ServiceState):
  match generations:
    case (request_generation, (state_generation, _)):
      do IO<ServiceState>:
        updated : ByteDb.Handle & SnapshotStore.Store & CursorStore.Store <-
          serve.once(handle, connection, request_generation, snapshots, cursors)
        return serve.accepted.updated(server, endpoint, state_generation,
          updated)

def serve.accepted(
  pair: File & Result<&1, &1, UnixSocket.Error, File>,
  handle: ByteDb.Handle,
  endpoint: String,
  generation: U32,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> IO(ServiceState):
  match pair:
    case (server, Done{connection}):
      serve.accepted.connection(server, connection, handle, endpoint,
        Protocol.u32.duplicate.triple(generation), snapshots, cursors)
    case (server, Fail{UnixSocket.UnsupportedPlatform{}}):
      IO.pure(ServiceState, Stopping{server, handle, endpoint,
        "socket accept is unsupported on this platform", cursors})
    case (server, Fail{UnixSocket.Host{code, _}}):
      IO.pure(ServiceState, Stopping{server, handle, endpoint,
        "socket accept failed with host code " ++ Nat.show(U32.to_nat(code)),
        cursors})

def serve.stop.result(
  removed: Result<&1, &1, U32 & String, Unit>,
  closed: Result<&1, &1, ByteDb.Error, Unit>,
  reason: String
) -> IO(Unit):
  match removed closed reason:
    case Done{Unit{}} Done{Unit{}} "owner request budget exhausted":
      IO.print("OWNER_STOPPED")
    case Done{Unit{}} Done{Unit{}} _:
      IO.die(Unit, 1, reason)
    case Fail{(code, message)} Done{Unit{}} _:
      IO.die(Unit, code, "owner endpoint removal failed: " ++ message)
    case Done{Unit{}} Fail{_} _:
      IO.die(Unit, 1, "owner database lock release failed")
    case Fail{(code, message)} Fail{_} _:
      IO.die(Unit, code, "owner endpoint removal failed: " ++ message)

def serve.stop(
  server: File,
  handle: ByteDb.Handle,
  endpoint: String,
  reason: String,
  cursors: CursorStore.Store
) -> IO(Unit):
  do IO<Unit>:
    _cursors_closed : Unit <- CursorStore.close.all(cursors)
    _server_closed : Unit <- File.close(server)
    removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
    closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    serve.stop.result(removed, closed, reason)

def serve.loop(fuel: Nat, state: ServiceState) -> IO(Unit):
  match fuel:
    case 0n:
      match state:
        case Serving{server, handle, endpoint, _, _, cursors}:
          serve.stop(server, handle, endpoint,
            "owner request budget exhausted", cursors)
        case Stopping{server, handle, endpoint, reason, cursors}:
          serve.stop(server, handle, endpoint, reason, cursors)
    case 1n+rest:
      match state:
        case Serving{server, handle, endpoint, generation, snapshots, cursors}:
          do IO<Unit>:
            accepted : File & Result<&1, &1, UnixSocket.Error, File> <-
              UnixSocket.accept(server)
            next : ServiceState <- serve.accepted(accepted, handle, endpoint,
              generation, snapshots, cursors)
            serve.loop(rest, next)
        case Stopping{server, handle, endpoint, reason, cursors}:
          serve.stop(server, handle, endpoint, reason, cursors)
