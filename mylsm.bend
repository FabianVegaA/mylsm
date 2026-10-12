import Base
import ./src/Keys.bend as Keys
import ./src/MemTable.bend as MemTable
import ./src/SortedRun.bend as SortedRun
import ./src/Sstable.bend as Sstable
import ./src/SstFile.bend as SstFile
import ./src/Wal.bend as Wal
import ./src/Manifest.bend as Manifest
import ./src/MergeIter.bend as MergeIter
import ./src/Db.bend as Db
import ./src/Recover.bend as Recover
import ./src/DurableDb.bend as DurableDb
import ./src/DurableError.bend as DurableError
import ./src/DurableDbPolicy.bend as DurableDbPolicy
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
    case OwnerSocket.Host{code, message}: Io{code, message}

def Bytes.owner.error.io(error: OwnerIo.Error) -> Bytes.Error:
  match error:
    case OwnerIo.UnsupportedPlatform{}: UnsupportedPlatform{}
    case OwnerIo.Host{code, message}: Io{code, message}
    case _: Corruption{"owner response transport was invalid"}

def Bytes.owner.error.commit(error: OwnerIo.Error) -> Bytes.Error:
  match error:
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

def Bytes.remote.role(
  endpoint: String,
  generation: U32,
  role: OwnerPolicy.OpenRole
) -> Result<&1, &1, Bytes.Error, Bytes.Handle>:
  match role:
    case OwnerPolicy.ExistingOwnerClient{}:
      Done{RemoteByteHandle{OwnerClient.session.open(endpoint, generation)}}
    case OwnerPolicy.ReturnBusy{}: Fail{Busy{}}
    case OwnerPolicy.PropagateOpenFailure{}:
      Fail{Io{0, "owner role could not be established"}}
    case OwnerPolicy.LocalOwner{}: Fail{Busy{}}

def Bytes.endpoint.generation(
  endpoint: String,
  result: Result<&1, &1, OwnerGenerationIo.Error, U32>
) -> Result<&1, &1, Bytes.Error, Bytes.Handle>:
  match result:
    case Fail{OwnerGenerationIo.Host{code, message}}: Fail{Io{code, message}}
    case Fail{OwnerGenerationIo.Invalid{}}:
      Fail{Corruption{"owner generation is invalid"}}
    case Fail{OwnerGenerationIo.Exhausted{}}:
      Fail{Corruption{"owner generation is exhausted"}}
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
        return Bytes.endpoint.generation(endpoint, generation)
    case Done{False{}}:
      IO.pure(Result<&1, &1, Bytes.Error, Bytes.Handle>,
        Bytes.remote.role(endpoint, 0, OwnerPolicy.open.role(
          OwnerPolicy.LockBusy{}, OwnerPolicy.EndpointMissing{})))

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
      Bytes.owner.wait.endpoint.path(Bytes.endpoint.path.pair(canonical),
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

def Bytes.snapshot.get.result(
  pair: ByteMemTable.Table & Maybe<&1, PackedBytes.Bytes>
) -> Bytes.Snapshot & Maybe<&1, PackedBytes.Bytes>:
  match pair:
    case (ByteMemTable.Table{entries}, value): (ByteSnapshot{entries}, value)

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

def Bytes.backup_to.snapshot(
  path: String,
  pair: Bytes.Handle & Result<&1, &1, Bytes.Error, Bytes.Snapshot>
) -> IO(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>):
  match pair:
    case (handle, Fail{error}):
      IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>,
        (handle, Fail{error}))
    case (handle, Done{ByteSnapshot{entries}}):
      do IO<Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>>:
        result : Result<&1, &1, BackupIo.Error, Unit> <- BackupIo.export(path, entries)
        return Bytes.backup_to.result(handle, result)
    case (handle, Done{RemoteByteSnapshot{_, _}}):
      IO.pure(Bytes.Handle & Result<&1, &1, Bytes.Error, Unit>,
        (handle, Fail{UnsupportedOperation{}}))

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

def Bytes.snapshot.live_scan_prefix(
  handle: Bytes.Handle,
  prefix: PackedBytes.Bytes
) -> Bytes.Handle & Bytes.Cursor:
  Bytes.snapshot.live_scan(handle, ScanBounds{None{}, None{}, Some{prefix}})

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

type InMemory.Session<a, -A: Kind(a)> is Kind(a <&> &1):
  InMemorySession{run: Db.Db -> (Db.Db & A)}

# --- Level 2: part control (1:1 delegates) ---
def cmp(+s1: String, +s2: String) -> Cmp:
  Keys.cmp(s1, s2)

# Key equality: true exactly for identical strings.
def eq(+s1: String, +s2: String) -> Bool:
  Keys.eq(s1, s2)

# Empty MemTable: no entries, count zero.
def mem_empty() -> MemTable.MemTable:
  MemTable.empty()

# MemTable with one live version prepended (newest-first log).
def mem_put(tab: MemTable.MemTable, key: String, val: String) -> MemTable.MemTable:
  MemTable.put(tab, key, val)

# MemTable with one tombstone prepended; hides older versions on read.
def mem_del(tab: MemTable.MemTable, key: String) -> MemTable.MemTable:
  MemTable.del(tab, key)

# Newest-first read; a tombstone answers None and hides older versions.
def mem_get(tab: MemTable.MemTable, +key: String) -> Maybe<&2, String>:
  MemTable.get(tab, key)

# Number of log entries, live and tombstoned.
def mem_count(tab: MemTable.MemTable) -> Nat:
  MemTable.count(tab)

# Canonicalize newest-first entries into a strict ordered run.
def sort_newest(entries: List<&2, MemTable.Entry>) -> List<&2, MemTable.Entry>:
  SortedRun.sort_newest(entries)

# Range scan over a merged run: lo <= key < hi, tombstones dropped.
def range_scan(+merged: List<&2, MemTable.Entry>, lo: String, hi: String) -> List<&2, MemTable.Entry>:
  MergeIter.scan(merged, lo, hi)

# Build an SSTable, canonicalizing entries newest-first.
def sst_build(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Sstable.Table:
  Sstable.build(entries, level, est_keys)

# Build an SSTable trusting an already strict, unique run (no sorting).
def sst_from_sorted_unique(+entries: List<&2, MemTable.Entry>, level: Nat) -> Sstable.Table:
  Sstable.from_sorted_unique(entries, level)

# Build an SSTable from a sorted run with an explicit key estimate.
def sst_build_sorted(+entries: List<&2, MemTable.Entry>, level: Nat, est_keys: Nat) -> Sstable.Table:
  Sstable.build_sorted(entries, level, est_keys)

# Handle wal encode in the public module exports.
def wal_encode(batch: Wal.Batch) -> Result<&1, &1, Wal.Error, PackedBytes.Bytes>:
  Wal.encode_frame(batch)

# Handle wal decode in the public module exports.
def wal_decode(encoded: PackedBytes.Bytes) -> Result<&1, &1, Wal.Error, Wal.Batch>:
  Wal.decode_frame(encoded)

# Encode an SST as packed v3 bytes.
def sst_encode(
  +entries: List<&2, MemTable.Entry>,
  +level: U32
) -> Result<&1, &1, SstFile.Error, PackedBytes.Bytes>:
  SstFile.encode_file(entries, level)

# Parse packed v3 bytes with strict bounds and checksum verification.
def sst_parse(
  encoded: PackedBytes.Bytes
) -> Result<&1, &1, SstFile.Error, Sstable.Table>:
  SstFile.parse(encoded)

# Serialize a Manifest to its exact on-disk bytes.
def mfst_serialize(mfst: Manifest.Manifest) -> Result<&1, &1, Manifest.Error, PackedBytes.Bytes>:
  Manifest.serialize(mfst)

# Handle mfst parse in the public module exports.
def mfst_parse(encoded: PackedBytes.Bytes) -> Maybe<&2, Manifest.Manifest>:
  Manifest.parse(encoded)

def InMemory.Session.pure(a, -A: Kind(a), value: A) -> InMemory.Session<a, A>:
  InMemorySession{database => (database, value)}

def InMemory.Session.run(a, -A: Kind(a), session: InMemory.Session<a, A>, database: Db.Db) -> Db.Db & A:
  match session:
    case InMemorySession{run}: run(database)

def InMemory.Session.apply(
  a,
  -A: Kind(a),
  b,
  -B: Kind(b),
  pair: Db.Db & A,
  next: A -> InMemory.Session<b, B>
) -> Db.Db & B:
  match pair:
    case (database, value): InMemory.Session.run(b, B, next(value), database)

def InMemory.Session.bind(
  a,
  -A: Kind(a),
  -B: Kind(a),
  session: InMemory.Session<a, A>,
  next: A -> InMemory.Session<a, B>
) -> InMemory.Session<a, B>:
  InMemorySession{database => InMemory.Session.apply(a, A, a, B, InMemory.Session.run(a, A, session, database), next)}

def InMemory.open(+path: String) -> Db.Db:
  Db.open_db(path)

def InMemory.put_database(+database: Db.Db, +key: String, +value: String) -> Db.Db:
  match database:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db.apply_done(Db.apply_and_rotate(Con{Wal.Put{key, value}, Nil{}}, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

def InMemory.delete_database(+database: Db.Db, +key: String) -> Db.Db:
  match database:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db.apply_done(Db.apply_and_rotate(Con{Wal.Del{key}, Nil{}}, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

def InMemory.write_database_batch(+database: Db.Db, +mutations: List<&2, Wal.Mut>) -> Db.Db:
  match database:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db.apply_done(Db.apply_and_rotate(mutations, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

def InMemory.read_database(+database: Db.Db, +key: String) -> Db.Db & Maybe<&2, String>:
  Db.db_get_cached(database, key)

def InMemory.Session.put(+key: String, +value: String) -> InMemory.Session<&2, Unit>:
  InMemorySession{database => (InMemory.put_database(database, key, value), Unit{})}

def InMemory.Session.delete(+key: String) -> InMemory.Session<&2, Unit>:
  InMemorySession{database => (InMemory.delete_database(database, key), Unit{})}

def InMemory.Session.write_batch(+mutations: List<&2, Wal.Mut>) -> InMemory.Session<&2, Unit>:
  InMemorySession{database => (InMemory.write_database_batch(database, mutations), Unit{})}

def InMemory.Session.get(+key: String) -> InMemory.Session<&2, Maybe<&2, String>>:
  InMemorySession{database => InMemory.read_database(database, key)}

def InMemory.run_session(a, -A: Kind(a), database: Db.Db, session: InMemory.Session<a, A>) -> Db.Db & A:
  InMemory.Session.run(a, A, session, database)

def InMemory.value_of(a, -A: Kind(a), pair: Db.Db & A) -> A:
  match pair:
    case (database, value): value

# Recover a persisted database from its directory.
def open_recovering(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  Recover.open_db(dir)


# Lists the error categories exposed by the durable API.
type ErrorKind is Data:
  NotFoundError{}
  AlreadyExistsError{}
  BusyError{}
  TimeoutError{}
  InvalidArgumentError{}
  UnsupportedPlatformError{}
  UnsupportedFormatError{}
  CorruptionError{}
  ResourceLimitError{}
  IoError{}
  CommitUnknownError{}

# Carries structured error details for API callers.
type Error is Data:
  Error{kind: ErrorKind, operation: String, path: String, host_code: U32, host_message: String}

# Owns the database and its process lock.
type Handle is Type:
  Handle{inner: DurableDb.Handle}

# Carries failures from scoped session execution.
type SessionError is Data:
  OpenFailure{error: Error}
  OperationFailure{error: Error}
  CloseFailure{error: Error}
  OperationAndCloseFailure{operation_error: Error, close_error: Error}

# Holds durable operations that thread one owned handle.
type Session<a, -A: Kind(a)> is Kind(a <&> &1):
  Session{run: Handle -> IO(Handle & Result<&1, &1, Error, A>)}

# Reports database size, cache use, errors, and maintenance state.
type DurableStats is Data:
  DurableStats{active_bytes: Nat, wal_bytes: Nat, memtable_entries: Nat, memtable_payload_bytes: Nat, cache_entries: Nat, operation_errors: Nat, maintenance_blocked: Bool}

# Reports whether post-commit maintenance completed.
type MaintenanceStatus is Data:
  MaintenanceComplete{}
  MaintenancePending{error: Error}

# Reports maintenance status for a confirmed write.
type WriteOutcome is Data:
  WriteOutcome{maintenance: MaintenanceStatus}

# Describes a public key/value update or deletion.
type Mutation is Data:
  SetValue{key: String, value: String}
  DeleteKey{key: String}

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

# Converts a public mutation to the WAL representation.
def to_storage_mut(mutation: Mutation) -> Wal.Mut:
  match mutation:
    case SetValue{key, value}: Wal.Put{key, value}
    case DeleteKey{key}: Wal.Del{key}

# Converts each public mutation to its WAL representation.
def to_storage_muts(+mutations: List<&2, Mutation>) -> List<&2, Wal.Mut>:
  match mutations:
    case Nil{}: Nil{}
    case Con{mutation, tail}: Con{to_storage_mut(mutation), to_storage_muts(tail)}

# Maps internal error categories to the public error kind.
def public_error_kind(kind: DurableError.ErrorKind) -> ErrorKind:
  match kind:
    case DurableError.NotFound{}: NotFoundError{}
    case DurableError.AlreadyExists{}: AlreadyExistsError{}
    case DurableError.Busy{}: BusyError{}
    case DurableError.Timeout{}: TimeoutError{}
    case DurableError.InvalidArgument{}: InvalidArgumentError{}
    case DurableError.UnsupportedPlatform{}: UnsupportedPlatformError{}
    case DurableError.UnsupportedFormat{}: UnsupportedFormatError{}
    case DurableError.Corruption{}: CorruptionError{}
    case DurableError.ResourceLimit{}: ResourceLimitError{}
    case DurableError.Io{}: IoError{}
    case DurableError.CommitUnknown{}: CommitUnknownError{}

# Builds the public error while preserving its structured details.
def public_error(error: DurableError.Error) -> Error:
  match error:
    case DurableError.Error{kind, operation, path, host_code, host_message}:
      Error{public_error_kind(kind), operation, path, host_code, host_message}

# Converts an internal result to the public error type.
def public_error_result(result: Result<&1, &1, DurableError.Error, Unit>) -> Result<&1, &1, Error, Unit>:
  match result:
    case Fail{error}: Fail{public_error(error)}
    case Done{value}: Done{value}

# Converts a durable open result to the public handle.
def public_open_result(result: Result<&1, &1, DurableError.Error, DurableDb.Handle>) -> Result<&1, &1, Error, Handle>:
  match result:
    case Fail{error}: Fail{public_error(error)}
    case Done{handle}: Done{Handle{handle}}

# Creates a database and returns its owned durable handle.
def create(+dir: String) -> IO(Result<&1, &1, Error, Handle>):
  do IO<Result<&1, &1, Error, Handle>>:
    result : Result<&1, &1, DurableError.Error, DurableDb.Handle> <- DurableDb.create(dir)
    return public_open_result(result)

# Opens and recovers an existing database under its lock.
def open_existing(+dir: String) -> IO(Result<&1, &1, Error, Handle>):
  do IO<Result<&1, &1, Error, Handle>>:
    result : Result<&1, &1, DurableError.Error, DurableDb.Handle> <- DurableDb.open_existing(dir)
    return public_open_result(result)

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

# Opens an existing database with a bounded wait for its process lock.
def open_existing_wait(
  +dir: String,
  timeout_ms: U32,
  backoff_ms: U32
) -> IO(Result<&1, &1, Error, Handle>):
  do IO<Result<&1, &1, Error, Handle>>:
    result : Result<&1, &1, DurableError.Error, DurableDb.Handle> <-
      DurableDb.open_existing_wait(dir, timeout_ms, backoff_ms)
    return public_open_result(result)

# Converts an optional stored value and its error.
def public_maybe_result(
  result: Result<&1, &1, DurableError.Error, Maybe<&2, String>>,
) -> Result<&1, &1, Error, Maybe<&2, String>>:
  match result:
    case Fail{error}: Fail{public_error(error)}
    case Done{value}: Done{value}

# Converts a durable read result to the public value type.
def durable_get_result(
  pair: DurableDb.Handle & Result<&1, &1, DurableError.Error, Maybe<&2, String>>,
) -> Handle & Result<&1, &1, Error, Maybe<&2, String>>:
  match pair:
    case (handle, result): (Handle{handle}, public_maybe_result(result))

# Reads a key from the owned durable database handle.
def get(handle: Handle, +key: String) -> IO(Handle & Result<&1, &1, Error, Maybe<&2, String>>):
  match handle:
    case Handle{inner}:
      do IO<Handle & Result<&1, &1, Error, Maybe<&2, String>>>:
        pair : DurableDb.Handle & Result<&1, &1, DurableError.Error, Maybe<&2, String>> <- DurableDb.get(inner, key)
        return durable_get_result(pair)

# Maps internal maintenance state to its public status.
def public_maintenance(maintenance: DurableDb.Maintenance) -> MaintenanceStatus:
  match maintenance:
    case DurableDb.Maintained{}: MaintenanceComplete{}
    case DurableDb.Pending{error}: MaintenancePending{public_error(error)}

# Converts a confirmed write outcome to the public type.
def public_write_result(
  result: Result<&1, &1, DurableError.Error, DurableDb.WriteOutcome>,
) -> Result<&1, &1, Error, WriteOutcome>:
  match result:
    case Fail{error}: Fail{public_error(error)}
    case Done{DurableDb.WriteOutcome{maintenance}}: Done{WriteOutcome{public_maintenance(maintenance)}}

# Preserves maintenance status while converting write errors.
def durable_write_result(
  pair: DurableDb.Handle & Result<&1, &1, DurableError.Error, Unit>,
) -> Handle & Result<&1, &1, Error, Unit>:
  match pair:
    case (handle, result): (Handle{handle}, public_error_result(result))

# Converts a batch outcome while preserving handle ownership.
def durable_batch_result(
  pair: DurableDb.Handle & Result<&1, &1, DurableError.Error, DurableDb.WriteOutcome>,
) -> Handle & Result<&1, &1, Error, WriteOutcome>:
  match pair:
    case (handle, result): (Handle{handle}, public_write_result(result))

# Validates and commits a public mutation batch atomically.
def write_batch(handle: Handle, mutations: List<&2, Mutation>) -> IO(Handle & Result<&1, &1, Error, WriteOutcome>):
  match handle:
    case Handle{inner}:
      do IO<Handle & Result<&1, &1, Error, WriteOutcome>>:
        pair : DurableDb.Handle & Result<&1, &1, DurableError.Error, DurableDb.WriteOutcome> <- DurableDb.write_batch(inner, to_storage_muts(mutations))
        return durable_batch_result(pair)

# Writes one key and value through the durable handle.
def put(handle: Handle, +key: String, +value: String) -> IO(Handle & Result<&1, &1, Error, WriteOutcome>):
  match handle:
    case Handle{inner}:
      do IO<Handle & Result<&1, &1, Error, WriteOutcome>>:
        pair : DurableDb.Handle & Result<&1, &1, DurableError.Error, DurableDb.WriteOutcome> <- DurableDb.put(inner, key, value)
        return durable_batch_result(pair)

# Deletes one key through the durable handle.
def delete(handle: Handle, +key: String) -> IO(Handle & Result<&1, &1, Error, WriteOutcome>):
  match handle:
    case Handle{inner}:
      do IO<Handle & Result<&1, &1, Error, WriteOutcome>>:
        pair : DurableDb.Handle & Result<&1, &1, DurableError.Error, DurableDb.WriteOutcome> <- DurableDb.delete(inner, key)
        return durable_batch_result(pair)

# Flushes the durable handle and returns maintenance status.
def flush(handle: Handle) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match handle:
    case Handle{inner}:
      do IO<Handle & Result<&1, &1, Error, Unit>>:
        pair : DurableDb.Handle & Result<&1, &1, DurableError.Error, Unit> <- DurableDb.flush(inner)
        return durable_write_result(pair)

# Compacts the durable handle and returns maintenance status.
def compact(handle: Handle) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match handle:
    case Handle{inner}:
      do IO<Handle & Result<&1, &1, Error, Unit>>:
        pair : DurableDb.Handle & Result<&1, &1, DurableError.Error, Unit> <- DurableDb.compact(inner)
        return durable_write_result(pair)

# Maps internal counters to the public stats record.
def public_stats(result: Result<&1, &1, DurableError.Error, DurableDb.Stats>) -> Result<&1, &1, Error, DurableStats>:
  match result:
    case Fail{error}: Fail{public_error(error)}
    case Done{DurableDb.Stats{active_bytes, wal_bytes, memtable_entries, memtable_payload_bytes, cache_entries, operation_errors, state}}:
      match state:
        case DurableDbPolicy.MaintenanceBlocked{}: Done{DurableStats{active_bytes, wal_bytes, memtable_entries, memtable_payload_bytes, cache_entries, operation_errors, True{}}}
        case _: Done{DurableStats{active_bytes, wal_bytes, memtable_entries, memtable_payload_bytes, cache_entries, operation_errors, False{}}}

# Converts durable stats errors to the public error type.
def durable_stats_result(
  pair: DurableDb.Handle & Result<&1, &1, DurableError.Error, DurableDb.Stats>,
) -> Handle & Result<&1, &1, Error, DurableStats>:
  match pair:
    case (handle, result): (Handle{handle}, public_stats(result))

# Reads bounded operational stats from the durable handle.
def stats(handle: Handle) -> IO(Handle & Result<&1, &1, Error, DurableStats>):
  match handle:
    case Handle{inner}:
      do IO<Handle & Result<&1, &1, Error, DurableStats>>:
        pair : DurableDb.Handle & Result<&1, &1, DurableError.Error, DurableDb.Stats> <- DurableDb.stats(inner)
        return durable_stats_result(pair)

# Closes the durable handle and releases its database lock.
def close(handle: Handle) -> IO(Result<&1, &1, Error, Unit>):
  match handle:
    case Handle{inner}:
      do IO<Result<&1, &1, Error, Unit>>:
        result : Result<&1, &1, DurableError.Error, Unit> <- DurableDb.close(inner)
        return public_error_result(result)

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

def Utf8.mutation.result(
  mutation: Utf8.Mutation,
  key: Result<&1, &1, Utf8.Error, PackedBytes.Bytes>,
  value: Maybe<&1, Result<&1, &1, Utf8.Error, PackedBytes.Bytes>>
) -> Result<&1, &1, Utf8.Error, Bytes.Mutation>:
  match mutation:
    case Utf8SetValue{_, _}:
      Utf8.set_mutation_result(key, value)
    case Utf8DeleteKey{_}:
      Utf8.delete_mutation_result(key, value)

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

def Utf8.open_existing(+path: String) -> IO(Result<&1, &1, Utf8.Error, Utf8.Handle>):
  do IO<Result<&1, &1, Utf8.Error, Utf8.Handle>>:
    result : Result<&1, &1, Bytes.Error, Bytes.Handle> <- Bytes.open_existing(path)
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
) -> Utf8.Handle & Result<&1, &1, Utf8.Error, WriteOutcome>:
  match pair:
    case (handle, Fail{error}): (Utf8Handle{handle}, Fail{Utf8Failure{error}})
    case (handle, Done{Unit{}}): (Utf8Handle{handle}, Done{WriteOutcome{MaintenanceComplete{}}})

def Utf8.write.encoded(
  inner: Bytes.Handle,
  encoded: Result<&1, &1, Utf8.Error, List<&1, Bytes.Mutation>>
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, WriteOutcome>):
      match encoded:
        case Fail{error}:
          IO.pure(Utf8.Handle & Result<&1, &1, Utf8.Error, WriteOutcome>,
            (Utf8Handle{inner}, Fail{error}))
        case Done{encoded}:
          do IO<Utf8.Handle & Result<&1, &1, Utf8.Error, WriteOutcome>>:
            pair : Bytes.Handle & Result<&1, &1, Bytes.Error, Unit> <- Bytes.write_batch(inner, encoded)
            return Utf8.write.result(pair)

def Utf8.write_batch(
  handle: Utf8.Handle,
  mutations: List<&1, Utf8.Mutation>
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, WriteOutcome>):
  match handle:
    case Utf8Handle{inner}:
      Utf8.write.encoded(inner, Utf8.mutations(mutations))

def Utf8.put(
  handle: Utf8.Handle,
  +key: String,
  +value: String
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, WriteOutcome>):
  Utf8.write_batch(handle, Con{Utf8SetValue{key, value}, Nil{}})

def Utf8.delete(
  handle: Utf8.Handle,
  +key: String
) -> IO(Utf8.Handle & Result<&1, &1, Utf8.Error, WriteOutcome>):
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

def Utf8.scan.opened(pair: Bytes.Handle & Bytes.Cursor) -> Utf8.Handle & Utf8.Cursor:
  match pair:
    case (handle, cursor):
      (Utf8Handle{handle}, Utf8Cursor{cursor, Utf8CursorActive{}})

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

def Utf8.scan_next.result(pair: Utf8.Cursor & Bytes.StreamStep) -> Utf8.ScanStep:
  match pair:
    case (Utf8Cursor{_, Utf8CursorActive{}}, step): Utf8.scan.byte.step(step)
    case (cursor, _): Utf8ScanEnd{cursor}

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

def Session.pure(a, -A: Kind(a), value: A) -> Session<a, A>:
  Session{handle => IO.pure(Handle & Result<&1, &1, Error, A>, (handle, Done{value}))}

def Session.run(a, -A: Kind(a), session: Session<a, A>, handle: Handle) -> IO(Handle & Result<&1, &1, Error, A>):
  match session:
    case Session{run}: run(handle)

def Session.bind_result(
  a,
  -A: Kind(a),
  -B: Kind(a),
  pair: Handle & Result<&1, &1, Error, A>,
  next: A -> Session<a, B>
) -> IO(Handle & Result<&1, &1, Error, B>):
  match pair:
    case (handle, Fail{error}):
      IO.pure(Handle & Result<&1, &1, Error, B>, (handle, Fail{error}))
    case (handle, Done{value}):
      Session.run(a, B, next(value), handle)

def Session.bind(a, -A: Kind(a), -B: Kind(a), session: Session<a, A>, next: A -> Session<a, B>) -> Session<a, B>:
  Session{handle =>
    do IO<Handle & Result<&1, &1, Error, B>>:
      pair : Handle & Result<&1, &1, Error, A> <- Session.run(a, A, session, handle)
      Session.bind_result(a, A, B, pair, next)
  }

def Session.put(+key: String, +value: String) -> Session<&2, WriteOutcome>:
  Session{handle => put(handle, key, value)}

def Session.delete(+key: String) -> Session<&2, WriteOutcome>:
  Session{handle => delete(handle, key)}

def Session.write_batch(mutations: List<&2, Mutation>) -> Session<&2, WriteOutcome>:
  Session{handle => write_batch(handle, mutations)}

def Session.get(+key: String) -> Session<&2, Maybe<&2, String>>:
  Session{handle => get(handle, key)}

def Session.flush() -> Session<&2, Unit>:
  Session{handle => flush(handle)}

def Session.compact() -> Session<&2, Unit>:
  Session{handle => compact(handle)}

def Session.stats() -> Session<&2, DurableStats>:
  Session{handle => stats(handle)}

def Session.finish_result(
  a,
  -A: Kind(a),
  result: Result<&1, &1, Error, A>,
  close_result: Result<&1, &1, Error, Unit>
) -> Result<&1, &1, SessionError, A>:
  match result close_result:
    case Done{value} Done{Unit{}}: Done{value}
    case Fail{error} Done{Unit{}}: Fail{OperationFailure{error}}
    case Done{_} Fail{error}: Fail{CloseFailure{error}}
    case Fail{operation_error} Fail{close_error}:
      Fail{OperationAndCloseFailure{operation_error, close_error}}

def Session.finish(
  a,
  -A: Kind(a),
  handle: Handle,
  result: Result<&1, &1, Error, A>
) -> IO(Result<&1, &1, SessionError, A>):
  do IO<Result<&1, &1, SessionError, A>>:
    close_result : Result<&1, &1, Error, Unit> <- close(handle)
    return Session.finish_result(a, A, result, close_result)

def Session.finish_pair(
  a,
  -A: Kind(a),
  pair: Handle & Result<&1, &1, Error, A>
) -> IO(Result<&1, &1, SessionError, A>):
  match pair:
    case (handle, result): Session.finish(a, A, handle, result)

def Session.run_opened(
  a,
  -A: Kind(a),
  opened: Result<&1, &1, Error, Handle>,
  session: Session<a, A>
) -> IO(Result<&1, &1, SessionError, A>):
  match opened:
    case Fail{error}:
      IO.pure(Result<&1, &1, SessionError, A>, Fail{OpenFailure{error}})
    case Done{handle}:
      do IO<Result<&1, &1, SessionError, A>>:
        pair : Handle & Result<&1, &1, Error, A> <- Session.run(a, A, session, handle)
        Session.finish_pair(a, A, pair)

# Runs a program and returns its still-owned handle.
def run_session(a, -A: Kind(a), handle: Handle, session: Session<a, A>) -> IO(Handle & Result<&1, &1, Error, A>):
  Session.run(a, A, session, handle)

# Creates, runs, and closes a scoped durable session.
def create_database(a, -A: Kind(a), +path: String, session: Session<a, A>) -> IO(Result<&1, &1, SessionError, A>):
  do IO<Result<&1, &1, SessionError, A>>:
    opened : Result<&1, &1, Error, Handle> <- create(path)
    Session.run_opened(a, A, opened, session)

# Opens, runs, and closes a scoped durable session.
def open_database(a, -A: Kind(a), +path: String, session: Session<a, A>) -> IO(Result<&1, &1, SessionError, A>):
  do IO<Result<&1, &1, SessionError, A>>:
    opened : Result<&1, &1, Error, Handle> <- open_existing(path)
    Session.run_opened(a, A, opened, session)

# Checks whether the public error means the path exists.
def error_is_already_exists(error: Error) -> Bool:
  match error:
    case Error{AlreadyExistsError{}, _, _, _, _}: True{}
    case _: False{}

# Checks whether the public error means the database is locked.
def error_is_busy(error: Error) -> Bool:
  match error:
    case Error{BusyError{}, _, _, _, _}: True{}
    case _: False{}

# Checks whether lock acquisition exceeded its requested timeout.
def error_is_timeout(error: Error) -> Bool:
  match error:
    case Error{TimeoutError{}, _, _, _, _}: True{}
    case _: False{}
