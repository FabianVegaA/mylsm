import Base
import ./Reply.bend as Reply
import ../../ByteDurableDb.bend as ByteDb
import ../../ResourceOptions.bend as ResourceOptions
import ../Protocol.bend as Protocol
import ../OwnerSnapshotStore.bend as SnapshotStore
import ../OwnerCursorStore.bend as CursorStore
import ../../scan/VisibleCursor.bend as VisibleCursor
import ../../scan/RangeCursor.bend as RangeCursor
import ../../ByteMemTable.bend as ByteMemTable
import ../../ByteManifest.bend as ByteManifest
import ../../ByteManifestIo.bend as ByteManifestIo
import ../CursorCodec.bend as CursorCodec
import ../../Fs.bend as Fs
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries one bounded owner-cursor read across visible-source steps.
type CursorReadState is Type:
  CursorReadNeed{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, context: Reply.ReplyContext, cursor_id: U32,
    release_id: U32, cursor: VisibleCursor.Cursor}
  CursorReadStep{handle: ByteDb.Handle,
    snapshots: SnapshotStore.Store,
    cursors: CursorStore.Store, context: Reply.ReplyContext, cursor_id: U32,
    release_id: U32, step: VisibleCursor.Step}

def snapshot.generation(value: Maybe<&1, U32>) -> Nat:
  match value:
    case None{}: 0n
    case Some{generation}: U32.to_nat(generation)

def snapshot.open.result(
  handle: ByteDb.Handle,
  context: Reply.ReplyContext,
  cursors: CursorStore.Store,
  result: SnapshotStore.OpenResult
) -> Reply.DispatchResult:
  match result:
    case SnapshotStore.RootStored{store, snapshot_id}:
      Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.Success{},
          Protocol.snapshot.id.bytes(snapshot_id))}
    case SnapshotStore.RootRejected{store}:
      Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))}

def snapshot.open.root.configured(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context_options: Reply.ReplyContext & ResourceOptions.Options,
  cursors: CursorStore.Store,
  roots: ByteDb.SnapshotRoot & ByteDb.SnapshotRoot
) -> Reply.DispatchResult:
  match context_options:
    case (context, +options):
      match roots:
        case (generation_root, retained_root):
          match generation_root:
            case ByteDb.SnapshotRoot{_, sst_generation, _, _}:
              snapshot.open.result(handle, context, cursors,
                SnapshotStore.open.root(snapshots, retained_root,
                  snapshot.generation(sst_generation),
                  (U32.to_nat(ResourceOptions.snapshot.count(options)),
                    U32.to_nat(ResourceOptions.snapshot.retained.bytes(options)))))

def snapshot.open.root.copies(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: Reply.ReplyContext,
  cursors: CursorStore.Store,
  roots: ByteDb.SnapshotRoot & ByteDb.SnapshotRoot
) -> Reply.DispatchResult:
  snapshot.open.root.configured(handle, snapshots,
    Reply.reply.options.pair(context), cursors, roots)

def snapshot.open.captured(
  pair: ByteDb.Handle & Result<&1, &1, ByteDb.Error, ByteDb.SnapshotRoot>,
  snapshots: SnapshotStore.Store,
  context: Reply.ReplyContext,
  cursors: CursorStore.Store
) -> Reply.DispatchResult:
  match pair:
    case (handle, Fail{error}):
      Reply.dispatch.result((handle, Reply.reply.response(context, Reply.error.status(error),
        Bytes.new(0))), snapshots, cursors)
    case (handle, Done{root}):
      snapshot.open.root.copies(handle, snapshots, context, cursors,
        ByteDb.snapshot.root.clone(root))

def snapshot.open.configured(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context_options: Reply.ReplyContext & ResourceOptions.Options,
  cursors: CursorStore.Store
) -> IO(Reply.DispatchResult):
  match context_options:
    case (context, +options):
      do IO<Reply.DispatchResult>:
        captured : ByteDb.Handle &
          Result<&1, &1, ByteDb.Error, ByteDb.SnapshotRoot> <-
            ByteDb.snapshot_root_limited(
              U32.to_nat(ResourceOptions.snapshot.retained.bytes(options)),
              handle)
        return snapshot.open.captured(captured, snapshots, context, cursors)

def snapshot.open(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: Reply.ReplyContext,
  cursors: CursorStore.Store
) -> IO(Reply.DispatchResult):
  snapshot.open.configured(handle, snapshots, Reply.reply.options.pair(context),
    cursors)

def snapshot.get.result(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  result: Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>>
) -> Reply.DispatchResult:
  match result:
    case Fail{error}:
      Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Reply.error.status(error), Bytes.new(0))}
    case Done{None{}}:
      Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.NotFound{}, Bytes.new(0))}
    case Done{Some{value}}:
      Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.Success{}, value)}

def snapshot.get.lookup(
  handle: ByteDb.Handle,
  context: Reply.ReplyContext,
  cursors: CursorStore.Store,
  key: Bytes.Bytes,
  lookup: SnapshotStore.LookupResult
) -> IO(Reply.DispatchResult):
  match lookup:
    case SnapshotStore.RootFound{store, root}:
      do IO<Reply.DispatchResult>:
        result : Result<&1, &1, ByteDb.Error, Maybe<&1, Bytes.Bytes>> <-
          ByteDb.snapshot.root.get(root, key)
        return snapshot.get.result(handle, store, cursors, context, result)
    case SnapshotStore.RootMissing{store}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.get(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshot_id: U32,
  key: Bytes.Bytes
) -> IO(Reply.DispatchResult):
  snapshot.get.lookup(handle, context, cursors, key,
    SnapshotStore.lookup.root(snapshots, snapshot_id))

def snapshot.close.reply(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  status: Protocol.ResponseStatus
) -> Reply.DispatchResult:
  Reply.DispatchResult{handle, snapshots, cursors,
    Reply.reply.response(context, status, Bytes.new(0))}

def snapshot.close.cleanup.removed(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  removed: Result<&1, &1, U32 & String, Unit>
) -> IO(Reply.DispatchResult):
  match removed:
    case Done{Unit{}}:
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Success{}))
    case Fail{_}:
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.IoFailure{}))

def snapshot.close.cleanup.exists(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  stale_path: String,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(Reply.DispatchResult):
  match exists:
    case Fail{_}:
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.IoFailure{}))
    case Done{False{}}:
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Success{}))
    case Done{True{}}:
      do IO<Reply.DispatchResult>:
        removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(stale_path)
        snapshot.close.cleanup.removed(handle, snapshots, cursors, context,
          removed)

def snapshot.close.cleanup.paths(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  paths: String & String
) -> IO(Reply.DispatchResult):
  match paths:
    case (check_path, stale_path):
      do IO<Reply.DispatchResult>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(check_path)
        snapshot.close.cleanup.exists(handle, snapshots, cursors, context,
          stale_path, exists)

def snapshot.close.cleanup(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  stale_path: String
) -> IO(Reply.DispatchResult):
  snapshot.close.cleanup.paths(handle, snapshots, cursors, context,
    ByteDb.path.clone.pair(stale_path))

def snapshot.close.reclaim(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  stale_path: String,
  decision: Bool & SnapshotStore.Store
) -> IO(Reply.DispatchResult):
  match decision:
    case (False{}, snapshots):
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Success{}))
    case (True{}, snapshots):
      snapshot.close.cleanup(handle, snapshots, cursors, context, stale_path)

def snapshot.close.manifest.current(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  candidate: U32,
  stale_path: String,
  manifest: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Reply.DispatchResult):
  match manifest:
    case Fail{ByteManifestIo.Invalid{_}}:
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Corruption{}))
    case Fail{ByteManifestIo.Host{_, _}}:
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.IoFailure{}))
    case Done{value}:
      match value:
        case ByteManifest.GenerationSst{file_id}:
          snapshot.close.reclaim(handle, cursors, context, stale_path,
            SnapshotStore.generation.can.reclaim(snapshots, candidate,
              Some{file_id}))
        case _:
          snapshot.close.reclaim(handle, cursors, context, stale_path,
            SnapshotStore.generation.can.reclaim(snapshots, candidate,
              None{}))

def snapshot.close.manifest(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: U32,
  stale_path: String,
  manifest: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Reply.DispatchResult):
  snapshot.close.manifest.current(handle, snapshots, cursors, context,
    candidate, stale_path, manifest)

# Reads the active manifest before deciding whether a closed root is obsolete.
def snapshot_close_root_path_read(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshots: SnapshotStore.Store,
  file_id: U32,
  path: String,
  manifest_path: String
) -> IO(Reply.DispatchResult):
  do IO<Reply.DispatchResult>:
    manifest : Result<&1, &1, ByteManifestIo.Error,
      ByteManifest.ManifestValue> <-
        ByteManifestIo.read(manifest_path ++ "/MANIFEST")
    snapshot.close.manifest(handle, cursors, context,
      snapshots, file_id, path, manifest)

# Preserves the database handle while reading the active manifest path.
def snapshot_close_root_path_reclaim(
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshots: SnapshotStore.Store,
  file_id: U32,
  path: String,
  paths: ByteDb.Handle & String
) -> IO(Reply.DispatchResult):
  match paths:
    case (retained_handle, manifest_path):
      snapshot_close_root_path_read(retained_handle, cursors, context,
        snapshots, file_id, path, manifest_path)

# Skips legacy roots and checks generation references before unlinking.
def snapshot_close_root_path_candidate_decide(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: Maybe<&1, U32>,
  path: String
) -> IO(Reply.DispatchResult):
      match candidate:
        case None{}:
          IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, snapshots,
            cursors, context, Protocol.Success{}))
        case Some{file_id}:
          snapshot_close_root_path_reclaim(cursors, context, snapshots,
            file_id, path, ByteDb.handle.path.copy(handle))

# Checks the generation only when a closed root has a stored SST path.
def snapshot_close_root_path_candidate_some(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: Maybe<&1, U32>,
  path: String
) -> IO(Reply.DispatchResult):
      snapshot_close_root_path_candidate_decide(handle, cursors, context,
        snapshots, candidate, path)

# Skips filesystem cleanup for roots without a physical SST path.
def snapshot_close_root_path_candidate(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: Maybe<&1, U32>,
  stale_path: Maybe<&1, String>
) -> IO(Reply.DispatchResult):
  match stale_path:
    case None{}:
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, snapshots,
        cursors, context, Protocol.Success{}))
    case Some{path}:
      snapshot_close_root_path_candidate_some(handle, cursors, context,
        snapshots, candidate, path)

def snapshot.close.root.path(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshots: SnapshotStore.Store,
  candidate: Maybe<&1, U32>,
  stale_path: Maybe<&1, String>
) -> IO(Reply.DispatchResult):
  snapshot_close_root_path_candidate(handle, cursors, context, snapshots,
    candidate, stale_path)

def snapshot.close.root(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshots: SnapshotStore.Store,
  root: ByteDb.SnapshotRoot
) -> IO(Reply.DispatchResult):
  match root:
    case ByteDb.SnapshotRoot{sst_path, sst_generation, _, _}:
      snapshot.close.root.path(handle, cursors, context, snapshots,
        sst_generation, sst_path)

def snapshot.close.result(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  result: SnapshotStore.CloseResult
) -> IO(Reply.DispatchResult):
  match result:
    case SnapshotStore.RootClosed{store, root}:
      snapshot.close.root(handle, cursors, context, store, root)
    case SnapshotStore.RootCloseBusy{store}:
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, store, cursors,
        context, Protocol.Busy{}))
    case SnapshotStore.RootCloseMissing{store}:
      IO.pure(Reply.DispatchResult, snapshot.close.reply(handle, store, cursors,
        context, Protocol.InvalidArgument{}))

# Closes one owner snapshot token through the aggregate retention registry.
def snapshot.close(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshot_id: U32
) -> IO(Reply.DispatchResult):
  snapshot.close.result(handle, cursors, context,
    SnapshotStore.close(snapshots, snapshot_id))

def snapshot.cursor.open.register(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  cursor_ids: U32 & U32 & U32,
  cursor: VisibleCursor.Cursor
) -> IO(Reply.DispatchResult):
  match cursor_ids:
    case (store_id, (response_id, _)):
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots,
        CursorStore.insert(cursors, store_id, cursor),
        Reply.reply.response(context, Protocol.Success{},
          Protocol.snapshot.id.bytes(response_id))})

def snapshot.cursor.open.failed(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  error: ByteDb.Error,
  released: SnapshotStore.CursorCloseResult
) -> Reply.DispatchResult:
  match released:
    case SnapshotStore.CursorReleased{updated, _}:
      Reply.DispatchResult{handle, updated, cursors,
        Reply.reply.response(context, Reply.error.status(error), Bytes.new(0))}
    case SnapshotStore.CursorReleaseRejected{updated}:
      Reply.DispatchResult{handle, updated, cursors,
        Reply.reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.opened(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  cursor_id: U32,
  opened: Result<&1, &1, ByteDb.Error, VisibleCursor.Cursor>
) -> IO(Reply.DispatchResult):
  match opened:
    case Fail{error}:
      IO.pure(Reply.DispatchResult, snapshot.cursor.open.failed(handle, cursors,
        context, error,
        SnapshotStore.cursor.close(snapshots, cursor_id)))
    case Done{cursor}:
      snapshot.cursor.open.register(handle, snapshots, cursors, context,
        Protocol.u32.duplicate.triple(cursor_id), cursor)

def snapshot.cursor.open.admitted(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  root: ByteDb.SnapshotRoot,
  bounds: RangeCursor.Bounds,
  decision: SnapshotStore.CursorOpenResult
) -> IO(Reply.DispatchResult):
  match decision:
    case SnapshotStore.CursorRejected{store}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})
    case SnapshotStore.CursorStored{store, cursor_id}:
      do IO<Reply.DispatchResult>:
        opened : Result<&1, &1, ByteDb.Error, VisibleCursor.Cursor> <-
          ByteDb.snapshot.root.cursor.open(root, bounds)
        dispatched : Reply.DispatchResult <-
          snapshot.cursor.opened(handle, store, cursors, context, cursor_id,
            opened)
        return dispatched

def snapshot.cursor.open.global.capacity(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  options: ResourceOptions.Options,
  snapshot_id: U32,
  root: ByteDb.SnapshotRoot,
  bounds: RangeCursor.Bounds,
  available: Bool
) -> IO(Reply.DispatchResult):
  match available:
    case True{}:
      snapshot.cursor.open.admitted(handle, cursors, context, root, bounds,
        SnapshotStore.cursor.open(snapshots, snapshot_id,
          U32.to_nat(ResourceOptions.cursor.per.snapshot(
            options))))
    case False{}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, cursors,
        Reply.reply.response(context, Protocol.ResponseResourceLimit{}, Bytes.new(0))})

def snapshot.cursor.open.lookup.capacity(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context_options: Reply.ReplyContext & ResourceOptions.Options,
  snapshot_id: U32,
  root: ByteDb.SnapshotRoot,
  bounds: RangeCursor.Bounds,
  metrics: CursorStore.Metrics
) -> IO(Reply.DispatchResult):
  match context_options:
    case (context, +options):
      match metrics:
        case CursorStore.Metrics{count, cursors}:
          snapshot.cursor.open.global.capacity(handle, snapshots, cursors,
            context, options, snapshot_id, root, bounds,
            CursorStore.has.capacity(count,
              U32.to_nat(ResourceOptions.cursor.count(options))))

def snapshot.cursor.open.lookup(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshot_id: U32,
  bounds: RangeCursor.Bounds,
  lookup: SnapshotStore.LookupResult
) -> IO(Reply.DispatchResult):
  match lookup:
    case SnapshotStore.RootFound{store, root}:
      snapshot.cursor.open.lookup.capacity(handle, store,
        Reply.reply.options.pair(context), snapshot_id, root, bounds,
        CursorStore.metrics(cursors))
    case SnapshotStore.RootMissing{store}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.cursor.open.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  bounds: RangeCursor.Bounds,
  ids: U32 & U32 & U32
) -> IO(Reply.DispatchResult):
  match ids:
    case (lookup_id, (retained_id, _)):
      snapshot.cursor.open.lookup(handle, cursors, context, retained_id, bounds,
        SnapshotStore.lookup.root(snapshots, lookup_id))

def snapshot.cursor.open(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  snapshot_id: U32,
  bounds: RangeCursor.Bounds
) -> IO(Reply.DispatchResult):
  snapshot.cursor.open.ids(handle, snapshots, cursors, context, bounds,
    Protocol.u32.duplicate.triple(snapshot_id))

def snapshot.cursor.next.response(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  frame: CursorCodec.Frame
) -> Reply.DispatchResult:
  Reply.DispatchResult{handle, snapshots, cursors,
    Reply.reply.response(context, Protocol.Success{}, CursorCodec.encode(frame))}

def snapshot.cursor.next.item(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  cursor_id: U32,
  key: Bytes.Bytes,
  value: Bytes.Bytes,
  cursor: VisibleCursor.Cursor
) -> Reply.DispatchResult:
  snapshot.cursor.next.response(handle, snapshots,
    CursorStore.reinsert(cursors, cursor_id, cursor), context,
    CursorCodec.CursorItem{key, value})

def snapshot.cursor.next.terminal(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  released: SnapshotStore.CursorCloseResult,
  frame: CursorCodec.Frame
) -> Reply.DispatchResult:
  match released:
    case SnapshotStore.CursorReleased{store, _}:
      snapshot.cursor.next.response(handle, store, cursors, context, frame)
    case SnapshotStore.CursorReleaseRejected{store}:
      Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.next.terminal.error(
  handle: ByteDb.Handle,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  released: SnapshotStore.CursorCloseResult
) -> Reply.DispatchResult:
  match released:
    case SnapshotStore.CursorReleased{store, _}:
      Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.IoFailure{}, Bytes.new(0))}
    case SnapshotStore.CursorReleaseRejected{store}:
      Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.next.loop(
  fuel: Nat,
  state: CursorReadState
) -> IO(Reply.DispatchResult):
  match fuel:
    case 0n:
      match state:
        case CursorReadNeed{handle, snapshots, cursors, context, cursor_id,
            _, cursor}:
          IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots,
            CursorStore.reinsert(cursors, cursor_id, cursor),
            Reply.reply.response(context, Protocol.ResponseResourceLimit{},
              Bytes.new(0))})
        case CursorReadStep{handle, snapshots, cursors, context, cursor_id,
            release_id, step}:
          match step:
            case VisibleCursor.Item{entry, cursor}:
              match entry:
                case ByteMemTable.Entry{key, value}:
                  match value:
                    case Some{bytes}:
                      IO.pure(Reply.DispatchResult, snapshot.cursor.next.item(handle,
                        snapshots, cursors, context, cursor_id, key, bytes,
                        cursor))
                    case None{}:
                      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots,
                        CursorStore.reinsert(cursors, cursor_id, cursor),
                        Reply.reply.response(context, Protocol.ResponseResourceLimit{},
                          Bytes.new(0))})
            case VisibleCursor.Skip{cursor}:
              IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots,
                CursorStore.reinsert(cursors, cursor_id, cursor),
                Reply.reply.response(context, Protocol.ResponseResourceLimit{},
                  Bytes.new(0))})
            case VisibleCursor.End{}:
              IO.pure(Reply.DispatchResult, snapshot.cursor.next.terminal(handle,
                cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id),
                CursorCodec.CursorEnd{}))
            case VisibleCursor.Error{_}:
              IO.pure(Reply.DispatchResult, snapshot.cursor.next.terminal.error(
                handle, cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id)))
    case 1n+rest:
      match state:
        case CursorReadNeed{handle, snapshots, cursors, context, cursor_id,
            release_id, cursor}:
          do IO<Reply.DispatchResult>:
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
                      IO.pure(Reply.DispatchResult, snapshot.cursor.next.item(handle,
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
              IO.pure(Reply.DispatchResult, snapshot.cursor.next.terminal(handle,
                cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id),
                CursorCodec.CursorEnd{}))
            case VisibleCursor.Error{_}:
              IO.pure(Reply.DispatchResult, snapshot.cursor.next.terminal.error(
                handle, cursors, context,
                SnapshotStore.cursor.close(snapshots, release_id)))

def snapshot.cursor.next.taken(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: Reply.ReplyContext,
  ids: U32 & U32,
  result: CursorStore.TakeResult
) -> IO(Reply.DispatchResult):
  match ids:
    case (cursor_id, release_id):
      match result:
        case CursorStore.Taken{store, cursor}:
          snapshot.cursor.next.loop(4096n, CursorReadNeed{handle, snapshots,
            store, context, cursor_id, release_id, cursor})
        case CursorStore.NotFound{store}:
          IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, store,
            Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.cursor.next.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  ids: U32 & U32 & U32
) -> IO(Reply.DispatchResult):
  match ids:
    case (take_id, (cursor_id, release_id)):
      snapshot.cursor.next.taken(handle, snapshots, context,
        (cursor_id, release_id), CursorStore.take(cursors, take_id))

def snapshot.cursor.next(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  cursor_id: U32
) -> IO(Reply.DispatchResult):
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
  context: Reply.ReplyContext,
  outcome: Bool & SnapshotStore.CursorCloseResult
) -> Reply.DispatchResult:
  match outcome:
    case (True{}, SnapshotStore.CursorReleased{store, _}):
      Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.Success{}, Bytes.new(0))}
    case (False{}, SnapshotStore.CursorReleased{store, _}):
      Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.IoFailure{}, Bytes.new(0))}
    case (_, SnapshotStore.CursorReleaseRejected{store}):
      Reply.DispatchResult{handle, store, cursors,
        Reply.reply.response(context, Protocol.Corruption{}, Bytes.new(0))}

def snapshot.cursor.close.closed(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  cursor_id: U32,
  closed: Result<&1, &1, U32 & String, Unit>
) -> IO(Reply.DispatchResult):
  IO.pure(Reply.DispatchResult, snapshot.cursor.close.result(handle, cursors,
    context, (snapshot.cursor.close.success(closed),
      SnapshotStore.cursor.close(snapshots, cursor_id))))

def snapshot.cursor.close.taken(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: Reply.ReplyContext,
  cursor_id: U32,
  result: CursorStore.TakeResult
) -> IO(Reply.DispatchResult):
  match result:
    case CursorStore.Taken{store, cursor}:
      do IO<Reply.DispatchResult>:
        closed : Result<&1, &1, U32 & String, Unit> <-
          VisibleCursor.close(cursor)
        result : Reply.DispatchResult <- snapshot.cursor.close.closed(handle,
          snapshots, store, context, cursor_id, closed)
        return result
    case CursorStore.NotFound{store}:
      IO.pure(Reply.DispatchResult, Reply.DispatchResult{handle, snapshots, store,
        Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))})

def snapshot.cursor.close.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  ids: U32 & U32 & U32
) -> IO(Reply.DispatchResult):
  match ids:
    case (take_id, (release_id, _)):
      snapshot.cursor.close.taken(handle, snapshots, context,
        release_id, CursorStore.take(cursors, take_id))

def snapshot.cursor.close(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  cursor_id: U32
) -> IO(Reply.DispatchResult):
  snapshot.cursor.close.ids(handle, snapshots, cursors, context,
    Protocol.u32.duplicate.triple(cursor_id))

def snapshot.cursor.seek.taken(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  context: Reply.ReplyContext,
  ids: U32 & U32,
  lower: Maybe<&1, Bytes.Bytes>,
  result: CursorStore.TakeResult
) -> Reply.DispatchResult:
  match ids:
    case (cursor_id, _):
      match result:
        case CursorStore.Taken{store, cursor}:
          Reply.DispatchResult{handle, snapshots,
            CursorStore.reinsert(store, cursor_id,
              VisibleCursor.seek(cursor, lower)),
            Reply.reply.response(context, Protocol.Success{}, Bytes.new(0))}
        case CursorStore.NotFound{store}:
          Reply.DispatchResult{handle, snapshots, store,
            Reply.reply.response(context, Protocol.InvalidArgument{}, Bytes.new(0))}

def snapshot.cursor.seek.ids(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  ids: U32 & U32 & U32,
  lower: Maybe<&1, Bytes.Bytes>
) -> IO(Reply.DispatchResult):
  match ids:
    case (cursor_id, (response_id, take_id)):
      IO.pure(Reply.DispatchResult, snapshot.cursor.seek.taken(handle, snapshots,
        context, (cursor_id, response_id), lower,
        CursorStore.take(cursors, take_id)))

def snapshot.cursor.seek(
  handle: ByteDb.Handle,
  snapshots: SnapshotStore.Store,
  cursors: CursorStore.Store,
  context: Reply.ReplyContext,
  cursor_id: U32,
  lower: Maybe<&1, Bytes.Bytes>
) -> IO(Reply.DispatchResult):
  snapshot.cursor.seek.ids(handle, snapshots, cursors, context,
    Protocol.u32.duplicate.triple(cursor_id), lower)
