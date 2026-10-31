import Base
import ./src/DurableError.bend as DurableError
import bend-kit-bytes@0.3.2.0/bytes.bend as PackedBytes
import ./src/ByteDurableDb.bend as RawByteDb
import ./src/ByteWal.bend as RawByteWal
import ./src/ByteMemTable.bend as ByteMemTable
import ./src/scan/RangeCursor.bend as ByteRangeCursor
import ./src/scan/VisibleCursor.bend as VisibleByteCursor
import ./src/scan/Snapshot.bend as SnapshotPolicy
import ./src/scan/Utf8CursorPolicy.bend as Utf8CursorPolicy
import ./src/scan/CursorCleanupPolicy.bend as CursorCleanupPolicy
import ./src/transfer/Backup.bend as BackupCodec
import ./src/transfer/BackupIo.bend as BackupIo
import ./src/transfer/BackupCursorIo.bend as BackupCursorIo
import ./src/transfer/BackupOwnerCursorIo.bend as BackupOwnerCursorIo
import ./src/transfer/RestoreIo.bend as RestoreIo
import ./src/transfer/FormatInspect.bend as FormatInspect
import ./src/transfer/FormatInspectIo.bend as FormatInspectIo
import ./src/transfer/MigrateRunIo.bend as MigrateRunIo
import ./src/StorageBytes.bend as Utf8Codec
import ./src/Fs.bend as Fs
import ./src/coordinator/EndpointPath.bend as EndpointPath
import ./src/coordinator/OwnerGenerationIo.bend as OwnerGenerationIo
import ./src/coordinator/Client.bend as OwnerClient
import ./src/coordinator/ByteClient.bend as OwnerByteClient
import ./src/coordinator/CursorCodec.bend as OwnerCursorCodec
import ./src/coordinator/Protocol.bend as CoordinatorProtocol
import ./src/coordinator/StatsCodec.bend as OwnerStatsCodec
import ./src/coordinator/Io.bend as OwnerIo
import ./src/coordinator/UnixSocketIo.bend as OwnerSocket
import ./src/coordinator/CoordinatorPolicy.bend as OwnerPolicy
import ./src/coordinator/OwnerOpenPolicy.bend as OwnerOpenPolicy
import ./src/ResourceOptions.bend as ResourceOptions
import ./src/coordinator/OptionsCodec.bend as OwnerOptionsCodec

# Describes manifest validation independently from package/storage identity.
type ManifestStatus is Data:
  ManifestValid{}
  ManifestVersionUnsupported{generation: U32}
  ManifestComparatorUnsupported{generation: U32}
  ManifestFormatUnknown{}
  ManifestCorrupt{}
  ManifestResourceLimit{}

# Reports package version, storage generation, and validation status.
type ManifestInspection is Data:
  ManifestInspection{package_version: String, storage_version: String,
    generation: U32, status: ManifestStatus}

# Reports lock or host errors from the read-only inspection operation.
type InspectionError is Data:
  InspectionBusy{}
  InspectionTimeout{}
  InspectionUnsupportedPlatform{}
  InspectionLockIo{code: U32, message: String}
  InspectionIo{code: U32, message: String}

type Bytes.Error is Data:
  Busy{}
  Timeout{}
  NotFound{}
  AlreadyExists{}
  InvalidArgument{}
  UnsupportedPlatform{}
  UnsupportedOperation{}
  ResourceLimit{}
  Corruption{message: String}
  Io{code: U32, message: String}
  CommitUnknown{code: U32, message: String}
  StaleOwner{}

type Bytes.Stats is Data:
  ByteStats{entries: Nat, payload_bytes: Nat, snapshots: Nat, retained_bytes: Nat, cursors: Nat}

type Bytes.Snapshot is Type:
  ByteSnapshot{entries: List<&1, ByteMemTable.Entry>}
  RemoteByteSnapshot{session: OwnerClient.Session, snapshot_id: U32}

type Bytes.BackupStream is Type:
  ByteBackupStream{inner: BackupCodec.Stream}

type Bytes.BackupStep is Type:
  BackupChunk{stream: Bytes.BackupStream, bytes: PackedBytes.Bytes}
  BackupEnd{}

# Converts internal byte-engine errors into the public byte API error type.
def Bytes.error(error: RawByteDb.Error) -> Bytes.Error:
  match error:
    case RawByteDb.Busy{}: Busy{}
    case RawByteDb.Timeout{}: Timeout{}
    case RawByteDb.NotFound{}: NotFound{}
    case RawByteDb.AlreadyExists{}: AlreadyExists{}
    case RawByteDb.InvalidArgument{}: InvalidArgument{}
    case RawByteDb.UnsupportedPlatform{}: UnsupportedPlatform{}
    case RawByteDb.ResourceLimit{}: ResourceLimit{}
    case RawByteDb.Corruption{message}: Corruption{message}
    case RawByteDb.Io{code, message}: Io{code, message}
    case RawByteDb.CommitUnknown{code, message}: CommitUnknown{code, message}

def Bytes.error.result(result: Result<&1, &1, RawByteDb.Error, Unit>) -> Result<&1, &1, Bytes.Error, Unit>:
  match result:
    case Fail{error}: Fail{Bytes.error(error)}
    case Done{Unit{}}: Done{Unit{}}

def Bytes.error.maybe(
  result: Result<&1, &1, RawByteDb.Error, Maybe<&1, PackedBytes.Bytes>>
) -> Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>:
  match result:
    case Fail{error}: Fail{Bytes.error(error)}
    case Done{value}: Done{value}

def Bytes.owner.error.status(status: CoordinatorProtocol.ResponseStatus) -> Bytes.Error:
  match status:
    case CoordinatorProtocol.Success{}: InvalidArgument{}
    case CoordinatorProtocol.InvalidArgument{}: InvalidArgument{}
    case CoordinatorProtocol.NotFound{}: NotFound{}
    case CoordinatorProtocol.Busy{}: Busy{}
    case CoordinatorProtocol.Timeout{}: Timeout{}
    case CoordinatorProtocol.ResponseResourceLimit{}: ResourceLimit{}
    case CoordinatorProtocol.Corruption{}: Corruption{"owner reported corruption"}
    case CoordinatorProtocol.IoFailure{}: Io{0, "owner IO failure"}
    case CoordinatorProtocol.CommitUnknown{}: CommitUnknown{0, "owner commit is uncertain"}
    case CoordinatorProtocol.AlreadyExists{}: AlreadyExists{}
    case CoordinatorProtocol.UnsupportedPlatform{}: UnsupportedPlatform{}
    case CoordinatorProtocol.InvalidUtf8{}: Corruption{"owner rejected invalid UTF-8"}
    case CoordinatorProtocol.UnsupportedFormat{}: Corruption{"owner storage format is unsupported"}

def Bytes.owner.error.socket(error: OwnerSocket.Error) -> Bytes.Error:
  match error:
    case OwnerSocket.UnsupportedPlatform{}: UnsupportedPlatform{}
    case OwnerSocket.Transient{code}: Io{code, "owner socket operation was interrupted"}
    case OwnerSocket.Host{code, message}: Io{code, message}

def Bytes.owner.error.io(error: OwnerIo.Error) -> Bytes.Error:
  match error:
    case OwnerIo.UnsupportedPlatform{}: UnsupportedPlatform{}
    case OwnerIo.Transient{code}: Io{code, "owner response IO was interrupted"}
    case OwnerIo.Host{code, message}: Io{code, message}
    case _: Corruption{"owner response transport was invalid"}

def Bytes.owner.error.commit(error: OwnerIo.Error) -> Bytes.Error:
  match error:
    case OwnerIo.Transient{code}:
      CommitUnknown{code, "mutation response IO was interrupted"}
    case OwnerIo.Host{code, message}: CommitUnknown{code, message}
    case _: CommitUnknown{0, "mutation outcome is uncertain"}

def Bytes.owner.error(error: OwnerClient.Error) -> Bytes.Error:
  match error:
    case OwnerClient.ConnectFailure{error}: Bytes.owner.error.socket(error)
    case OwnerClient.RetryRead{error}: Bytes.owner.error.io(error)
    case OwnerClient.CommitUnknown{error}: Bytes.owner.error.commit(error)
    case OwnerClient.FrameTooLarge{}: ResourceLimit{}
    case OwnerClient.StaleOwner{}: StaleOwner{}
    case OwnerClient.CorrelationMismatch{}: Corruption{"owner response correlation mismatch"}
    case OwnerClient.MalformedResponse{}: Corruption{"owner response is malformed"}
    case OwnerClient.RequestIdsExhausted{}: ResourceLimit{}
    case OwnerClient.OwnerRejected{status}: Bytes.owner.error.status(status)

def Bytes.owner.unit.result(
  pair: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>:
  match pair:
    case (session, Fail{error}):
      (RemoteByteHandle{session}, Fail{Bytes.owner.error(error)})
    case (session, Done{Unit{}}):
      (RemoteByteHandle{session}, Done{Unit{}})

def Bytes.owner.get.result(
  pair:
    OwnerClient.Session &
      Result<&1, &1, OwnerClient.Error, Maybe<&1, PackedBytes.Bytes>>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>:
  match pair:
    case (session, Fail{error}):
      (RemoteByteHandle{session}, Fail{Bytes.owner.error(error)})
    case (session, Done{value}):
      (RemoteByteHandle{session}, Done{value})

type Bytes.Handle is Type:
  ByteHandle{raw: RawByteDb.Handle}
  RemoteByteHandle{session: OwnerClient.Session}

type Bytes.Mutation is Type:
  BytesPut{key: PackedBytes.Bytes, value: PackedBytes.Bytes}
  BytesDelete{key: PackedBytes.Bytes}

type Bytes.ScanBounds is Type:
  ScanBounds{lower: Maybe<&1, PackedBytes.Bytes>, upper: Maybe<&1, PackedBytes.Bytes>,
    prefix: Maybe<&1, PackedBytes.Bytes>}

type Bytes.Cursor is Type:
  ByteCursor{inner: ByteRangeCursor.Cursor, bounds: ByteRangeCursor.Bounds}
  ByteStreamCursor{inner: VisibleByteCursor.Cursor}
  ByteOwnerCursor{session: OwnerClient.Session, snapshot_id: U32, cursor_id: U32}
  ByteOwnedCursor{snapshot: Bytes.Snapshot, inner: Bytes.Cursor,
    bounds: ByteRangeCursor.Bounds}
  ByteFailureCursor{error: Bytes.Error}
  ByteClosedCursor{}

type Bytes.ScanStep is Type:
  ScanItem{key: PackedBytes.Bytes, value: PackedBytes.Bytes, cursor: Bytes.Cursor}
  ScanSkip{cursor: Bytes.Cursor}
  ScanEnd{cursor: Bytes.Cursor}
  ScanFailure{error: Bytes.Error, cursor: Bytes.Cursor}

type Bytes.StreamStep is Type:
  StreamItem{key: PackedBytes.Bytes, value: PackedBytes.Bytes,
    cursor: Bytes.Cursor}
  StreamSkip{cursor: Bytes.Cursor}
  StreamEnd{cursor: Bytes.Cursor}
  StreamFailure{error: Bytes.Error, cursor: Bytes.Cursor}

# Converts public byte mutations into the durable WAL batch representation.
def Bytes.mutations(mutations: List<&1, Bytes.Mutation>) -> List<&1, RawByteWal.Mutation>:
  match mutations:
    case Nil{}: Nil{}
    case Con{BytesPut{key, value}, tail}:
      Con{RawByteWal.Put{key, value}, Bytes.mutations(tail)}
    case Con{BytesDelete{key}, tail}:
      Con{RawByteWal.Delete{key}, Bytes.mutations(tail)}


def Bytes.handle(
  result: Result<&1, &1, RawByteDb.Error, RawByteDb.Handle>
) -> Result<&1, &1, Bytes.Error, Bytes.Handle>:
  match result:
    case Fail{error}: Fail{Bytes.error(error)}
    case Done{raw}: Done{ByteHandle{raw}}

def Bytes.remote.handshake.validated(
  session: OwnerClient.Session,
  decision: ResourceOptions.Decision
) -> Result<&1, &1, Bytes.Error, Bytes.Handle>:
  match decision:
    case ResourceOptions.Accepted{_}: Done{RemoteByteHandle{session}}
    case _: Fail{Corruption{"owner options are invalid"}}

def Bytes.remote.handshake.result(
  pair: OwnerClient.Session &
    Result<&1, &1, OwnerClient.Error, OwnerOptionsCodec.Decision>
) -> Result<&1, &1, Bytes.Error, Bytes.Handle>:
  match pair:
    case (_, Fail{error}): Fail{Bytes.owner.error(error)}
    case (session, Done{OwnerOptionsCodec.Parsed{options}}):
      Bytes.remote.handshake.validated(session,
        ResourceOptions.validate(options))
    case (_, Done{_}): Fail{Corruption{"owner options response is invalid"}}

def Bytes.remote.handshake(
  pair: OwnerClient.Session &
    Result<&1, &1, OwnerClient.Error, OwnerOptionsCodec.Decision>
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
    Bytes.remote.handshake.result(pair))

def Bytes.remote.role(
  endpoint: String,
  generation: U32,
  role: OwnerPolicy.OpenRole
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match role:
    case OwnerPolicy.ExistingOwnerClient{}:
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        described : OwnerClient.Session &
          Result<&1, &1, OwnerClient.Error, OwnerOptionsCodec.Decision> <-
            OwnerByteClient.describe_owner(
              OwnerClient.session.open(endpoint, generation))
        Bytes.remote.handshake(described)
    case OwnerPolicy.ReturnBusy{}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>, Fail{Busy{}})
    case OwnerPolicy.PropagateOpenFailure{}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Io{0, "owner role could not be established"}})
    case OwnerPolicy.LocalOwner{}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>, Fail{Busy{}})

def Bytes.endpoint.generation(
  endpoint: String,
  result: Result<&1, &1, OwnerGenerationIo.Error, U32>
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match result:
    case Fail{OwnerGenerationIo.Host{code, message}}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>, Fail{Io{code, message}})
    case Fail{OwnerGenerationIo.Invalid{}}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Corruption{"owner generation is invalid"}})
    case Fail{OwnerGenerationIo.Exhausted{}}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Corruption{"owner generation is exhausted"}})
    case Done{generation}:
      Bytes.remote.role(endpoint, generation, OwnerPolicy.open.role(
        OwnerPolicy.LockBusy{}, OwnerPolicy.EndpointPresent{}))

def Bytes.endpoint.checked(
  canonical: String,
  endpoint: String,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match exists:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Io{code, message}})
    case Done{True{}}:
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        generation : Result<&1, &1, OwnerGenerationIo.Error, U32> <-
          OwnerGenerationIo.read(canonical ++ "/OWNER.GEN")
        Bytes.endpoint.generation(endpoint, generation)
    case Done{False{}}:
      Bytes.remote.role(endpoint, 0, OwnerPolicy.open.role(
        OwnerPolicy.LockBusy{}, OwnerPolicy.EndpointMissing{}))

def Bytes.endpoint.path.pair.go(
  path: String,
  left: String,
  right: String
) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      Bytes.endpoint.path.pair.go(rest, SCon{character, left},
        SCon{character, right})

def Bytes.endpoint.path.pair(path: String) -> String & String:
  Bytes.endpoint.path.pair.go(path, SNil{}, SNil{})

def Bytes.endpoint.exists(
  paths: String & String & String
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match paths:
    case (canonical, (exists_path, retained_path)):
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(exists_path)
        Bytes.endpoint.checked(canonical, retained_path, exists)

def Bytes.endpoint.result(
  canonical: String,
  decision: EndpointPath.Decision
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match decision:
    case EndpointPath.Endpoint{path}:
      Bytes.endpoint.exists((canonical, Bytes.endpoint.path.pair(path)))
    case EndpointPath.PathTooLong{}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{UnsupportedPlatform{}})

def Bytes.canonical.endpoint.paths(
  paths: String & String
) ->
  IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match paths:
    case (endpoint_path, retained_path):
      Bytes.endpoint.result(retained_path,
        EndpointPath.for_canonical_path(endpoint_path))

def Bytes.canonical.endpoint(
  result: Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Io{code, message}})
    case Done{canonical}:
      Bytes.canonical.endpoint.paths(Bytes.endpoint.path.pair(canonical))

def Bytes.owner.candidate(
  path: String,
  result: Result<&1, &1, RawByteDb.Error, RawByteDb.Handle>
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match result:
    case Done{raw}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Done{ByteHandle{raw}})
    case Fail{RawByteDb.Busy{}}:
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        canonical : Result<&1, &1, U32 & String, String> <-
          Fs.canonical_path(path)
        Bytes.canonical.endpoint(canonical)
    case Fail{error}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Bytes.error(error)})

def Bytes.owner.wait.endpoint(
  canonical: String,
  timeout_ms: U32,
  backoff_ms: U32,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match exists:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Io{code, message}})
    case Done{True{}}:
      Bytes.canonical.endpoint.paths(Bytes.endpoint.path.pair(canonical))
    case Done{False{}}:
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        opened : Result<&1, &1, RawByteDb.Error, RawByteDb.Handle> <-
          RawByteDb.open_existing_wait(canonical, timeout_ms, backoff_ms)
        return Bytes.handle(opened)

def Bytes.owner.wait.endpoint.path(
  paths: String & String,
  timeout_ms: U32,
  backoff_ms: U32
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match paths:
    case (canonical, endpoint):
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(endpoint)
        Bytes.owner.wait.endpoint(canonical, timeout_ms, backoff_ms,
          exists)

def Bytes.owner.wait.decided(
  canonical: String,
  decision: EndpointPath.Decision,
  timeout_ms: U32,
  backoff_ms: U32
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match decision:
    case EndpointPath.Endpoint{endpoint}:
      Bytes.owner.wait.endpoint.path((canonical, endpoint), timeout_ms,
        backoff_ms)
    case EndpointPath.PathTooLong{}:
      Bytes.owner.wait.endpoint(canonical, timeout_ms, backoff_ms,
        Done{False{}})

def Bytes.owner.wait.located(
  paths: String & String,
  timeout_ms: U32,
  backoff_ms: U32
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match paths:
    case (canonical, endpoint_source):
      Bytes.owner.wait.decided(canonical,
        EndpointPath.for_canonical_path(endpoint_source), timeout_ms,
        backoff_ms)

def Bytes.owner.wait.canonical(
  timeout_ms: U32,
  backoff_ms: U32,
  result: Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Io{code, message}})
    case Done{canonical}:
      Bytes.owner.wait.located(Bytes.endpoint.path.pair(canonical),
        timeout_ms, backoff_ms)

def Bytes.owner.wait.candidate(
  path: String,
  timeout_ms: U32,
  backoff_ms: U32,
  result: Result<&1, &1, RawByteDb.Error, RawByteDb.Handle>
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match result:
    case Done{raw}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Done{ByteHandle{raw}})
    case Fail{RawByteDb.Busy{}}:
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        canonical : Result<&1, &1, U32 & String, String> <-
          Fs.canonical_path(path)
        Bytes.owner.wait.canonical(timeout_ms, backoff_ms,
          canonical)
    case Fail{error}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Bytes.error(error)})

def Bytes.create(+path: String) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
    opened : Result<&1, &1, RawByteDb.Error, RawByteDb.Handle> <-
      RawByteDb.create(path)
    Bytes.owner.candidate(path, opened)

def Bytes.open_existing(+path: String) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
    opened : Result<&1, &1, RawByteDb.Error, RawByteDb.Handle> <-
      RawByteDb.open_existing(path)
    Bytes.owner.candidate(path, opened)

def Bytes.options.rejected(
  handle: Bytes.Handle
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match handle:
    case ByteHandle{raw}:
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        _closed : Result<&1, &1, RawByteDb.Error, Unit> <- RawByteDb.close(raw)
        return Fail{InvalidArgument{}}
    case RemoteByteHandle{_}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{InvalidArgument{}})

def Bytes.options.decided(
  decision: OwnerOpenPolicy.Decision,
  handle: Bytes.Handle
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match decision:
    case OwnerOpenPolicy.UseLocal{}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>, Done{handle})
    case OwnerOpenPolicy.UseRemote{}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>, Done{handle})
    case OwnerOpenPolicy.RejectOptions{}: Bytes.options.rejected(handle)

def Bytes.options.local(
  options: ResourceOptions.Options,
  handle: Bytes.Handle
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  Bytes.options.decided(OwnerOpenPolicy.choose(True{},
    ResourceOptions.same(options, ResourceOptions.defaults())), handle)

def Bytes.options.remote.result(
  pair: OwnerClient.Session &
    Result<&1, &1, OwnerClient.Error, OwnerOptionsCodec.Decision>,
  expected: ResourceOptions.Options
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match pair:
    case (_, Fail{error}):
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Bytes.owner.error(error)})
    case (session, Done{OwnerOptionsCodec.Parsed{options}}):
      Bytes.options.decided(OwnerOpenPolicy.choose(False{},
        ResourceOptions.same(options, expected)), RemoteByteHandle{session})
    case (_, Done{_}):
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{Corruption{"owner options response is invalid"}})

def Bytes.options.remote(
  session: OwnerClient.Session,
  expected: ResourceOptions.Options
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
    described : OwnerClient.Session &
      Result<&1, &1, OwnerClient.Error, OwnerOptionsCodec.Decision> <-
        OwnerByteClient.describe_owner(session)
    Bytes.options.remote.result(described, expected)

def Bytes.options.opened(
  handle: Bytes.Handle,
  options: ResourceOptions.Options
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match handle:
    case ByteHandle{_}: Bytes.options.local(options, handle)
    case RemoteByteHandle{session}: Bytes.options.remote(session, options)

def Bytes.options.opened.result(
  result: Result<&1, &1, Bytes.Error, Bytes.Handle>,
  options: ResourceOptions.Options
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>, Fail{error})
    case Done{handle}: Bytes.options.opened(handle, options)

def Bytes.open_existing.options.decision(
  +path: String,
  decision: ResourceOptions.Decision
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match decision:
    case ResourceOptions.Accepted{options}:
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        opened : Result<&1, &1, Bytes.Error, Bytes.Handle> <-
          Bytes.open_existing(path)
        Bytes.options.opened.result(opened, options)
    case _: IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
      Fail{InvalidArgument{}})

def Bytes.open_existing_with_options(
  +path: String,
  options: ResourceOptions.Options
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  Bytes.open_existing.options.decision(path,
    ResourceOptions.validate(options))

def Bytes.create.options.probe.result(
  result: Result<&1, &1, Bytes.Error, Bytes.Handle>
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match result:
    case Fail{NotFound{}}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Fail{InvalidArgument{}})
    case Fail{error}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>, Fail{error})
    case Done{RemoteByteHandle{session}}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Done{RemoteByteHandle{session}})
    case Done{ByteHandle{raw}}:
      do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
        _closed : Result<&1, &1, RawByteDb.Error, Unit> <- RawByteDb.close(raw)
        return Fail{AlreadyExists{}}

def Bytes.create.options.probe(
  +path: String,
  options: ResourceOptions.Options
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
    opened : Result<&1, &1, Bytes.Error, Bytes.Handle> <-
      Bytes.open_existing_with_options(path, options)
    Bytes.create.options.probe.result(opened)

def Bytes.create.options.decision(
  +path: String,
  options: ResourceOptions.Options,
  is_default: Bool
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match is_default:
    case True{}: Bytes.create(path)
    case False{}: Bytes.create.options.probe(path, options)

def Bytes.create.options.validated(
  +path: String,
  decision: ResourceOptions.Decision
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  match decision:
    case ResourceOptions.Accepted{+options}:
      Bytes.create.options.decision(path, options,
        ResourceOptions.same(options, ResourceOptions.defaults()))
    case _: IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
      Fail{InvalidArgument{}})

def Bytes.create_with_options(
  +path: String,
  options: ResourceOptions.Options
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  Bytes.create.options.validated(path, ResourceOptions.validate(options))

def Bytes.open_existing_wait(
  +path: String,
  timeout_ms: U32,
  backoff_ms: U32
) -> IO(Result<&1, &1, Bytes.Error, Bytes.Handle>):
  do IO<Result<&1, &1, Bytes.Error, Bytes.Handle>>:
    opened : Result<&1, &1, RawByteDb.Error, RawByteDb.Handle> <-
      RawByteDb.open_existing(path)
    Bytes.owner.wait.candidate(path, timeout_ms, backoff_ms, opened)

def Bytes.put.result(
  pair: RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Unit>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>:
  match pair:
    case (raw, result): (ByteHandle{raw}, Bytes.error.result(result))

# Wraps the raw handle returned after committing one public byte batch.
def Bytes.write_batch.result(
  pair: RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Unit>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>:
  match pair:
    case (raw, result): (ByteHandle{raw}, Bytes.error.result(result))

# Commits a public binary batch as one WAL frame.
def Bytes.write_batch(
  handle: Bytes.Handle,
  mutations: List<&1, Bytes.Mutation>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match handle:
    case ByteHandle{raw}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Unit> <-
          RawByteDb.write_batch(raw, Bytes.mutations(mutations))
        return Bytes.write_batch.result(pair)
    case RemoteByteHandle{session}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit> <-
          OwnerByteClient.write_batch(session, Bytes.mutations(mutations))
        return Bytes.owner.unit.result(pair)

def Bytes.put(
  handle: Bytes.Handle,
  key: PackedBytes.Bytes,
  value: PackedBytes.Bytes
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match handle:
    case ByteHandle{raw}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Unit> <- RawByteDb.put(raw, key, value)
        return Bytes.put.result(pair)
    case RemoteByteHandle{session}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit> <-
          OwnerByteClient.put(session, key, value)
        return Bytes.owner.unit.result(pair)


def Bytes.get.result(
  pair: RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Maybe<&1, PackedBytes.Bytes>>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>:
  match pair:
    case (raw, result): (ByteHandle{raw}, Bytes.error.maybe(result))

def Bytes.delete.result(
  pair: RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Unit>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>:
  match pair:
    case (raw, result): (ByteHandle{raw}, Bytes.error.result(result))

def Bytes.get(
  handle: Bytes.Handle,
  key: PackedBytes.Bytes
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>):
  match handle:
    case ByteHandle{raw}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>>:
        pair : RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Maybe<&1, PackedBytes.Bytes>> <- RawByteDb.get(raw, key)
        return Bytes.get.result(pair)
    case RemoteByteHandle{session}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error,
        Maybe<&1, PackedBytes.Bytes>>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error,
          Maybe<&1, PackedBytes.Bytes>> <- OwnerByteClient.get(session, key)
        return Bytes.owner.get.result(pair)


def Bytes.delete(
  handle: Bytes.Handle,
  key: PackedBytes.Bytes
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match handle:
    case ByteHandle{raw}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Unit> <- RawByteDb.delete(raw, key)
        return Bytes.delete.result(pair)
    case RemoteByteHandle{session}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit> <-
          OwnerByteClient.delete(session, key)
        return Bytes.owner.unit.result(pair)

# Wraps the handle after publishing the durable byte SST snapshot.
def Bytes.flush.result(
  pair: RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Unit>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>:
  match pair:
    case (raw, result): (ByteHandle{raw}, Bytes.error.result(result))

# Publishes the current byte state to an authenticated SST file.
def Bytes.flush(handle: Bytes.Handle) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match handle:
    case ByteHandle{raw}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Unit> <- RawByteDb.flush(raw)
        return Bytes.flush.result(pair)
    case RemoteByteHandle{session}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit> <-
          OwnerByteClient.flush(session)
        return Bytes.owner.unit.result(pair)

# Publishes a canonical byte snapshot with tombstones removed.
def Bytes.compact(handle: Bytes.Handle) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match handle:
    case ByteHandle{raw}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, Unit> <- RawByteDb.compact(raw)
        return Bytes.flush.result(pair)
    case RemoteByteHandle{session}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit> <-
          OwnerByteClient.compact(session)
        return Bytes.owner.unit.result(pair)

def Bytes.stats.local(
  pair: RawByteDb.Handle & RawByteDb.Stats
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Stats>:
  match pair:
    case (raw, RawByteDb.Stats{entries, payload_bytes}):
      (ByteHandle{raw}, Done{ByteStats{entries, payload_bytes, 0n, 0n, 0n}})

def Bytes.stats.remote(
  pair:
    OwnerClient.Session & Result<&1, &1, OwnerClient.Error,
      OwnerStatsCodec.Stats>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Stats>:
  match pair:
    case (session, Fail{error}):
      (RemoteByteHandle{session}, Fail{Bytes.owner.error(error)})
    case (session, Done{OwnerStatsCodec.ByteStats{entries, payload_bytes, snapshots, retained_bytes, cursors}}):
      (RemoteByteHandle{session}, Done{ByteStats{entries, payload_bytes, snapshots, retained_bytes, cursors}})

def Bytes.stats(handle: Bytes.Handle) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Stats>):
  match handle:
    case ByteHandle{raw}:
      IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Stats>,
        Bytes.stats.local(RawByteDb.stats(raw)))
    case RemoteByteHandle{session}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Stats>>:
        pair : OwnerClient.Session &
          Result<&1, &1, OwnerClient.Error, OwnerStatsCodec.Stats> <-
            OwnerByteClient.stats(session)
        return Bytes.stats.remote(pair)

def Bytes.scan.from.snapshot(
  lower_pair: Maybe<&1, PackedBytes.Bytes> & Maybe<&1, PackedBytes.Bytes>,
  upper: Maybe<&1, PackedBytes.Bytes>,
  prefix: Maybe<&1, PackedBytes.Bytes>,
  snapshot: RawByteDb.Handle & List<&1, ByteMemTable.Entry>
) -> Bytes.Handle & Bytes.Cursor:
  match lower_pair:
    case (lower, seek_lower):
      match snapshot:
        case (next_raw, entries):
          (ByteHandle{next_raw}, ByteCursor{
            ByteRangeCursor.open(ByteRangeCursor.seek(entries, seek_lower)),
            ByteRangeCursor.Bounds{lower, upper, prefix}})

def Bytes.scan.raw(raw: RawByteDb.Handle, bounds: Bytes.ScanBounds) -> Bytes.Handle & Bytes.Cursor:
  match bounds:
    case ScanBounds{lower, upper, prefix}:
      Bytes.scan.from.snapshot(ByteMemTable.value.clone(lower), upper, prefix, RawByteDb.snapshot(raw))

def Bytes.snapshot.limit() -> Nat:
  Nat.mul(64n, 1048576n)

def Bytes.snapshot.raw(
  pair: RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, List<&1, ByteMemTable.Entry>>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>:
  match pair:
    case (raw, Fail{error}): (ByteHandle{raw}, Fail{Bytes.error(error)})
    case (raw, Done{entries}): (ByteHandle{raw}, Done{ByteSnapshot{entries}})

def Bytes.snapshot.remote.opened.sessions(
  sessions: OwnerClient.Session & OwnerClient.Session,
  snapshot_id: U32
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>:
  match sessions:
    case (handle_session, snapshot_session):
      (RemoteByteHandle{handle_session},
        Done{RemoteByteSnapshot{snapshot_session, snapshot_id}})

def Bytes.snapshot.remote.opened(
  pair: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>:
  match pair:
    case (session, Fail{error}):
      (RemoteByteHandle{session}, Fail{Bytes.owner.error(error)})
    case (session, Done{snapshot_id}):
      Bytes.snapshot.remote.opened.sessions(OwnerClient.session.clone(session),
        snapshot_id)

def Bytes.snapshot(handle: Bytes.Handle) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>):
  match handle:
    case ByteHandle{raw}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>>:
        pair : RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, List<&1, ByteMemTable.Entry>> <-
          RawByteDb.snapshot_limited(Bytes.snapshot.limit(), raw)
        return Bytes.snapshot.raw(pair)
    case RemoteByteHandle{session}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32> <-
          OwnerByteClient.snapshot.open(session)
        return Bytes.snapshot.remote.opened(pair)

def Bytes.snapshot.clone.local(
  entries: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Bytes.Snapshot & Bytes.Snapshot:
  match entries:
    case (first, second): (ByteSnapshot{first}, ByteSnapshot{second})

def Bytes.snapshot.clone.remote(
  +snapshot_id: U32,
  sessions: OwnerClient.Session & OwnerClient.Session
) -> Bytes.Snapshot & Bytes.Snapshot:
  match sessions:
    case (first, second):
      (RemoteByteSnapshot{first, snapshot_id},
        RemoteByteSnapshot{second, snapshot_id})

def Bytes.snapshot.clone(snapshot: Bytes.Snapshot) -> Bytes.Snapshot & Bytes.Snapshot:
  match snapshot:
    case ByteSnapshot{entries}:
      Bytes.snapshot.clone.local(ByteMemTable.entries.clone(entries))
    case RemoteByteSnapshot{session, +snapshot_id}:
      Bytes.snapshot.clone.remote(snapshot_id,
        OwnerClient.session.clone(session))

def Bytes.snapshot.cursor.ready(
  snapshot_entries: List<&1, ByteMemTable.Entry>,
  cursor_entries: List<&1, ByteMemTable.Entry>,
  lower: Maybe<&1, PackedBytes.Bytes> & Maybe<&1, PackedBytes.Bytes>,
  bounds: ByteRangeCursor.Bounds
) -> Bytes.Snapshot & Bytes.Cursor:
  match lower:
    case (seek_lower, retained_lower):
      match bounds:
        case ByteRangeCursor.Bounds{_, upper, prefix}:
          (ByteSnapshot{snapshot_entries}, ByteCursor{
            ByteRangeCursor.open(ByteRangeCursor.seek(cursor_entries, seek_lower)),
            ByteRangeCursor.Bounds{retained_lower, upper, prefix}})

def Bytes.snapshot.cursor.opened(
  entries: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  bounds: ByteRangeCursor.Bounds & ByteRangeCursor.Bounds
) -> Bytes.Snapshot & Bytes.Cursor:
  match entries:
    case (snapshot_entries, cursor_entries):
      match bounds:
        case (seek_bounds, retained_bounds):
          match seek_bounds:
            case ByteRangeCursor.Bounds{lower, _, _}:
              Bytes.snapshot.cursor.ready(snapshot_entries, cursor_entries,
                ByteMemTable.value.clone(lower), retained_bounds)

def Bytes.snapshot.cursor(
  entries: List<&1, ByteMemTable.Entry>,
  bounds: Bytes.ScanBounds
) -> Bytes.Snapshot & Bytes.Cursor:
  match bounds:
    case ScanBounds{lower, upper, prefix}:
      Bytes.snapshot.cursor.opened(
        ByteMemTable.entries.clone(entries),
        ByteRangeCursor.bounds.clone(ByteRangeCursor.Bounds{lower, upper, prefix}))

def Bytes.snapshot.cursor.result(
  pair: Bytes.Snapshot & Bytes.Cursor
) -> Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>:
  match pair:
    case (snapshot, cursor): (snapshot, Done{cursor})

def Bytes.snapshot.cursor.remote.sessions(
  +snapshot_id: U32,
  +cursor_id: U32,
  sessions: OwnerClient.Session & OwnerClient.Session
) -> Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>:
  match sessions:
    case (snapshot_session, cursor_session):
      (RemoteByteSnapshot{snapshot_session, snapshot_id},
        Done{ByteOwnerCursor{cursor_session, snapshot_id, cursor_id}})

def Bytes.snapshot.cursor.remote(
  snapshot_id: U32,
  pair: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32>
) -> Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>:
  match pair:
    case (session, Fail{error}):
      (RemoteByteSnapshot{session, snapshot_id}, Fail{Bytes.owner.error(error)})
    case (session, Done{cursor_id}):
      Bytes.snapshot.cursor.remote.sessions(snapshot_id, cursor_id,
        OwnerClient.session.clone(session))

def Bytes.snapshot.scan_range.local(
  snapshot: Bytes.Snapshot,
  lower: Maybe<&1, PackedBytes.Bytes>,
  upper: Maybe<&1, PackedBytes.Bytes>
) -> Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>:
  match snapshot:
    case ByteSnapshot{entries}:
      Bytes.snapshot.cursor.result(
        Bytes.snapshot.cursor(entries, ScanBounds{lower, upper, None{}}))
    case RemoteByteSnapshot{_, _}:
      (snapshot, Fail{UnsupportedOperation{}})

def Bytes.snapshot.scan_prefix.local(
  snapshot: Bytes.Snapshot,
  prefix: PackedBytes.Bytes
) -> Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>:
  match snapshot:
    case ByteSnapshot{entries}:
      Bytes.snapshot.cursor.result(Bytes.snapshot.cursor(entries,
        ScanBounds{None{}, None{}, Some{prefix}}))
    case RemoteByteSnapshot{_, _}:
      (snapshot, Fail{UnsupportedOperation{}})

def Bytes.snapshot.scan_range(
  snapshot: Bytes.Snapshot,
  lower: Maybe<&1, PackedBytes.Bytes>,
  upper: Maybe<&1, PackedBytes.Bytes>
) -> IO(Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  match snapshot:
    case ByteSnapshot{entries}:
      IO.pure(Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>,
        Bytes.snapshot.scan_range.local(snapshot, lower, upper))
    case RemoteByteSnapshot{session, +snapshot_id}:
      do IO<Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32> <-
          OwnerByteClient.snapshot.cursor.open.range(session, snapshot_id,
            lower, upper)
        return Bytes.snapshot.cursor.remote(snapshot_id, pair)

def Bytes.snapshot.scan_prefix(
  snapshot: Bytes.Snapshot,
  prefix: PackedBytes.Bytes
) -> IO(Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  match snapshot:
    case ByteSnapshot{entries}:
      IO.pure(Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>,
        Bytes.snapshot.scan_prefix.local(snapshot, prefix))
    case RemoteByteSnapshot{session, +snapshot_id}:
      do IO<Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32> <-
          OwnerByteClient.snapshot.cursor.open.prefix(session, snapshot_id, prefix)
        return Bytes.snapshot.cursor.remote(snapshot_id, pair)

def Bytes.snapshot.get.local.result(
  pair: ByteMemTable.Table & Maybe<&1, PackedBytes.Bytes>
) -> Bytes.Snapshot & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>:
  match pair:
    case (ByteMemTable.Table{entries}, value):
      (ByteSnapshot{entries}, Done{value})

def Bytes.snapshot.get.remote(
  snapshot_id: U32,
  pair: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Maybe<&1, PackedBytes.Bytes>>
) -> Bytes.Snapshot & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>:
  match pair:
    case (session, Fail{error}):
      (RemoteByteSnapshot{session, snapshot_id}, Fail{Bytes.owner.error(error)})
    case (session, Done{value}):
      (RemoteByteSnapshot{session, snapshot_id}, Done{value})

def Bytes.snapshot.get(
  snapshot: Bytes.Snapshot,
  key: PackedBytes.Bytes
) -> IO(Bytes.Snapshot & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>):
  match snapshot:
    case ByteSnapshot{entries}:
      IO.pure(Bytes.Snapshot & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>,
        Bytes.snapshot.get.local.result(ByteMemTable.get(
          ByteMemTable.Table{entries}, key)))
    case RemoteByteSnapshot{session, +snapshot_id}:
      do IO<Bytes.Snapshot & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>>:
        pair : OwnerClient.Session &
          Result<&1, &1, OwnerClient.Error, Maybe<&1, PackedBytes.Bytes>> <-
            OwnerByteClient.snapshot.get(session, snapshot_id, key)
        return Bytes.snapshot.get.remote(snapshot_id, pair)


def Bytes.snapshot.close.remote(
  pair: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit>
) -> Result<&1, &1, Bytes.Error, Unit>:
  match pair:
    case (_, Fail{error}): Fail{Bytes.owner.error(error)}
    case (_, Done{Unit{}}): Done{Unit{}}

def Bytes.snapshot.close(snapshot: Bytes.Snapshot) -> IO(Result<&1, &1, Bytes.Error, Unit>):
  match snapshot:
    case ByteSnapshot{_}:
      IO.pure(Result<&1, &1, Bytes.Error, Unit>, Done{Unit{}})
    case RemoteByteSnapshot{session, snapshot_id}:
      do IO<Result<&1, &1, Bytes.Error, Unit>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit> <-
          OwnerByteClient.snapshot.close(session, snapshot_id)
        return Bytes.snapshot.close.remote(pair)

def Bytes.backup.error(error: BackupCodec.Error) -> Bytes.Error:
  match error:
    case BackupCodec.UnsupportedPlatform{}: UnsupportedPlatform{}
    case BackupCodec.InvalidOrder{}: InvalidArgument{}
    case BackupCodec.ResourceLimit{}: ResourceLimit{}
    case BackupCodec.CodecFailure{}: Corruption{"backup encoder rejected the snapshot"}
    case BackupCodec.SourceFailure{code, message}: Io{code, message}

def Bytes.backup.started(
  handle: Bytes.Handle,
  result: Result<&1, &1, BackupCodec.Error, BackupCodec.Stream>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.BackupStream>:
  match result:
    case Fail{error}: (handle, Fail{Bytes.backup.error(error)})
    case Done{inner}: (handle, Done{ByteBackupStream{inner}})

def Bytes.backup.snapshot(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.BackupStream>:
  match pair:
    case (handle, Fail{error}): (handle, Fail{error})
    case (handle, Done{ByteSnapshot{entries}}):
      Bytes.backup.started(handle, BackupCodec.start(entries))
    case (handle, Done{RemoteByteSnapshot{_, _}}):
      (handle, Fail{UnsupportedOperation{}})

# Opens a stable logical export from one retained database snapshot.
def Bytes.backup(handle: Bytes.Handle) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.BackupStream>):
  match handle:
    case ByteHandle{_}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.BackupStream>>:
        snapshot : Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot> <-
          Bytes.snapshot(handle)
        return Bytes.backup.snapshot(snapshot)
    case RemoteByteHandle{session}:
      IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.BackupStream>,
        (RemoteByteHandle{session}, Fail{UnsupportedOperation{}}))

def Bytes.backup.next.result(
  result: Result<&1, &1, BackupCodec.Error, BackupCodec.Step>
) -> Result<&1, &1, Bytes.Error, Bytes.BackupStep>:
  match result:
    case Fail{error}: Fail{Bytes.backup.error(error)}
    case Done{BackupCodec.End{}}: Done{BackupEnd{}}
    case Done{BackupCodec.Chunk{stream, bytes}}:
      Done{BackupChunk{ByteBackupStream{stream}, bytes}}

# Produces one bounded checksummed backup chunk per call.
def Bytes.backup_next(stream: Bytes.BackupStream) -> Result<&1, &1, Bytes.Error, Bytes.BackupStep>:
  match stream:
    case ByteBackupStream{inner}:
      Bytes.backup.next.result(BackupCodec.next(inner))

def Bytes.backup_to.error(error: BackupIo.Error) -> Bytes.Error:
  match error:
    case BackupIo.AlreadyExists{}: AlreadyExists{}
    case BackupIo.UnsupportedPlatform{}: UnsupportedPlatform{}
    case BackupIo.ResourceLimit{}: ResourceLimit{}
    case BackupIo.Io{code, message}: Io{code, message}
    case BackupIo.CommitUnknown{code, message}: CommitUnknown{code, message}

def Bytes.backup_to.result(
  handle: Bytes.Handle,
  result: Result<&1, &1, BackupIo.Error, Unit>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>:
  match result:
    case Fail{error}: (handle, Fail{Bytes.backup_to.error(error)})
    case Done{Unit{}}: (handle, Done{Unit{}})

def Bytes.backup_to.opened(
  path: String,
  entries: Nat,
  fuel: Nat,
  pair: RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, VisibleByteCursor.Cursor>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match pair:
    case (raw, Fail{error}):
      IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>,
        (ByteHandle{raw}, Fail{Bytes.error(error)}))
    case (raw, Done{cursor}):
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        result : Result<&1, &1, BackupIo.Error, Unit> <-
          BackupCursorIo.export(path, cursor, entries, fuel)
        return Bytes.backup_to.result(ByteHandle{raw}, result)

def Bytes.backup_to.rooted(
  path: String,
  entries: Nat,
  fuel: Nat,
  pair:
    RawByteDb.Handle &
    Result<&1, &1, RawByteDb.Error, RawByteDb.SnapshotRoot>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match pair:
    case (raw, Fail{error}):
      IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>,
        (ByteHandle{raw}, Fail{Bytes.error(error)}))
    case (raw, Done{root}):
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        opened : Result<&1, &1, RawByteDb.Error, VisibleByteCursor.Cursor> <-
          RawByteDb.snapshot.root.cursor.open(root,
            ByteRangeCursor.Bounds{None{}, None{}, None{}})
        exported : Bytes.Handle & Result<&1, &1, Bytes.Error, Unit> <-
          Bytes.backup_to.opened(path, entries, fuel, (raw, opened))
        return exported

def Bytes.backup_to.budgeted(
  path: String,
  entries: Nat,
  pair: RawByteDb.Handle & Nat
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match pair:
    case (raw, fuel):
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        rooted : RawByteDb.Handle &
          Result<&1, &1, RawByteDb.Error, RawByteDb.SnapshotRoot> <-
            RawByteDb.snapshot_root_limited(67108864n, raw)
        Bytes.backup_to.rooted(path, entries, fuel, rooted)

def Bytes.backup_to.statsed(
  path: String,
  pair: RawByteDb.Handle & RawByteDb.Stats
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match pair:
    case (raw, RawByteDb.Stats{entries, _}):
      Bytes.backup_to.budgeted(path, entries,
        RawByteDb.scan.work_budget(raw))

def Bytes.backup_to.remote.failed(
  handle_session: OwnerClient.Session,
  snapshot_id: U32,
  session: OwnerClient.Session,
  error: OwnerClient.Error
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
    _closed : OwnerClient.Session &
      Result<&1, &1, OwnerClient.Error, Unit> <-
        OwnerByteClient.snapshot.close(session, snapshot_id)
    return (RemoteByteHandle{handle_session}, Fail{Bytes.owner.error(error)})

def Bytes.backup_to.remote.exported(
  handle_session: OwnerClient.Session,
  result: Result<&1, &1, BackupIo.Error, Unit>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>,
    Bytes.backup_to.result(RemoteByteHandle{handle_session}, result))

def Bytes.backup_to.remote.export.ready(
  path: String,
  handle_session: OwnerClient.Session,
  source: BackupOwnerCursorIo.OwnerSource,
  counts: U32 & U32
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match counts:
    case (entries, fuel_entries):
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        result : Result<&1, &1, BackupIo.Error, Unit> <-
          BackupOwnerCursorIo.export(path, source, U32.to_nat(entries),
            Nat.add(32n, Nat.mul(8n, U32.to_nat(fuel_entries))))
        Bytes.backup_to.remote.exported(handle_session, result)

def Bytes.backup_to.remote.export.ready.copies(
  path: String,
  handle_session: OwnerClient.Session,
  source: BackupOwnerCursorIo.OwnerSource,
  counts: U32 & U32 & U32
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match counts:
    case (entries, (fuel_entries, _)):
      Bytes.backup_to.remote.export.ready(path, handle_session, source,
        (entries, fuel_entries))

def Bytes.backup_to.remote.export.opened(
  path: String,
  handle_session: OwnerClient.Session,
  snapshot_id: U32,
  entry_count: U32,
  opened: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match opened:
    case (session, Fail{error}):
      Bytes.backup_to.remote.failed(handle_session, snapshot_id,
        session, error)
    case (session, Done{cursor_id}):
      Bytes.backup_to.remote.export.ready.copies(path, handle_session,
        BackupOwnerCursorIo.OwnerSource{session, snapshot_id,
          cursor_id, True{}},
        CoordinatorProtocol.u32.duplicate.triple(entry_count))

def Bytes.backup_to.remote.cursor.counted.result.copied(
  path: String,
  handle_session: OwnerClient.Session,
  snapshot_ids: U32 & U32 & U32,
  pair: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match snapshot_ids:
    case (failure_id, (open_id, export_id)):
      match pair:
        case (session, Fail{error}):
          Bytes.backup_to.remote.failed(handle_session, failure_id,
            session, error)
        case (session, Done{entry_count}):
          do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
            opened : OwnerClient.Session &
              Result<&1, &1, OwnerClient.Error, U32> <-
                OwnerByteClient.snapshot.cursor.open(session, open_id)
            Bytes.backup_to.remote.export.opened(path, handle_session,
              export_id, entry_count, opened)

def Bytes.backup_to.remote.cursor.counted.result(
  path: String,
  handle_session: OwnerClient.Session,
  snapshot_id: U32,
  pair: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  Bytes.backup_to.remote.cursor.counted.result.copied(path,
    handle_session,
    CoordinatorProtocol.u32.duplicate.triple(snapshot_id), pair)

def Bytes.backup_to.remote.cursor.counted(
  path: String,
  handle_session: OwnerClient.Session,
  snapshot_id: U32,
  opened: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match opened:
    case (session, Fail{error}):
      Bytes.backup_to.remote.failed(handle_session, snapshot_id,
        session, error)
    case (session, Done{cursor_id}):
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        counted : OwnerClient.Session &
          Result<&1, &1, OwnerClient.Error, U32> <-
            OwnerByteClient.snapshot.cursor.count(session, cursor_id)
        Bytes.backup_to.remote.cursor.counted.result(path, handle_session,
          snapshot_id, counted)

def Bytes.backup_to.remote.snapshot.cloned(
  path: String,
  sessions: OwnerClient.Session & OwnerClient.Session,
  snapshot_ids: U32 & U32 & U32
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match sessions:
    case (handle_session, owner_session):
      match snapshot_ids:
        case (count_id, (export_id, _)):
          do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
            opened_cursor : OwnerClient.Session &
              Result<&1, &1, OwnerClient.Error, U32> <-
                OwnerByteClient.snapshot.cursor.open(owner_session, count_id)
            Bytes.backup_to.remote.cursor.counted(path, handle_session,
              export_id, opened_cursor)

def Bytes.backup_to.remote.snapshot.opened(
  path: String,
  opened: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, U32>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match opened:
    case (session, Fail{error}):
      IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>,
        (RemoteByteHandle{session}, Fail{Bytes.owner.error(error)}))
    case (session, Done{snapshot_id}):
      Bytes.backup_to.remote.snapshot.cloned(path,
        OwnerClient.session.clone(session),
        CoordinatorProtocol.u32.duplicate.triple(snapshot_id))

def Bytes.backup_to.remote(
  path: String,
  session: OwnerClient.Session
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
    opened : OwnerClient.Session &
      Result<&1, &1, OwnerClient.Error, U32> <-
        OwnerByteClient.snapshot.open(session)
    Bytes.backup_to.remote.snapshot.opened(path, opened)

# Publishes one consistent byte snapshot as a checksummed backup bundle.
def Bytes.backup_to(
  path: String,
  handle: Bytes.Handle
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match handle:
    case ByteHandle{raw}:
      Bytes.backup_to.statsed(path, RawByteDb.stats(raw))
    case RemoteByteHandle{session}:
      Bytes.backup_to.remote(path, session)

def Bytes.restore.error(error: RestoreIo.Error) -> Bytes.Error:
  match error:
    case RestoreIo.InvalidFormat{}: Corruption{"invalid backup format"}
    case RestoreIo.ResourceLimit{}: ResourceLimit{}
    case RestoreIo.InvalidOrder{}: InvalidArgument{}
    case RestoreIo.ChecksumMismatch{}: Corruption{"backup checksum mismatch"}
    case RestoreIo.CountMismatch{}: Corruption{"backup entry count mismatch"}
    case RestoreIo.Storage{error}: Bytes.error(error)
    case RestoreIo.Io{code, message}: Io{code, message}
    case RestoreIo.DestinationExists{}: AlreadyExists{}
    case RestoreIo.TemporaryExists{}: AlreadyExists{}
    case RestoreIo.VerificationFailed{}: Corruption{"restored database verification failed"}
    case RestoreIo.CommitUnknown{code, message}: CommitUnknown{code, message}

def Bytes.restore.result(
  restored: Result<&1, &1, RestoreIo.Error, Unit>
) -> IO(Result<&1, &1, Bytes.Error, Unit>):
  match restored:
    case Fail{error}: IO.pure(Result<&1, &1, Bytes.Error, Unit>,
      Fail{Bytes.restore.error(error)})
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, Bytes.Error, Unit>, Done{Unit{}})

# Validates a complete exchange before building and atomically publishing a database.
def Bytes.restore(
  destination: String,
  input: PackedBytes.Bytes
) -> IO(Result<&1, &1, Bytes.Error, Unit>):
  do IO<Result<&1, &1, Bytes.Error, Unit>>:
    restored : Result<&1, &1, RestoreIo.Error, Unit> <-
      RestoreIo.restore(destination, input)
    converted : Result<&1, &1, Bytes.Error, Unit> <- Bytes.restore.result(restored)
    return converted

def Bytes.restore_from.result(
  restored: Result<&1, &1, RestoreIo.Error, Unit>
) -> IO(Result<&1, &1, Bytes.Error, Unit>):
  Bytes.restore.result(restored)

# Restores a published backup bundle containing its `BACKUP` exchange file.
def Bytes.restore_from(
  destination: String,
  bundle: String
) -> IO(Result<&1, &1, Bytes.Error, Unit>):
  do IO<Result<&1, &1, Bytes.Error, Unit>>:
    restored : Result<&1, &1, RestoreIo.Error, Unit> <-
      RestoreIo.restore_from(destination, bundle)
    converted : Result<&1, &1, Bytes.Error, Unit> <-
      Bytes.restore_from.result(restored)
    return converted

# Creates a stable ordered scan snapshot from the current visible byte keys.
def Bytes.snapshot.live_scan(handle: Bytes.Handle, bounds: Bytes.ScanBounds) -> Bytes.Handle & Bytes.Cursor:
  match handle:
    case ByteHandle{raw}:
      Bytes.scan.raw(raw, bounds)
    case RemoteByteHandle{session}:
      (RemoteByteHandle{session}, ByteFailureCursor{UnsupportedOperation{}})

def Bytes.snapshot.live_scan_range(
  handle: Bytes.Handle,
  lower: Maybe<&1, PackedBytes.Bytes>,
  upper: Maybe<&1, PackedBytes.Bytes>
) -> Bytes.Handle & Bytes.Cursor:
  Bytes.snapshot.live_scan(handle, ScanBounds{lower, upper, None{}})

def Bytes.scan_open.result(
  pair: RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, VisibleByteCursor.Cursor>
) -> Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>:
  match pair:
    case (raw, Fail{error}):
      (ByteHandle{raw}, Fail{Bytes.error(error)})
    case (raw, Done{cursor}):
      (ByteHandle{raw}, Done{ByteStreamCursor{cursor}})

def Bytes.scan_open.owned.failed(
  handle: Bytes.Handle,
  snapshot: Bytes.Snapshot,
  error: Bytes.Error
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>>:
    _closed : Result<&1, &1, Bytes.Error, Unit> <- Bytes.snapshot.close(snapshot)
    return (handle, Fail{error})

def Bytes.scan_open.owned.cursor(
  handle: Bytes.Handle,
  bounds: ByteRangeCursor.Bounds,
  opened: Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  match opened:
    case (snapshot, Fail{error}):
      Bytes.scan_open.owned.failed(handle, snapshot, error)
    case (snapshot, Done{cursor}):
      IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>,
        (handle, Done{ByteOwnedCursor{snapshot, cursor, bounds}}))

def Bytes.scan_open.owned.bounds(
  handle: Bytes.Handle,
  snapshot: Bytes.Snapshot,
  copies: ByteRangeCursor.Bounds & ByteRangeCursor.Bounds
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  match copies:
    case (ByteRangeCursor.Bounds{None{}, None{}, Some{prefix}}, retained):
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>>:
        opened : Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor> <-
          Bytes.snapshot.scan_prefix(snapshot, prefix)
        Bytes.scan_open.owned.cursor(handle, retained, opened)
    case (ByteRangeCursor.Bounds{lower, upper, _}, retained):
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>>:
        opened : Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor> <-
          Bytes.snapshot.scan_range(snapshot, lower, upper)
        Bytes.scan_open.owned.cursor(handle, retained, opened)

def Bytes.scan_open.owned.snapshot(
  opened: Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>,
  bounds: Bytes.ScanBounds
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  match opened:
    case (handle, Fail{error}):
      IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>,
        (handle, Fail{error}))
    case (handle, Done{snapshot}):
      match bounds:
        case ScanBounds{lower, upper, prefix}:
          Bytes.scan_open.owned.bounds(handle, snapshot,
            ByteRangeCursor.bounds.clone(ByteRangeCursor.Bounds{lower, upper, prefix}))

def Bytes.scan_open(
  handle: Bytes.Handle,
  bounds: Bytes.ScanBounds
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  match handle:
    case ByteHandle{raw}:
      match bounds:
        case ScanBounds{lower, upper, prefix}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>>:
            pair : RawByteDb.Handle & Result<&1, &1, RawByteDb.Error, VisibleByteCursor.Cursor> <-
              RawByteDb.scan.open(raw,
                ByteRangeCursor.Bounds{lower, upper, prefix})
            return Bytes.scan_open.result(pair)
    case RemoteByteHandle{session}:
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>>:
        opened : Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot> <-
          Bytes.snapshot(RemoteByteHandle{session})
        Bytes.scan_open.owned.snapshot(opened, bounds)


def Bytes.scan(
  handle: Bytes.Handle,
  bounds: Bytes.ScanBounds
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  Bytes.scan_open(handle, bounds)

def Bytes.scan_range(
  handle: Bytes.Handle,
  lower: Maybe<&1, PackedBytes.Bytes>,
  upper: Maybe<&1, PackedBytes.Bytes>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  Bytes.scan(handle, ScanBounds{lower, upper, None{}})

def Bytes.scan_prefix(
  handle: Bytes.Handle,
  prefix: PackedBytes.Bytes
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>):
  Bytes.scan(handle, ScanBounds{None{}, None{}, Some{prefix}})

def Bytes.stream.step.result(step: VisibleByteCursor.Step) -> Bytes.StreamStep:
  match step:
    case VisibleByteCursor.Item{ByteMemTable.Entry{key, Some{value}}, cursor}:
      StreamItem{key, value, ByteStreamCursor{cursor}}
    case VisibleByteCursor.Item{ByteMemTable.Entry{_, None{}}, cursor}:
      StreamSkip{ByteStreamCursor{cursor}}
    case VisibleByteCursor.Skip{cursor}:
      StreamSkip{ByteStreamCursor{cursor}}
    case VisibleByteCursor.End{}:
      StreamEnd{ByteStreamCursor{VisibleByteCursor.Ended{}}}
    case VisibleByteCursor.Error{error}:
      StreamFailure{Bytes.error(RawByteDb.scan.error(error)),
        ByteStreamCursor{VisibleByteCursor.Ended{}}}

def Bytes.snapshot.stream.step(step: Bytes.ScanStep) -> Bytes.StreamStep:
  match step:
    case ScanItem{key, value, cursor}: StreamItem{key, value, cursor}
    case ScanSkip{cursor}: StreamSkip{cursor}
    case ScanEnd{cursor}: StreamEnd{cursor}
    case ScanFailure{error, cursor}: StreamFailure{error, cursor}

def Bytes.owner.cursor.frame(
  +snapshot_id: U32,
  +cursor_id: U32,
  pair: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, OwnerCursorCodec.Frame>
) -> Bytes.StreamStep:
  match pair:
    case (session, Fail{error}):
      StreamFailure{Bytes.owner.error(error),
        ByteOwnerCursor{session, snapshot_id, cursor_id}}
    case (session, Done{OwnerCursorCodec.CursorEnd{}}):
      StreamEnd{ByteClosedCursor{}}
    case (session, Done{OwnerCursorCodec.CursorItem{key, value}}):
      StreamItem{key, value, ByteOwnerCursor{session, snapshot_id, cursor_id}}

def Bytes.scan_next.remote(
  session: OwnerClient.Session,
  +snapshot_id: U32,
  +cursor_id: U32
) -> IO(Bytes.StreamStep):
  do IO<Bytes.StreamStep>:
    pair : OwnerClient.Session &
      Result<&1, &1, OwnerClient.Error, OwnerCursorCodec.Frame> <-
        OwnerByteClient.snapshot.cursor.next(session, cursor_id)
    return Bytes.owner.cursor.frame(snapshot_id, cursor_id, pair)

def Bytes.scan_next_io.stream(cursor: VisibleByteCursor.Cursor) -> IO(Bytes.StreamStep):
  do IO<Bytes.StreamStep>:
    step : VisibleByteCursor.Step <- VisibleByteCursor.next(cursor)
    return Bytes.stream.step.result(step)

def Bytes.scan_close_io.result(
  result: Result<&1, &1, U32 & String, Unit>
) -> Result<&1, &1, Bytes.Error, Unit>:
  match result:
    case Fail{error}: Fail{Bytes.error(RawByteDb.scan.error(error))}
    case Done{Unit{}}: Done{Unit{}}

def Bytes.scan_close_io.stream(
  inner: VisibleByteCursor.Cursor
) -> IO(Result<&1, &1, Bytes.Error, Unit>):
  do IO<Result<&1, &1, Bytes.Error, Unit>>:
    closed : Result<&1, &1, U32 & String, Unit> <- VisibleByteCursor.close(inner)
    return Bytes.scan_close_io.result(closed)

def Bytes.scan_close(cursor: Bytes.Cursor) -> IO(Result<&1, &1, Bytes.Error, Unit>):
  match cursor:
    case ByteOwnedCursor{snapshot, inner, _}:
      do IO<Result<&1, &1, Bytes.Error, Unit>>:
        first : Result<&1, &1, Bytes.Error, Unit> <- Bytes.scan_close(inner)
        second : Result<&1, &1, Bytes.Error, Unit> <- Bytes.snapshot.close(snapshot)
        return CursorCleanupPolicy.combine(&1, Bytes.Error, first, second)
    case ByteStreamCursor{inner}:
      Bytes.scan_close_io.stream(inner)
    case ByteOwnerCursor{session, _, cursor_id}:
      do IO<Result<&1, &1, Bytes.Error, Unit>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit> <-
          OwnerByteClient.snapshot.cursor.close(session, cursor_id)
        return Bytes.snapshot.close.remote(pair)
    case ByteCursor{inner, _}:
      IO.pure(Result<&1, &1, Bytes.Error, Unit>, Done{Unit{}})
    case ByteClosedCursor{}:
      IO.pure(Result<&1, &1, Bytes.Error, Unit>, Done{Unit{}})
    case ByteFailureCursor{_}:
      IO.pure(Result<&1, &1, Bytes.Error, Unit>, Done{Unit{}})

def Bytes.scan_close_io(cursor: Bytes.Cursor) -> IO(Result<&1, &1, Bytes.Error, Unit>):
  Bytes.scan_close(cursor)

# Advances a byte scan by one matching item, filtered skip, or end marker.
def Bytes.scan_next.result(result: ByteRangeCursor.Step) -> Bytes.ScanStep:
  match result:
    case ByteRangeCursor.RangeItem{ByteMemTable.Entry{key, Some{value}}, next_inner, next_bounds}:
      ScanItem{key, value, ByteCursor{next_inner, next_bounds}}
    case ByteRangeCursor.RangeItem{ByteMemTable.Entry{_, None{}}, next_inner, next_bounds}:
      ScanSkip{ByteCursor{next_inner, next_bounds}}
    case ByteRangeCursor.RangeSkip{next_inner, next_bounds}:
      ScanSkip{ByteCursor{next_inner, next_bounds}}
    case ByteRangeCursor.RangeEnd{next_inner, next_bounds}:
      ScanEnd{ByteCursor{next_inner, next_bounds}}

def Bytes.scan_next.cloned(
  inner: ByteRangeCursor.Cursor,
  pair: ByteRangeCursor.Bounds & ByteRangeCursor.Bounds
) -> Bytes.ScanStep:
  match pair:
    case (read_bounds, retained_bounds):
      Bytes.scan_next.result(ByteRangeCursor.next(inner, (read_bounds, retained_bounds)))

def Bytes.snapshot.scan_next(cursor: Bytes.Cursor) -> Bytes.ScanStep:
  match cursor:
    case ByteCursor{inner, bounds}:
      Bytes.scan_next.cloned(inner, ByteRangeCursor.bounds.clone(bounds))
    case ByteOwnerCursor{_, _, _}:
      ScanFailure{UnsupportedOperation{}, ByteClosedCursor{}}
    case ByteFailureCursor{error}:
      ScanFailure{error, ByteClosedCursor{}}
    case _: ScanEnd{cursor}

# Advances a live byte cursor to a later inclusive lower bound.
def Bytes.snapshot.scan_seek(
  cursor: Bytes.Cursor,
  lower: Maybe<&1, PackedBytes.Bytes>
) -> Bytes.Cursor:
  match cursor:
    case ByteCursor{inner, bounds}:
      ByteCursor{ByteRangeCursor.seek.cursor(inner, lower), bounds}
    case ByteFailureCursor{_}: ByteClosedCursor{}
    case _: cursor

# Releases a scan cursor and its retained bounds explicitly.
def Bytes.snapshot.scan_close(cursor: Bytes.Cursor) -> Bytes.Cursor:
  match cursor:
    case ByteCursor{inner, bounds}:
      ByteCursor{ByteRangeCursor.close(inner), bounds}
    case ByteFailureCursor{_}: ByteClosedCursor{}
    case _: cursor

def Bytes.scan_next_io.snapshot(
  inner: ByteRangeCursor.Cursor,
  bounds: ByteRangeCursor.Bounds
) -> IO(Bytes.StreamStep):
  IO.pure(Bytes.StreamStep,
    Bytes.snapshot.stream.step(Bytes.snapshot.scan_next(ByteCursor{inner, bounds})))

def Bytes.scan_next.owned.item(
  snapshot: Bytes.Snapshot,
  inner: Bytes.Cursor,
  key: PackedBytes.Bytes,
  value: PackedBytes.Bytes,
  bounds: ByteRangeCursor.Bounds,
  matches: Bool
) -> Bytes.StreamStep:
  match matches:
    case True{}: StreamItem{key, value, ByteOwnedCursor{snapshot, inner, bounds}}
    case False{}: StreamSkip{ByteOwnedCursor{snapshot, inner, bounds}}

def Bytes.scan_next.owned.checked(
  snapshot: Bytes.Snapshot,
  inner: Bytes.Cursor,
  keys: PackedBytes.Bytes & PackedBytes.Bytes & PackedBytes.Bytes,
  value: PackedBytes.Bytes,
  copies: ByteRangeCursor.Bounds & ByteRangeCursor.Bounds
) -> Bytes.StreamStep:
  match keys:
    case (key, (range_key, prefix_key)):
      match copies:
        case (checked, retained):
          Bytes.scan_next.owned.item(snapshot, inner, key, value, retained,
            ByteRangeCursor.matches.key((range_key, prefix_key), checked))

def Bytes.scan_next.owned.ended(
  result: Result<&1, &1, Bytes.Error, Unit>
) -> Bytes.StreamStep:
  match result:
    case Done{Unit{}}: StreamEnd{ByteClosedCursor{}}
    case Fail{error}: StreamFailure{error, ByteClosedCursor{}}

def Bytes.scan_next.owned(
  snapshot: Bytes.Snapshot,
  bounds: ByteRangeCursor.Bounds,
  step: Bytes.StreamStep
) -> IO(Bytes.StreamStep):
  match step:
    case StreamItem{key, value, inner}:
      IO.pure(Bytes.StreamStep, Bytes.scan_next.owned.checked(snapshot, inner,
        ByteRangeCursor.key.copies.first(ByteMemTable.bytes.clone(key)), value,
        ByteRangeCursor.bounds.clone(bounds)))
    case StreamSkip{inner}:
      IO.pure(Bytes.StreamStep, StreamSkip{ByteOwnedCursor{snapshot, inner, bounds}})
    case StreamFailure{error, inner}:
      IO.pure(Bytes.StreamStep, StreamFailure{error, ByteOwnedCursor{snapshot, inner, bounds}})
    case StreamEnd{inner}:
      do IO<Bytes.StreamStep>:
        closed : Result<&1, &1, Bytes.Error, Unit> <-
          Bytes.scan_close(ByteOwnedCursor{snapshot, inner, bounds})
        return Bytes.scan_next.owned.ended(closed)

def Bytes.scan_next(cursor: Bytes.Cursor) -> IO(Bytes.StreamStep):
  match cursor:
    case ByteOwnedCursor{snapshot, inner, bounds}:
      do IO<Bytes.StreamStep>:
        step : Bytes.StreamStep <- Bytes.scan_next(inner)
        Bytes.scan_next.owned(snapshot, bounds, step)
    case ByteStreamCursor{inner}:
      Bytes.scan_next_io.stream(inner)
    case ByteOwnerCursor{session, snapshot_id, cursor_id}:
      Bytes.scan_next.remote(session, snapshot_id, cursor_id)
    case ByteCursor{inner, bounds}:
      Bytes.scan_next_io.snapshot(inner, bounds)
    case ByteClosedCursor{}:
      IO.pure(Bytes.StreamStep, StreamEnd{ByteClosedCursor{}})
    case ByteFailureCursor{error}:
      IO.pure(Bytes.StreamStep, StreamFailure{error, ByteClosedCursor{}})

def Bytes.scan_next_io(cursor: Bytes.Cursor) -> IO(Bytes.StreamStep):
  Bytes.scan_next(cursor)


def Bytes.scan_seek.remote(
  +snapshot_id: U32,
  +cursor_id: U32,
  pair: OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit>
) -> Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>:
  match pair:
    case (session, Fail{error}):
      (ByteOwnerCursor{session, snapshot_id, cursor_id},
        Fail{Bytes.owner.error(error)})
    case (session, Done{Unit{}}):
      (ByteOwnerCursor{session, snapshot_id, cursor_id}, Done{Unit{}})

def Bytes.scan_seek.ids(
  session: OwnerClient.Session,
  snapshot_id: U32,
  ids: U32 & U32,
  lower: Maybe<&1, PackedBytes.Bytes>
) -> IO(Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>):
  match ids:
    case (request_id, cursor_id):
      do IO<Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>>:
        pair : OwnerClient.Session & Result<&1, &1, OwnerClient.Error, Unit> <-
          OwnerByteClient.snapshot.cursor.seek(session, request_id, lower)
        return Bytes.scan_seek.remote(snapshot_id, cursor_id, pair)

def Bytes.scan_seek.owned(
  snapshot: Bytes.Snapshot,
  bounds: ByteRangeCursor.Bounds,
  pair: Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>
) -> Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>:
  match pair:
    case (inner, result): (ByteOwnedCursor{snapshot, inner, bounds}, result)


def Bytes.scan_seek(
  cursor: Bytes.Cursor,
  lower: Maybe<&1, PackedBytes.Bytes>
) -> IO(Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>):
  match cursor:
    case ByteOwnedCursor{snapshot, inner, bounds}:
      do IO<Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>>:
        pair : Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit> <-
          Bytes.scan_seek(inner, lower)
        return Bytes.scan_seek.owned(snapshot, bounds, pair)
    case ByteStreamCursor{inner}:
      IO.pure(Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>,
        (ByteStreamCursor{VisibleByteCursor.seek(inner, lower)}, Done{Unit{}}))
    case ByteOwnerCursor{session, snapshot_id, cursor_id}:
      Bytes.scan_seek.ids(session, snapshot_id,
        OwnerCursorCodec.u32.duplicate(cursor_id), lower)
    case ByteCursor{_, _}:
      IO.pure(Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>,
        (Bytes.snapshot.scan_seek(cursor, lower), Done{Unit{}}))
    case ByteClosedCursor{}:
      IO.pure(Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>,
        (ByteClosedCursor{}, Done{Unit{}}))
    case ByteFailureCursor{error}:
      IO.pure(Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>,
        (ByteClosedCursor{}, Fail{error}))


def Bytes.close.result(result: Result<&1, &1, RawByteDb.Error, Unit>) -> Result<&1, &1, Bytes.Error, Unit>:
  Bytes.error.result(result)

def Bytes.close(handle: Bytes.Handle) -> IO(Result<&1, &1, Bytes.Error, Unit>):
  match handle:
    case ByteHandle{raw}:
      do IO<Result<&1, &1, Bytes.Error, Unit>>:
        result : Result<&1, &1, RawByteDb.Error, Unit> <- RawByteDb.close(raw)
        return Bytes.close.result(result)
    case RemoteByteHandle{_}:
      IO.pure(Result<&1, &1, Bytes.Error, Unit>, Done{Unit{}})

type Utf8.Error is Type:
  Utf8Failure{inner: Bytes.Error}
  InvalidUtf8{}
  Utf8ResourceLimit{}
  Utf8InvalidArgument{}

def Utf8.error.from.failure(failure: Utf8CursorPolicy.Failure) -> Utf8.Error:
  match failure:
    case Utf8CursorPolicy.TextDecodeFailure{}: InvalidUtf8{}
    case Utf8CursorPolicy.ReaderFailure{}: Utf8Failure{Io{7, "scan reader previously failed"}}
    case Utf8CursorPolicy.ResourceFailure{}: Utf8ResourceLimit{}
    case Utf8CursorPolicy.ArgumentFailure{}: Utf8InvalidArgument{}

type Utf8.Handle is Type:
  Utf8Handle{inner: Bytes.Handle}

type Utf8.Mutation is Data:
  Utf8SetValue{key: String, value: String}
  Utf8DeleteKey{key: String}

type Utf8.Stats is Type:
  Utf8Stats{inner: Bytes.Stats}

type Utf8.CursorState is Type:
  Utf8CursorActive{}
  Utf8CursorEnded{}
  Utf8CursorFailed{failure: Utf8CursorPolicy.Failure}
  Utf8CursorClosed{}

type Utf8.Cursor is Type:
  Utf8Cursor{inner: Bytes.Cursor, state: Utf8.CursorState}

type Utf8.Snapshot is Type:
  Utf8Snapshot{inner: Bytes.Snapshot}

type Utf8.BackupStream is Type:
  Utf8BackupStream{inner: Bytes.BackupStream}

type Utf8.BackupStep is Type:
  Utf8BackupChunk{stream: Utf8.BackupStream, bytes: PackedBytes.Bytes}
  Utf8BackupEnd{}

type Utf8.ScanStep is Type:
  Utf8ScanItem{key: String, value: String, cursor: Utf8.Cursor}
  Utf8ScanSkip{cursor: Utf8.Cursor}
  Utf8ScanEnd{cursor: Utf8.Cursor}
  Utf8ScanFailure{error: Utf8.Error, cursor: Utf8.Cursor}

# Converts the internal manifest validation result to the public status.
def public_manifest_status(status: FormatInspect.Integrity) -> ManifestStatus:
  match status:
    case FormatInspect.Valid{}: ManifestValid{}
    case FormatInspect.UnsupportedVersion{generation}:
      ManifestVersionUnsupported{generation}
    case FormatInspect.UnsupportedComparator{generation}:
      ManifestComparatorUnsupported{generation}
    case FormatInspect.UnrecognizedFormat{}: ManifestFormatUnknown{}
    case FormatInspect.Corrupt{}: ManifestCorrupt{}
    case FormatInspect.ResourceLimit{}: ManifestResourceLimit{}

# Converts the internal format identity and validation into the public record.
def public_manifest_inspection(
  inspection: FormatInspect.Inspection
) -> ManifestInspection:
  match inspection:
    case FormatInspect.Inspection{identity, integrity}:
      match identity:
        case FormatInspect.Identity{package_version, storage_version, generation}:
          ManifestInspection{package_version, storage_version, generation,
            public_manifest_status(integrity)}

# Maps database lock failures to inspection-specific public errors.
def public_inspection_lock_error(error: DurableError.Error) -> InspectionError:
  match error:
    case DurableError.Error{DurableError.Busy{}, _, _, _, _}: InspectionBusy{}
    case DurableError.Error{DurableError.Timeout{}, _, _, _, _}: InspectionTimeout{}
    case DurableError.Error{DurableError.UnsupportedPlatform{}, _, _, _, _}:
      InspectionUnsupportedPlatform{}
    case DurableError.Error{_, _, _, code, message}: InspectionLockIo{code, message}

# Preserves inspection IO and lock errors while mapping valid inspection data.
def public_inspection_result(
  result: Result<&1, &1, FormatInspectIo.Error, FormatInspect.Inspection>
) -> Result<&1, &1, InspectionError, ManifestInspection>:
  match result:
    case Fail{FormatInspectIo.Lock{error}}:
      Fail{public_inspection_lock_error(error)}
    case Fail{FormatInspectIo.Host{code, message}}:
      Fail{InspectionIo{code, message}}
    case Fail{FormatInspectIo.ResourceLimit{}}:
      Fail{InspectionIo{7, "manifest exceeds inspection limit"}}
    case Done{inspection}: Done{public_manifest_inspection(inspection)}

# Reads format identity and integrity under the existing database lock.
def inspect(
  +dir: String
) ->
  IO(Result<&1, &1, InspectionError, ManifestInspection>):
  do IO<Result<&1, &1, InspectionError, ManifestInspection>>:
    result : Result<&1, &1, FormatInspectIo.Error, FormatInspect.Inspection> <-
      FormatInspectIo.inspect(dir)
    return public_inspection_result(result)

# Converts a verified 0.5.0.0 database into a new generation-four destination.
def migrate_legacy(
  source: String,
  destination: String
) -> IO(Result<&1, &1, MigrateRunIo.Error, Unit>):
  MigrateRunIo.migrate_legacy_source(source, destination)

def Utf8.encode.result(
  result: Result<&1, &1, U32 & String, PackedBytes.Bytes>
) -> Result<&1, &1, Utf8.Error, PackedBytes.Bytes>:
  match result:
    case Fail{_}: Fail{Utf8ResourceLimit{}}
    case Done{bytes}: Done{bytes}

def Utf8.encode(+text: String) -> Result<&1, &1, Utf8.Error, PackedBytes.Bytes>:
  Utf8.encode.result(Utf8Codec.from_string(text))

def Utf8.set_mutation_result(
  key: Result<&1, &1, Utf8.Error, PackedBytes.Bytes>,
  value: Maybe<&1, Result<&1, &1, Utf8.Error, PackedBytes.Bytes>>
) -> Result<&1, &1, Utf8.Error, Bytes.Mutation>:
  match key value:
    case Fail{error} _:
      Fail{error}
    case Done{_} Some{Fail{error}}:
      Fail{error}
    case Done{key_bytes} Some{Done{value_bytes}}:
      Done{BytesPut{key_bytes, value_bytes}}
    case Done{_} None{}:
      Fail{Utf8InvalidArgument{}}

def Utf8.delete_mutation_result(
  key: Result<&1, &1, Utf8.Error, PackedBytes.Bytes>,
  value: Maybe<&1, Result<&1, &1, Utf8.Error, PackedBytes.Bytes>>
) -> Result<&1, &1, Utf8.Error, Bytes.Mutation>:
  match key value:
    case Fail{error} _:
      Fail{error}
    case Done{_} Some{Fail{error}}:
      Fail{error}
    case Done{_} Some{Done{_}}:
      Fail{Utf8InvalidArgument{}}
    case Done{key_bytes} None{}:
      Done{BytesDelete{key_bytes}}

def Utf8.set_mutations_result(
  head: Result<&1, &1, Utf8.Error, Bytes.Mutation>,
  tail: Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>
) -> Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>:
  match head tail:
    case Fail{error} _:
      Fail{error}
    case Done{_} Fail{error}:
      Fail{error}
    case Done{mutation} Done{mutations}:
      Done{Con{mutation, mutations}}

def Utf8.delete_mutations_result(
  head: Result<&1, &1, Utf8.Error, Bytes.Mutation>,
  tail: Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>
) -> Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>:
  Utf8.set_mutations_result(head, tail)

def Utf8.encode_set_mutation(
  +key: String,
  +value: String,
  tail: Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>
) -> Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>:
  Utf8.set_mutations_result(
    Utf8.set_mutation_result(Utf8.encode(key), Some{Utf8.encode(value)}), tail)

def Utf8.encode_delete_mutation(
  +key: String,
  tail: Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>
) -> Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>:
  Utf8.delete_mutations_result(
    Utf8.delete_mutation_result(Utf8.encode(key), None{}), tail)

def Utf8.mutations(
  mutations: List<&1, Utf8.Mutation>
) -> Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>:
  match mutations:
    case Nil{}: Done{Nil{}}
    case Con{mutation, tail}:
      match mutation:
        case Utf8SetValue{key, value}:
          Utf8.encode_set_mutation(key, value, Utf8.mutations(tail))
        case Utf8DeleteKey{key}:
          Utf8.encode_delete_mutation(key, Utf8.mutations(tail))

def Utf8.open.result(
  result: Result<&1, &1, Bytes.Error, Bytes.Handle>
) -> Result<&1, &1, Utf8.Error, Utf8.Handle>:
  match result:
    case Fail{error}: Fail{Utf8Failure{error}}
    case Done{handle}: Done{Utf8Handle{handle}}

def Utf8.create(+path: String) -> IO(Result<&1, &1, Utf8.Error, Utf8.Handle>):
  do IO<Result<&1, &1, Utf8.Error, Utf8.Handle>>:
    result : Result<&1, &1, Bytes.Error, Bytes.Handle> <- Bytes.create(path)
    return Utf8.open.result(result)

def Utf8.create_with_options(
  +path: String,
  options: ResourceOptions.Options
) -> IO(Result<&1, &1, Utf8.Error, Utf8.Handle>):
  do IO<Result<&1, &1, Utf8.Error, Utf8.Handle>>:
    result : Result<&1, &1, Bytes.Error, Bytes.Handle> <-
      Bytes.create_with_options(path, options)
    return Utf8.open.result(result)

def Utf8.open_existing(+path: String) -> IO(Result<&1, &1, Utf8.Error, Utf8.Handle>):
  do IO<Result<&1, &1, Utf8.Error, Utf8.Handle>>:
    result : Result<&1, &1, Bytes.Error, Bytes.Handle> <- Bytes.open_existing(path)
    return Utf8.open.result(result)

def Utf8.open_existing_with_options(
  +path: String,
  options: ResourceOptions.Options
) -> IO(Result<&1, &1, Utf8.Error, Utf8.Handle>):
  do IO<Result<&1, &1, Utf8.Error, Utf8.Handle>>:
    result : Result<&1, &1, Bytes.Error, Bytes.Handle> <-
      Bytes.open_existing_with_options(path, options)
    return Utf8.open.result(result)

def Utf8.open_existing_wait(
  +path: String,
  timeout_ms: U32,
  backoff_ms: U32
) -> IO(Result<&1, &1, Utf8.Error, Utf8.Handle>):
  do IO<Result<&1, &1, Utf8.Error, Utf8.Handle>>:
    result : Result<&1, &1, Bytes.Error, Bytes.Handle> <- Bytes.open_existing_wait(path, timeout_ms, backoff_ms)
    return Utf8.open.result(result)

def Utf8.get.decode.result(
  handle: Bytes.Handle,
  result: Result<&1, &1, U32 & String, String>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Maybe<&2, String>>:
  match result:
    case Fail{_}: (Utf8Handle{handle}, Fail{InvalidUtf8{}})
    case Done{text}: (Utf8Handle{handle}, Done{Some{text}})

def Utf8.get.result(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Maybe<&2, String>>:
  match pair:
    case (handle, result):
      match result:
        case Fail{error}: (Utf8Handle{handle}, Fail{Utf8Failure{error}})
        case Done{None{}}: (Utf8Handle{handle}, Done{None{}})
        case Done{Some{bytes}}:
          Utf8.get.decode.result(handle, Utf8Codec.to_string_strict(bytes))

def Utf8.get.encoded(
  inner: Bytes.Handle,
  encoded: Result<&1, &1, Utf8.Error, PackedBytes.Bytes>
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Maybe<&2, String>>):
      match encoded:
        case Fail{error}:
          IO.pure(Utf8.Handle & Result<&1, &1, Utf8.Error, Maybe<&2, String>>,
            (Utf8Handle{inner}, Fail{error}))
        case Done{key_bytes}:
          do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Maybe<&2, String>>>:
            pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <- Bytes.get(inner, key_bytes)
            return Utf8.get.result(pair)

def Utf8.get(
  handle: Utf8.Handle,
  +key: String
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Maybe<&2, String>>):
  match handle:
    case Utf8Handle{inner}:
      Utf8.get.encoded(inner, Utf8.encode(key))

def Utf8.write.result(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>:
  match pair:
    case (handle, Fail{error}): (Utf8Handle{handle}, Fail{Utf8Failure{error}})
    case (handle, Done{Unit{}}): (Utf8Handle{handle}, Done{Unit{}})

def Utf8.write.encoded(
  inner: Bytes.Handle,
  encoded: Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>):
      match encoded:
        case Fail{error}:
          IO.pure(Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>,
            (Utf8Handle{inner}, Fail{error}))
        case Done{encoded}:
          do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>>:
            pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Unit> <- Bytes.write_batch(inner, encoded)
            return Utf8.write.result(pair)

def Utf8.write_batch(
  handle: Utf8.Handle,
  mutations: List<&1, Utf8.Mutation>
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>):
  match handle:
    case Utf8Handle{inner}:
      Utf8.write.encoded(inner, Utf8.mutations(mutations))

def Utf8.put(
  handle: Utf8.Handle,
  +key: String,
  +value: String
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>):
  Utf8.write_batch(handle, Con{Utf8SetValue{key, value}, Nil{}})

def Utf8.delete(
  handle: Utf8.Handle,
  +key: String
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>):
  Utf8.write_batch(handle, Con{Utf8DeleteKey{key}, Nil{}})

def Utf8.unit.result(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>:
  match pair:
    case (handle, Fail{error}): (Utf8Handle{handle}, Fail{Utf8Failure{error}})
    case (handle, Done{Unit{}}): (Utf8Handle{handle}, Done{Unit{}})

def Utf8.flush(handle: Utf8.Handle) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>):
  match handle:
    case Utf8Handle{inner}:
      do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>>:
        pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Unit> <- Bytes.flush(inner)
        return Utf8.unit.result(pair)

def Utf8.compact(handle: Utf8.Handle) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>):
  match handle:
    case Utf8Handle{inner}:
      do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>>:
        pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Unit> <- Bytes.compact(inner)
        return Utf8.unit.result(pair)

def Utf8.scan.bound.encoded(
  result: Result<&1, &1, Utf8.Error, PackedBytes.Bytes>
) -> Result<&1, &1, Utf8.Error, Maybe<&1, PackedBytes.Bytes>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{bytes}: Done{Some{bytes}}

def Utf8.scan.bound(
  bound: Maybe<&2, String>
) -> Result<&1, &1, Utf8.Error, Maybe<&1, PackedBytes.Bytes>>:
  match bound:
    case None{}: Done{None{}}
    case Some{text}:
      Utf8.scan.bound.encoded(Utf8.encode(text))

def Utf8.scan_seek.byte.result(
  pair: Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit>
) -> Bytes.Cursor & Result<&1, &1, Utf8.Error, Unit>:
  match pair:
    case (cursor, Fail{error}): (cursor, Fail{Utf8Failure{error}})
    case (cursor, Done{Unit{}}): (cursor, Done{Unit{}})

# Applies an already validated text seek bound to an active byte cursor.
def Utf8.scan_seek.active(
  inner: Bytes.Cursor,
  result: Result<&1, &1, Utf8.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Bytes.Cursor & Result<&1, &1, Utf8.Error, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Bytes.Cursor & Result<&1, &1, Utf8.Error, Unit>,
        (inner, Fail{error}))
    case Done{bound}:
      do IO<Bytes.Cursor & Result<&1, &1, Utf8.Error, Unit>>:
        pair : Bytes.Cursor & Result<&1, &1, Bytes.Error, Unit> <-
          Bytes.scan_seek(inner, bound)
        return Utf8.scan_seek.byte.result(pair)

def Utf8.scan_seek.failed(
  byte_cursor: Bytes.Cursor,
  error: Utf8.Error
) -> Utf8.Cursor & Result<&1, &1, Utf8.Error, Unit>:
  match error:
    case Utf8Failure{inner}:
      (Utf8Cursor{byte_cursor, Utf8CursorFailed{Utf8CursorPolicy.ReaderFailure{}}}, Fail{Utf8Failure{inner}})
    case InvalidUtf8{}:
      (Utf8Cursor{byte_cursor, Utf8CursorFailed{Utf8CursorPolicy.TextDecodeFailure{}}}, Fail{InvalidUtf8{}})
    case Utf8ResourceLimit{}:
      (Utf8Cursor{byte_cursor, Utf8CursorFailed{Utf8CursorPolicy.ResourceFailure{}}}, Fail{Utf8ResourceLimit{}})
    case Utf8InvalidArgument{}:
      (Utf8Cursor{byte_cursor, Utf8CursorFailed{Utf8CursorPolicy.ArgumentFailure{}}}, Fail{Utf8InvalidArgument{}})

def Utf8.scan_seek.result(
  pair: Bytes.Cursor & Result<&1, &1, Utf8.Error, Unit>
) -> Utf8.Cursor & Result<&1, &1, Utf8.Error, Unit>:
  match pair:
    case (inner, Fail{error}):
      Utf8.scan_seek.failed(inner, error)
    case (inner, Done{Unit{}}):
      (Utf8Cursor{inner, Utf8CursorActive{}}, Done{Unit{}})

# Seeks an active text cursor by UTF-8 key, preserving terminal cursors.
def Utf8.scan_seek(
  cursor: Utf8.Cursor,
  lower: Maybe<&2, String>
) -> IO(Utf8.Cursor & Result<&1, &1, Utf8.Error, Unit>):
  match cursor:
    case Utf8Cursor{inner, Utf8CursorActive{}}:
      do IO<Utf8.Cursor & Result<&1, &1, Utf8.Error, Unit>>:
        pair : Bytes.Cursor & Result<&1, &1, Utf8.Error, Unit> <-
          Utf8.scan_seek.active(inner, Utf8.scan.bound(lower))
        return Utf8.scan_seek.result(pair)
    case Utf8Cursor{inner, state}:
      IO.pure(Utf8.Cursor & Result<&1, &1, Utf8.Error, Unit>,
        (Utf8Cursor{inner, state}, Done{Unit{}}))

def Utf8.scan.range.opened(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>:
  match pair:
    case (handle, Fail{error}):
      (Utf8Handle{handle}, Fail{Utf8Failure{error}})
    case (handle, Done{cursor}):
      (Utf8Handle{handle}, Done{Utf8Cursor{cursor, Utf8CursorActive{}}})

def Utf8.scan.range.result(
  handle: Bytes.Handle,
  lower: Result<&1, &1, Utf8.Error, Maybe<&1, PackedBytes.Bytes>>,
  upper: Result<&1, &1, Utf8.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>):
  match lower upper:
    case Fail{error} _:
      IO.pure(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>,
        (Utf8Handle{handle}, Fail{error}))
    case Done{_} Fail{error}:
      IO.pure(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>,
        (Utf8Handle{handle}, Fail{error}))
    case Done{lower_bound} Done{upper_bound}:
      do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>>:
        pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor> <-
          Bytes.scan_range(handle, lower_bound, upper_bound)
        return Utf8.scan.range.opened(pair)

def Utf8.scan_range(
  handle: Utf8.Handle,
  lower: Maybe<&2, String>,
  upper: Maybe<&2, String>
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>):
  match handle:
    case Utf8Handle{inner}:
      Utf8.scan.range.result(inner,
        Utf8.scan.bound(lower), Utf8.scan.bound(upper))

def Utf8.scan.prefix.opened(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>:
  Utf8.scan.range.opened(pair)

def Utf8.scan.prefix.encoded(
  handle: Bytes.Handle,
  encoded: Result<&1, &1, Utf8.Error, PackedBytes.Bytes>
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>):
  match encoded:
    case Fail{error}:
      IO.pure(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>,
        (Utf8Handle{handle}, Fail{error}))
    case Done{prefix}:
      do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>>:
        pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Cursor> <-
          Bytes.scan_prefix(handle, prefix)
        return Utf8.scan.prefix.opened(pair)

def Utf8.scan_prefix(
  handle: Utf8.Handle,
  +prefix: String
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Cursor>):
  match handle:
    case Utf8Handle{inner}:
      Utf8.scan.prefix.encoded(inner, Utf8.encode(prefix))

def Utf8.scan.item.failed(
  cursor: Bytes.Cursor,
  error: Utf8.Error,
  failure: Utf8CursorPolicy.Failure
) -> Utf8.ScanStep:
  Utf8ScanFailure{error, Utf8Cursor{cursor, Utf8CursorFailed{failure}}}

def Utf8.scan.item.result(
  cursor: Bytes.Cursor,
  key: Result<&1, &1, U32 & String, String>,
  value: Result<&1, &1, U32 & String, String>
) -> Utf8.ScanStep:
  match key value:
    case Fail{_} _:
      Utf8.scan.item.failed(cursor, InvalidUtf8{}, Utf8CursorPolicy.TextDecodeFailure{})
    case Done{_} Fail{_}:
      Utf8.scan.item.failed(cursor, InvalidUtf8{}, Utf8CursorPolicy.TextDecodeFailure{})
    case Done{key_text} Done{value_text}:
      Utf8ScanItem{key_text, value_text, Utf8Cursor{cursor, Utf8CursorActive{}}}

def Utf8.scan.byte.step(step: Bytes.StreamStep) -> Utf8.ScanStep:
  match step:
    case StreamItem{key, value, cursor}:
      Utf8.scan.item.result(cursor,
        Utf8Codec.to_string_strict(key), Utf8Codec.to_string_strict(value))
    case StreamSkip{cursor}:
      Utf8ScanSkip{Utf8Cursor{cursor, Utf8CursorActive{}}}
    case StreamEnd{cursor}:
      Utf8ScanEnd{Utf8Cursor{cursor, Utf8CursorEnded{}}}
    case StreamFailure{error, cursor}:
      Utf8.scan.item.failed(cursor, Utf8Failure{error}, Utf8CursorPolicy.ReaderFailure{})

def Utf8.scan_next.failed.ready(
  inner: Bytes.Cursor,
  failures: Utf8CursorPolicy.Failure & Utf8CursorPolicy.Failure
) -> IO(Utf8.ScanStep):
  match failures:
    case (stored, returned):
      IO.pure(Utf8.ScanStep, Utf8ScanFailure{Utf8.error.from.failure(returned),
        Utf8Cursor{inner, Utf8CursorFailed{stored}}})

def Utf8.scan_next(cursor: Utf8.Cursor) -> IO(Utf8.ScanStep):
  match cursor:
    case Utf8Cursor{inner, Utf8CursorActive{}}:
      do IO<Utf8.ScanStep>:
        step : Bytes.StreamStep <- Bytes.scan_next(inner)
        return Utf8.scan.byte.step(step)
    case Utf8Cursor{_, Utf8CursorEnded{}}:
      IO.pure(Utf8.ScanStep, Utf8ScanEnd{cursor})
    case Utf8Cursor{inner, Utf8CursorFailed{failure}}:
      Utf8.scan_next.failed.ready(inner, Utf8CursorPolicy.duplicate(failure))
    case Utf8Cursor{_, Utf8CursorClosed{}}:
      IO.pure(Utf8.ScanStep, Utf8ScanEnd{cursor})

def Utf8.scan_close.result(
  result: Result<&1, &1, Bytes.Error, Unit>
) -> Utf8.Cursor & Result<&1, &1, Utf8.Error, Unit>:
  match result:
    case Fail{error}:
      (Utf8Cursor{ByteClosedCursor{}, Utf8CursorClosed{}}, Fail{Utf8Failure{error}})
    case Done{Unit{}}:
      (Utf8Cursor{ByteClosedCursor{}, Utf8CursorClosed{}}, Done{Unit{}})

def Utf8.scan_close(cursor: Utf8.Cursor) -> IO(Utf8.Cursor & Result<&1, &1, Utf8.Error, Unit>):
  match cursor:
    case Utf8Cursor{inner, _}:
      do IO<Utf8.Cursor & Result<&1, &1, Utf8.Error, Unit>>:
        closed : Result<&1, &1, Bytes.Error, Unit> <- Bytes.scan_close(inner)
        return Utf8.scan_close.result(closed)

def Utf8.stats.result(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Stats>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Stats>:
  match pair:
    case (next, Fail{error}):
      (Utf8Handle{next}, Fail{Utf8Failure{error}})
    case (next, Done{byte_stats}):
      (Utf8Handle{next}, Done{Utf8Stats{byte_stats}})

def Utf8.stats(handle: Utf8.Handle) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Stats>):
  match handle:
    case Utf8Handle{inner}:
      do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Stats>>:
        pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Stats> <-
          Bytes.stats(inner)
        return Utf8.stats.result(pair)

def Utf8.close.result(
  result: Result<&1, &1, Bytes.Error, Unit>
) -> Result<&1, &1, Utf8.Error, Unit>:
  match result:
    case Fail{error}: Fail{Utf8Failure{error}}
    case Done{Unit{}}: Done{Unit{}}

def Utf8.close(handle: Utf8.Handle) -> IO(Result<&1, &1, Utf8.Error, Unit>):
  match handle:
    case Utf8Handle{inner}:
      do IO<Result<&1, &1, Utf8.Error, Unit>>:
        result : Result<&1, &1, Bytes.Error, Unit> <- Bytes.close(inner)
        return Utf8.close.result(result)

def Utf8.snapshot.created(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Snapshot>:
  match pair:
    case (handle, Fail{error}):
      (Utf8Handle{handle}, Fail{Utf8Failure{error}})
    case (handle, Done{snapshot}):
      (Utf8Handle{handle}, Done{Utf8Snapshot{snapshot}})

def Utf8.snapshot(handle: Utf8.Handle) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Snapshot>):
  match handle:
    case Utf8Handle{inner}:
      do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.Snapshot>>:
        pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot> <-
          Bytes.snapshot(inner)
        return Utf8.snapshot.created(pair)

def Utf8.snapshot.get.decoded(
  snapshot: Bytes.Snapshot,
  result: Result<&1, &1, U32 & String, String>
) -> Utf8.Snapshot & Result<&1, &1, Utf8.Error, Maybe<&1, String>>:
  match result:
    case Fail{_}: (Utf8Snapshot{snapshot}, Fail{InvalidUtf8{}})
    case Done{text}: (Utf8Snapshot{snapshot}, Done{Some{text}})

def Utf8.snapshot.get.result(
  pair: Bytes.Snapshot & Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>>
) -> Utf8.Snapshot & Result<&1, &1, Utf8.Error, Maybe<&1, String>>:
  match pair:
    case (snapshot, Fail{error}): (Utf8Snapshot{snapshot}, Fail{Utf8Failure{error}})
    case (snapshot, Done{None{}}): (Utf8Snapshot{snapshot}, Done{None{}})
    case (snapshot, Done{Some{value}}):
      Utf8.snapshot.get.decoded(snapshot, Utf8Codec.to_string_strict(value))

def Utf8.snapshot.get.encoded(
  snapshot: Bytes.Snapshot,
  encoded: Result<&1, &1, Utf8.Error, PackedBytes.Bytes>
) -> IO(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Maybe<&1, String>>):
  match encoded:
    case Fail{error}:
      IO.pure(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Maybe<&1, String>>,
        (Utf8Snapshot{snapshot}, Fail{error}))
    case Done{key}:
      do IO<Utf8.Snapshot & Result<&1, &1, Utf8.Error, Maybe<&1, String>>>:
        pair : Bytes.Snapshot &
          Result<&1, &1, Bytes.Error, Maybe<&1, PackedBytes.Bytes>> <-
            Bytes.snapshot.get(snapshot, key)
        return Utf8.snapshot.get.result(pair)

def Utf8.snapshot.get(
  snapshot: Utf8.Snapshot,
  +key: String
) -> IO(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Maybe<&1, String>>):
  match snapshot:
    case Utf8Snapshot{inner}:
      Utf8.snapshot.get.encoded(inner, Utf8.encode(key))

def Utf8.snapshot.range.opened(
  pair: Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>
) -> Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>:
  match pair:
    case (snapshot, Fail{error}): (Utf8Snapshot{snapshot}, Fail{Utf8Failure{error}})
    case (snapshot, Done{cursor}):
      (Utf8Snapshot{snapshot}, Done{Utf8Cursor{cursor, Utf8CursorActive{}}})

def Utf8.snapshot.range.result(
  snapshot: Bytes.Snapshot,
  lower: Result<&1, &1, Utf8.Error, Maybe<&1, PackedBytes.Bytes>>,
  upper: Result<&1, &1, Utf8.Error, Maybe<&1, PackedBytes.Bytes>>
) -> IO(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>):
  match lower upper:
    case Fail{error} _:
      IO.pure(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>,
        (Utf8Snapshot{snapshot}, Fail{error}))
    case Done{_} Fail{error}:
      IO.pure(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>,
        (Utf8Snapshot{snapshot}, Fail{error}))
    case Done{lower_bound} Done{upper_bound}:
      do IO<Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>>:
        pair : Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor> <-
          Bytes.snapshot.scan_range(snapshot, lower_bound, upper_bound)
        return Utf8.snapshot.range.opened(pair)

def Utf8.snapshot.scan_range(
  snapshot: Utf8.Snapshot,
  lower: Maybe<&2, String>,
  upper: Maybe<&2, String>
) -> IO(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>):
  match snapshot:
    case Utf8Snapshot{inner}:
      Utf8.snapshot.range.result(inner, Utf8.scan.bound(lower), Utf8.scan.bound(upper))

def Utf8.snapshot.prefix.opened(
  pair: Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor>
) -> Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>:
  Utf8.snapshot.range.opened(pair)

def Utf8.snapshot.scan_prefix.encoded(
  snapshot: Bytes.Snapshot,
  encoded: Result<&1, &1, Utf8.Error, PackedBytes.Bytes>
) -> IO(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>):
  match encoded:
    case Fail{error}:
      IO.pure(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>,
        (Utf8Snapshot{snapshot}, Fail{error}))
    case Done{bytes}:
      do IO<Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>>:
        pair : Bytes.Snapshot & Result<&1, &1, Bytes.Error, Bytes.Cursor> <-
          Bytes.snapshot.scan_prefix(snapshot, bytes)
        return Utf8.snapshot.prefix.opened(pair)

def Utf8.snapshot.scan_prefix(
  snapshot: Utf8.Snapshot,
  +prefix: String
) -> IO(Utf8.Snapshot & Result<&1, &1, Utf8.Error, Utf8.Cursor>):
  match snapshot:
    case Utf8Snapshot{inner}:
      Utf8.snapshot.scan_prefix.encoded(inner, Utf8.encode(prefix))

def Utf8.snapshot.close(snapshot: Utf8.Snapshot) -> IO(Result<&1, &1, Utf8.Error, Unit>):
  match snapshot:
    case Utf8Snapshot{inner}:
      do IO<Result<&1, &1, Utf8.Error, Unit>>:
        result : Result<&1, &1, Bytes.Error, Unit> <- Bytes.snapshot.close(inner)
        return Utf8.close.result(result)

# Opens the same logical byte backup through the text facade.
def Utf8.backup.started(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.BackupStream>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.BackupStream>:
  match pair:
    case (handle, Fail{error}): (Utf8Handle{handle}, Fail{Utf8Failure{error}})
    case (handle, Done{inner}):
      (Utf8Handle{handle}, Done{Utf8BackupStream{inner}})

def Utf8.backup(handle: Utf8.Handle) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.BackupStream>):
  match handle:
    case Utf8Handle{inner}:
      do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Utf8.BackupStream>>:
        pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.BackupStream> <-
          Bytes.backup(inner)
        return Utf8.backup.started(pair)

def Utf8.backup.next.result(
  result: Result<&1, &1, Bytes.Error, Bytes.BackupStep>
) -> Result<&1, &1, Utf8.Error, Utf8.BackupStep>:
  match result:
    case Fail{error}: Fail{Utf8Failure{error}}
    case Done{BackupEnd{}}: Done{Utf8BackupEnd{}}
    case Done{BackupChunk{stream, bytes}}:
      Done{Utf8BackupChunk{Utf8BackupStream{stream}, bytes}}

# Emits raw backup chunks without attempting text decoding.
def Utf8.backup_next(stream: Utf8.BackupStream) -> Result<&1, &1, Utf8.Error, Utf8.BackupStep>:
  match stream:
    case Utf8BackupStream{inner}:
      Utf8.backup.next.result(Bytes.backup_next(inner))

def Utf8.backup_to.started(
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>:
  match pair:
    case (updated, Fail{error}):
      (Utf8Handle{updated}, Fail{Utf8Failure{error}})
    case (updated, Done{Unit{}}): (Utf8Handle{updated}, Done{Unit{}})

def Utf8.backup_to(
  path: String,
  handle: Utf8.Handle
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>):
  match handle:
    case Utf8Handle{inner}:
      do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, Unit>>:
        pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Unit> <-
          Bytes.backup_to(path, inner)
        return Utf8.backup_to.started(pair)
