import Base
import ./Reply.bend as Reply
import ./Snapshots.bend as Snapshots
import ../../ByteDurableDb.bend as ByteDb
import ../../StorageBytes.bend as StorageBytes
import ../../ResourceOptions.bend as ResourceOptions
import ../Operation.bend as Operation
import ../OptionsCodec.bend as OptionsCodec
import ../Protocol.bend as Protocol
import ../OwnerGeneration.bend as Generation
import ../OwnerSnapshotStore.bend as SnapshotStore
import ../OwnerCursorStore.bend as CursorStore
import ../../CrashPoint.bend as CrashPoint
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def write.response(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit>,
  context: Reply.ReplyContext
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
        return (handle, Reply.reply.response(context, Protocol.Success{}, Bytes.new(0)))
    case (handle, Fail{error}):
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Reply.error.status(error), Bytes.new(0))))

def get.response(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>,
  context: Reply.ReplyContext
) -> ByteDb.Handle & Protocol.Response:
  match pair:
    case (handle, Fail{error}):
      (handle, Reply.reply.response(context, Reply.error.status(error), Bytes.new(0)))
    case (handle, Done{None{}}):
      (handle, Reply.reply.response(context, Protocol.NotFound{}, Bytes.new(0)))
    case (handle, Done{Some{value}}):
      (handle, Reply.reply.response(context, Protocol.Success{}, value))

def stats.response.encoded(
  handle: ByteDb.Handle,
  context: Reply.ReplyContext,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>
) -> ByteDb.Handle & Protocol.Response:
  match result:
    case Done{payload}:
      (handle, Reply.reply.response(context, Protocol.Success{}, payload))
    case Fail{_}:
      (handle, Reply.reply.response(context, Protocol.ResponseResourceLimit{},
        Bytes.new(0)))

def stats.response(
  handle: ByteDb.Handle,
  stats: ByteDb.Stats,
  context: Reply.ReplyContext
) -> ByteDb.Handle & Protocol.Response:
  match stats:
    case ByteDb.Stats{entries, payload_bytes}:
      stats.response.encoded(handle, context,
        StorageBytes.from_string(Nat.show(entries) ++ ":" ++
          Nat.show(payload_bytes) ++ ":0:0:0"))

def stats.response.owner.result(
  pair: ByteDb.Handle & Protocol.Response,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store
) -> Reply.DispatchResult:
  match pair:
    case (handle, response): Reply.DispatchResult{handle, snapshots, cursors, response}

def stats.response.owner.metrics(
  handle: ByteDb.Handle,
  context: Reply.ReplyContext,
  entries: Nat,
  payload_bytes: Nat,
  snapshot_metrics: SnapshotStore.Metrics,
  cursor_metrics: CursorStore.Metrics
) -> Reply.DispatchResult:
  match snapshot_metrics:
    case SnapshotStore.Metrics{snapshots, retained_bytes, snapshot_store}:
      match cursor_metrics:
        case CursorStore.Metrics{cursors, cursor_store}:
          stats.response.owner.result(
            stats.response.encoded(handle, context,
              StorageBytes.from_string(Nat.show(entries) ++ ":" ++
                Nat.show(payload_bytes) ++ ":" ++ Nat.show(snapshots) ++
                ":" ++ Nat.show(retained_bytes) ++ ":" ++ Nat.show(cursors))),
            snapshot_store, cursor_store)

def stats.response.owner(
  pair: ByteDb.Handle & ByteDb.Stats,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext
) -> Reply.DispatchResult:
  match pair:
    case (handle, stats):
      match stats:
        case ByteDb.Stats{entries, payload_bytes}:
          stats.response.owner.metrics(handle, context, entries, payload_bytes,
            SnapshotStore.metrics(snapshots), CursorStore.metrics(cursors))

def dispatch.stats.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext
) -> IO(Reply.DispatchResult):
  IO.pure(Reply.DispatchResult,
    stats.response.owner(ByteDb.stats(handle), snapshots, cursors, context))

def dispatch.stats(
  pair: ByteDb.Handle & ByteDb.Stats,
  context: Reply.ReplyContext
) -> IO(ByteDb.Handle & Protocol.Response):
  match pair:
    case (handle, snapshot):
      IO.pure(ByteDb.Handle & Protocol.Response,
        stats.response(handle, snapshot, context))

def compact.preflight.result(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  decision: Bool & SnapshotStore.Store
) -> IO(Reply.DispatchResult):
  match decision:
    case (False{}, snapshots):
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})
    case (True{}, snapshots):
      do IO<Reply.DispatchResult>:
        pair : ByteDb.Handle & Result<&1, &1, ByteDb.Error, Unit> <-
          ByteDb.compact(handle)
        response : ByteDb.Handle & Protocol.Response <-
          write.response(pair, context)
        return Reply.dispatch.result(response, snapshots, cursors)

def compact.preflight.options(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  options: ResourceOptions.Options
) -> IO(Reply.DispatchResult):
  compact.preflight.result(handle, cursors, context,
    SnapshotStore.retired_files.can_compact(snapshots,
      ResourceOptions.reader.retired.files(options)))

def compact.preflight.options.pair(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  pair: Reply.ReplyContext & ResourceOptions.Options
) -> IO(Reply.DispatchResult):
  match pair:
    case (context, options):
      compact.preflight.options(handle, snapshots, cursors, context, options)

def compact.preflight(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext
) -> IO(Reply.DispatchResult):
  compact.preflight.options.pair(handle, snapshots, cursors,
    Reply.reply.options.pair(context))

def dispatch.describe.owner(
  context_options: Reply.ReplyContext & ResourceOptions.Options,
  handle: ByteDb.Handle
) -> ByteDb.Handle & Protocol.Response:
  match context_options:
    case (context, options):
      (handle, Reply.reply.response(context, Protocol.Success{},
        OptionsCodec.encode(options)))

def dispatch.operation(
  handle: ByteDb.Handle,
  context: Reply.ReplyContext,
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
    case Operation.DescribeOwner{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        dispatch.describe.owner(Reply.reply.options.pair(context), handle))
    case Operation.SnapshotOpen{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotGet{_, _}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotClose{_}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorOpen{_, _}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorNext{_}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorClose{_}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Operation.SnapshotCursorSeek{_, _}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))

def dispatch.decoded.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  decision: Operation.Decision
) -> IO(Reply.DispatchResult):
  match decision:
    case Operation.Decoded{Operation.Stats{}}:
      dispatch.stats.state(handle, snapshots, cursors, context)
    case Operation.Decoded{Operation.SnapshotOpen{}}:
      Snapshots.snapshot.open(handle, snapshots, context, cursors)
    case Operation.Decoded{Operation.SnapshotGet{snapshot_id, key}}:
      Snapshots.snapshot.get(handle, snapshots, cursors, context, snapshot_id, key)
    case Operation.Decoded{Operation.SnapshotClose{snapshot_id}}:
      Snapshots.snapshot.close(handle, snapshots, cursors, context, snapshot_id)
    case Operation.Decoded{Operation.SnapshotCursorOpen{snapshot_id, bounds}}:
      Snapshots.snapshot.cursor.open(handle, snapshots, cursors, context, snapshot_id,
        bounds)
    case Operation.Decoded{Operation.SnapshotCursorNext{cursor_id}}:
      Snapshots.snapshot.cursor.next(handle, snapshots, cursors, context, cursor_id)
    case Operation.Decoded{Operation.SnapshotCursorClose{cursor_id}}:
      Snapshots.snapshot.cursor.close(handle, snapshots, cursors, context, cursor_id)
    case Operation.Decoded{Operation.SnapshotCursorSeek{cursor_id, lower}}:
      Snapshots.snapshot.cursor.seek(handle, snapshots, cursors, context, cursor_id,
        lower)
    case Operation.Decoded{Operation.Compact{}}:
      compact.preflight(handle, snapshots, cursors, context)
    case Operation.Decoded{operation}:
      do IO<Reply.DispatchResult>:
        pair : ByteDb.Handle & Protocol.Response <-
          dispatch.operation(handle, context, operation)
        return Reply.dispatch.result(pair, snapshots, cursors)
    case Operation.MalformedArguments{}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Operation.UnsupportedOperation{}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def dispatch.decoded(
  handle: ByteDb.Handle,
  context: Reply.ReplyContext,
  decision: Operation.Decision
) -> IO(ByteDb.Handle & Protocol.Response):
  match decision:
    case Operation.Decoded{operation}:
      dispatch.operation(handle, context, operation)
    case Operation.MalformedArguments{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{},
          Bytes.new(0))))
    case Operation.UnsupportedOperation{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{},
          Bytes.new(0))))

def dispatch.validated(
  handle: ByteDb.Handle,
  context: Reply.ReplyContext,
  decision: Protocol.Decision
) -> IO(ByteDb.Handle & Protocol.Response):
  match decision:
    case Protocol.Accepted{_, operation_code, payload}:
      dispatch.decoded(handle, context,
        Operation.decode.payload(operation_code, payload))
    case Protocol.VersionMismatch{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Protocol.StaleGeneration{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Protocol.UnsupportedRequestOperation{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))))
    case Protocol.ResourceLimit{}:
      IO.pure(ByteDb.Handle & Protocol.Response,
        (handle, Reply.reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))))

def dispatch.validated.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  decision: Protocol.Decision
) -> IO(Reply.DispatchResult):
  match decision:
    case Protocol.Accepted{_, operation_code, payload}:
      dispatch.decoded.state(handle, snapshots, cursors, context,
        Operation.decode.payload(operation_code, payload))
    case Protocol.VersionMismatch{}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Protocol.StaleGeneration{}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Protocol.UnsupportedRequestOperation{}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})
    case Protocol.ResourceLimit{}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})

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
                    Reply.ReplyContext{(response_version, response_version_hold),
                      (Generation.response.generation(response_generation),
                        response_generation_hold),
                      (response_id, response_id_hold),
                      ResourceOptions.defaults()},
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
  active_generations: U32 & U32,
  options: ResourceOptions.Options
) -> IO(Reply.DispatchResult):
  match versions:
    case (version, (response_version, response_version_hold)):
      match generations:
        case (generation, (_, response_generation_hold)):
          match request_ids:
            case (request_id, (response_id, response_id_hold)):
              match active_generations:
                case (response_generation, active_generation):
                  dispatch.validated.state(handle, snapshots, cursors,
                    Reply.ReplyContext{(response_version, response_version_hold),
                      (Generation.response.generation(response_generation),
                        response_generation_hold),
                      (response_id, response_id_hold), options},
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

def dispatch.request.with_options(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  active_generation: U32,
  options: ResourceOptions.Options
) -> IO(Reply.DispatchResult):
  match request:
    case Protocol.Request{version, generation, request_id, operation_code, payload}:
      dispatch.request.copies.state(handle, snapshots, cursors,
        Protocol.u32.duplicate.triple(version),
        Protocol.u32.duplicate.triple(generation),
        Protocol.u32.duplicate.triple(request_id), operation_code, payload,
        u32.duplicate.pair(active_generation), options)

def dispatch.request.state(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  request: Protocol.Request,
  active_generation: U32
) -> IO(Reply.DispatchResult):
  dispatch.request.with_options(handle, snapshots, cursors, request,
    active_generation, ResourceOptions.defaults())
