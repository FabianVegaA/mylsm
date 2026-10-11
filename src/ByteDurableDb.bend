import Base
import ./ByteMemTable.bend as ByteMemTable
import ./ByteManifest.bend as ByteManifest
import ./ByteManifestIo.bend as ByteManifestIo
import ./ByteSstFile.bend as ByteSstFile
import ./ByteSstIo.bend as ByteSstIo
import ./ByteWal.bend as ByteWal
import ./ByteWalIo.bend as ByteWalIo
import ./DbLock.bend as DbLock
import ./DurableError.bend as DurableError
import ./DurableBatchPolicy.bend as BatchPolicy
import ./coordinator/QueuePolicy.bend as QueuePolicy
import ./Fs.bend as Fs
import ./Keys.bend as Keys
import ./scan/Cursor.bend as Cursor
import ./scan/Snapshot.bend as SnapshotPolicy
import ./scan/ByteBlockReader.bend as ByteBlockReader
import ./scan/SstCursor.bend as SstCursor
import ./scan/RangeCursor.bend as RangeCursor
import ./scan/VisibleCursor.bend as VisibleCursor
import ./scan/VisibleStats.bend as VisibleStats
import ./CrashPoint.bend as CrashPoint
import ./scan/ScanWorkPolicy.bend as ScanWorkPolicy
import ./ByteRecoveryPolicy.bend as RecoveryPolicy
import ./Wal.bend as Wal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Reports byte-database lifecycle, validation, storage, and uncertain-commit failures.
type Error is Data:
  Busy{}
  Timeout{}
  NotFound{}
  AlreadyExists{}
  InvalidArgument{}
  UnsupportedPlatform{}
  ResourceLimit{}
  Corruption{message: String}
  Io{code: U32, message: String}
  CommitUnknown{code: U32, message: String}

# Prevents writes after a sync failure leaves commit status unknown.
type HandleState is Data:
  Open{}
  Poisoned{}

# Owns one exclusive database lock and the recovered byte mutation table.
type Handle is Type:
  Handle{path: String, lock: DbLock.Lock, table: ByteMemTable.Table,
    state: HandleState, base_stats: VisibleStats.Stats}

# Retains one immutable SST generation and an owned copy of the active delta.
type SnapshotRoot is Type:
  SnapshotRoot{sst_path: Maybe<&1, String>, delta: List<&1, ByteMemTable.Entry>}

# Reports canonical byte entry count and payload size.
type Stats is Data:
  Stats{entries: Nat, payload_bytes: Nat}

# Carries normalized mutations and the visible base totals before WAL append.
type BatchPrepared is Type:
  Prepared{mutations: List<&1, ByteWal.Mutation>, base_stats: VisibleStats.Stats}

# Tracks unique-key reconciliation against SST-backed visible statistics.
type BatchStatsState is Type:
  BatchNeed{handle: Handle, mutations: List<&1, ByteWal.Mutation>,
    entries: List<&1, ByteMemTable.Entry>, original_stats: VisibleStats.Stats,
    base_stats: VisibleStats.Stats}
  BatchRead{pair: Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
    mutations: List<&1, ByteWal.Mutation>, entries: List<&1, ByteMemTable.Entry>,
    original_stats: VisibleStats.Stats, base_stats: VisibleStats.Stats,
    key_bytes: Nat}
  BatchProbe{handle: Handle, mutations: List<&1, ByteWal.Mutation>,
    entries: List<&1, ByteMemTable.Entry>, original_stats: VisibleStats.Stats,
    base_stats: VisibleStats.Stats, key_bytes: Nat,
    key: Bytes.Bytes,
    result: ByteMemTable.Table & ByteMemTable.Probe}
  BatchKey{handle: Handle, mutations: List<&1, ByteWal.Mutation>,
    entries: List<&1, ByteMemTable.Entry>, original_stats: VisibleStats.Stats,
    base_stats: VisibleStats.Stats,
    keys: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes}

# Replays normalized mutations into a replacement byte table.
type BatchBuildState is Type:
  BatchBuild{mutations: List<&1, ByteWal.Mutation>,
    table: ByteMemTable.Table, reversed: List<&1, ByteWal.Mutation>}
  BatchBuildPut{keys: Bytes.Bytes & Bytes.Bytes,
    values: Bytes.Bytes & Bytes.Bytes, tail: List<&1, ByteWal.Mutation>,
    table: ByteMemTable.Table, reversed: List<&1, ByteWal.Mutation>}
  BatchBuildDelete{keys: Bytes.Bytes & Bytes.Bytes,
    tail: List<&1, ByteWal.Mutation>, table: ByteMemTable.Table,
    reversed: List<&1, ByteWal.Mutation>}

# Holds the next block read or key comparison in a bounded SST point lookup.
type PointRead is Type:
  Need{cursor: SstCursor.Cursor, query: Bytes.Bytes}
  Read{step: SstCursor.Step, query: Bytes.Bytes}
  Compare{value: Bytes.Bytes, cursor: SstCursor.Cursor,
    query: Bytes.Bytes, order: Cmp}

# Converts database lock errors into the byte database error domain.
def lock.error(error: DurableError.Error) -> Error:
  match error:
    case DurableError.Error{DurableError.Busy{}, _, _, _, _}:
      Busy{}
    case DurableError.Error{DurableError.Timeout{}, _, _, code, message}:
      Timeout{}
    case DurableError.Error{DurableError.NotFound{}, _, _, code, message}:
      NotFound{}
    case DurableError.Error{DurableError.AlreadyExists{}, _, _, code, message}:
      AlreadyExists{}
    case DurableError.Error{DurableError.InvalidArgument{}, _, _, code, message}:
      InvalidArgument{}
    case DurableError.Error{DurableError.UnsupportedPlatform{}, _, _, _, _}:
      UnsupportedPlatform{}
    case DurableError.Error{DurableError.Corruption{}, _, _, code, message}:
      Corruption{message}
    case DurableError.Error{_, _, _, code, message}:
      Io{code, message}

# Maps a raw filesystem failure into the byte database error domain.
def io.error(error: U32 & String) -> Error:
  match error:
    case (code, message):
      Io{code, message}

# Converts lock acquisition into an owned database handle.
def initialization.failed(
  +path: String,
  lock: DbLock.Lock,
  error: U32 & String
) -> IO(Result<&1, &1, Error, Handle>):
  match error:
    case (code, message):
      do IO<Result<&1, &1, Error, Handle>>:
        _released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "create", path)
        return Fail{Io{code, message}}

# Syncs the new WAL directory before returning its initial handle.
def initialized.synced(
  +path: String,
  lock: DbLock.Lock,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      initialization.failed(path, lock, error)
    case Done{Unit{}}:
      IO.pure(Result<&1, &1, Error, Handle>,
        Done{Handle{path, lock, ByteMemTable.empty(), Open{}, VisibleStats.Stats{0n, 0n}}})

# Creates the generation-four WAL after acquiring the directory lock.
def initialized(
  +path: String,
  lock: DbLock.Lock,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      initialization.failed(path, lock, error)
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Handle>>:
        synced : Result<&1, &1, U32 & String, Unit> <- Fs.fsync(path)
        initialized.synced(path, lock, synced)

def initialized.manifest(
  +path: String,
  lock: DbLock.Lock,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}: initialization.failed(path, lock, error)
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Handle>>:
        published : Result<&1, &1, U32 & String, Unit> <-
          ByteManifestIo.write_atomic(path, ByteManifest.GenerationEmpty{})
        initialized(path, lock, published)

# Releases ownership when syncing the created database directory fails.
def create.locked(
  +path: String,
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{lock.error(error)})
    case Done{lock}:
      do IO<Result<&1, &1, Error, Handle>>:
        created : Result<&1, &1, U32 & String, Unit> <- ByteWalIo.create(path ++ "/WAL")
        initialized.manifest(path, lock, created)

def create.canonical(
  result: Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{io.error(error)})
    case Done{+path}:
      do IO<Result<&1, &1, Error, Handle>>:
        acquired : Result<&1, &1, DurableError.Error, DbLock.Lock> <-
          DbLock.acquire(path, "create")
        create.locked(path, acquired)

# Converts successful directory reservation into lock acquisition.
def create.reserved(
  +path: String,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{io.error(error)})
    case Done{Unit{}}:
      do IO<Result<&1, &1, Error, Handle>>:
        canonical : Result<&1, &1, U32 & String, String> <-
          Fs.canonical_path(path)
        create.canonical(canonical)

# Creates a byte database directory, stable lock, and generation-four WAL.
def create(+path: String) -> IO(Result<&1, &1, Error, Handle>):
  do IO<Result<&1, &1, Error, Handle>>:
    reserved : Result<&1, &1, U32 & String, Unit> <- Fs.make_dir(path)
    create.reserved(path, reserved)

def recovery.error(code: U32, message: String) -> Error:
  Bool.pick(Error, RecoveryPolicy.is_resource_limit(code),
    ResourceLimit{}, Corruption{message})

# Maps WAL recovery errors into corruption or host failures.
def recovered(
  +path: String,
  lock: DbLock.Lock,
  base_stats: VisibleStats.Stats,
  result: Result<&1, &1, U32 & String, ByteMemTable.Table>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{(code, message)}:
      do IO<Result<&1, &1, Error, Handle>>:
        _released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "open_existing", path)
        return Fail{recovery.error(code, message)}
    case Done{table}:
      IO.pure(Result<&1, &1, Error, Handle>,
        Done{Handle{path, lock, table, Open{}, base_stats}})

# Replays the byte WAL into an empty in-memory delta after SST validation.
def open.wal(
  +path: String,
  lock: DbLock.Lock,
  base_stats: VisibleStats.Stats
) -> IO(Result<&1, &1, Error, Handle>):
  do IO<Result<&1, &1, Error, Handle>>:
    replayed : Result<&1, &1, U32 & String, ByteMemTable.Table> <-
      ByteWalIo.recover.from(path ++ "/WAL", ByteMemTable.empty())
    recovered(path, lock, base_stats, replayed)

def open.sst.validated(
  +path: String,
  lock: DbLock.Lock,
  result: Result<&1, &1, U32 & String, ByteBlockReader.Metadata>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      recovered(path, lock, VisibleStats.Stats{0n, 0n}, Fail{error})
    case Done{ByteBlockReader.Metadata{_, _, _, _, live_entries, payload_bytes}}:
      open.wal(path, lock, VisibleStats.Stats{live_entries, payload_bytes})

def open.manifest.failed(
  +path: String,
  lock: DbLock.Lock,
  error: ByteManifestIo.Error
) -> IO(Result<&1, &1, Error, Handle>):
  match error:
    case ByteManifestIo.Invalid{_}:
      do IO<Result<&1, &1, Error, Handle>>:
        _released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "open_existing", path)
        return Fail{Corruption{"byte manifest validation failed"}}
    case ByteManifestIo.Host{code, message}:
      do IO<Result<&1, &1, Error, Handle>>:
        _released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "open_existing", path)
        return Fail{Io{code, message}}

def open.manifest.result(
  +path: String,
  lock: DbLock.Lock,
  result: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}: open.manifest.failed(path, lock, error)
    case Done{ByteManifest.Empty{}}:
      open.wal(path, lock, VisibleStats.Stats{0n, 0n})
    case Done{ByteManifest.GenerationEmpty{}}:
      open.wal(path, lock, VisibleStats.Stats{0n, 0n})
    case Done{ByteManifest.HasSst{}}:
      do IO<Result<&1, &1, Error, Handle>>:
        metadata : Result<&1, &1, U32 & String, ByteBlockReader.Metadata> <-
          ByteSstIo.validate(path ++ "/SST")
        open.sst.validated(path, lock, metadata)
    case Done{ByteManifest.GenerationSst{file_id}}:
      do IO<Result<&1, &1, Error, Handle>>:
        metadata : Result<&1, &1, U32 & String, ByteBlockReader.Metadata> <-
          ByteSstIo.validate(ByteManifest.sst.generation.path(path, file_id))
        open.sst.validated(path, lock, metadata)

# Checks for a published byte SST while retaining database ownership.
def open.locked(
  +path: String,
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{lock.error(error)})
    case Done{lock}:
      do IO<Result<&1, &1, Error, Handle>>:
        manifest : Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue> <-
          ByteManifestIo.read(path ++ "/MANIFEST")
        open.manifest.result(path, lock, manifest)

# Acquires exclusive ownership before replaying the byte WAL.
def open.canonical(
  result: Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{io.error(error)})
    case Done{+path}:
      do IO<Result<&1, &1, Error, Handle>>:
        acquired : Result<&1, &1, DurableError.Error, DbLock.Lock> <-
          DbLock.acquire(path, "open_existing")
        open.locked(path, acquired)

def open.existing(+path: String) -> IO(Result<&1, &1, Error, Handle>):
  do IO<Result<&1, &1, Error, Handle>>:
    canonical : Result<&1, &1, U32 & String, String> <- Fs.canonical_path(path)
    open.canonical(canonical)

# Validates the WAL path before acquiring ownership.
def open.existing.present(
  +path: String,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{io.error(error)})
    case Done{False{}}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{NotFound{}})
    case Done{True{}}:
      open.existing(path)

def open.existing.wait.canonical(
  result: Result<&1, &1, U32 & String, String>,
  +timeout_ms: U32,
  +backoff_ms: U32
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{io.error(error)})
    case Done{+path}:
      do IO<Result<&1, &1, Error, Handle>>:
        acquired : Result<&1, &1, DurableError.Error, DbLock.Lock> <-
          DbLock.acquire_wait(path, "open_existing", timeout_ms, backoff_ms)
        open.locked(path, acquired)

def open.existing.wait.present(
  +path: String,
  +timeout_ms: U32,
  +backoff_ms: U32,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{io.error(error)})
    case Done{False{}}:
      IO.pure(Result<&1, &1, Error, Handle>, Fail{NotFound{}})
    case Done{True{}}:
      do IO<Result<&1, &1, Error, Handle>>:
        canonical : Result<&1, &1, U32 & String, String> <- Fs.canonical_path(path)
        open.existing.wait.canonical(canonical, timeout_ms, backoff_ms)

# Opens an existing byte database after immediate or bounded lock acquisition.
def open_existing_wait(
  +path: String,
  timeout_ms: U32,
  backoff_ms: U32
) -> IO(Result<&1, &1, Error, Handle>):
  do IO<Result<&1, &1, Error, Handle>>:
    present : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path ++ "/WAL")
    open.existing.wait.present(path, timeout_ms, backoff_ms, present)

# Opens an existing byte database and replays its binary WAL.
def open_existing(+path: String) -> IO(Result<&1, &1, Error, Handle>):
  do IO<Result<&1, &1, Error, Handle>>:
    present : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path ++ "/WAL")
    open.existing.present(path, present)

# Returns the handle and preserves the decoded batch result.
def append.decoded(
  result: Result<&1, &1, Wal.Error, ByteWal.Batch>
) -> Result<&1, &1, Error, ByteWal.Batch>:
  match result:
    case Fail{_}:
      Fail{Corruption{"encoded byte WAL frame failed self-validation"}}
    case Done{batch}:
      Done{batch}

# Poisons a handle when append or sync leaves commit status uncertain.
def append.unknown(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  error: U32 & String
) -> Handle & Result<&1, &1, Error, Unit>:
  match error:
    case (code, message):
      (Handle{path, lock, table, Poisoned{}, VisibleStats.Stats{0n, 0n}}, Fail{CommitUnknown{code, message}})

# Applies a successfully synced frame to the current table.
def append.applied.result(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  result: Result<&1, &1, Error, ByteMemTable.Table>
) -> Handle & Result<&1, &1, Error, Unit>:
  match result:
    case Fail{Corruption{message}}:
      (Handle{path, lock, table, Poisoned{}, VisibleStats.Stats{0n, 0n}},
        Fail{CommitUnknown{0, message}})
    case Fail{error}:
      (Handle{path, lock, table, Poisoned{}, VisibleStats.Stats{0n, 0n}}, Fail{CommitUnknown{0, "invalid durable frame"}})
    case Done{next_table}:
      (Handle{path, lock, next_table, Open{}, VisibleStats.Stats{0n, 0n}}, Done{Unit{}})

# Appends the encoded frame and preserves a copy for post-sync replay.
def append.applied.decoded(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  result: Result<&1, &1, Error, ByteWal.Batch>
) -> Handle & Result<&1, &1, Error, Unit>:
  match result:
    case Fail{error}:
      (Handle{path, lock, table, Poisoned{}, VisibleStats.Stats{0n, 0n}}, Fail{CommitUnknown{0, "invalid durable frame"}})
    case Done{batch}:
      (Handle{path, lock, ByteWalIo.apply.batch(table, batch), Open{}, VisibleStats.Stats{0n, 0n}}, Done{Unit{}})

def append.applied(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  result: Result<&1, &1, Wal.Error, ByteWal.Batch>
) -> Handle & Result<&1, &1, Error, Unit>:
  append.applied.decoded(path, lock, table, append.decoded(result))

# Converts decoded frame validation into a committed handle state.
def append.synced(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  apply_frame: Bytes.Bytes,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match result:
    case Fail{error}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        append.unknown(path, lock, table, error))
    case Done{Unit{}}:
      do IO<Handle & Result<&1, &1, Error, Unit>>:
        _checkpoint : Result<&1, &1, U32 & String, Unit> <-
          CrashPoint.hit("wal.after_sync_before_apply")
        return append.applied(path, lock, table, ByteWal.decode(apply_frame))

# Replaces the in-memory table only after the WAL frame is durable.
def append.frames(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  frames: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match frames:
    case (append_frame, apply_frame):
      do IO<Handle & Result<&1, &1, Error, Unit>>:
        appended : Result<&1, &1, U32 & String, Unit> <-
          ByteWalIo.append.encoded(Done{append_frame}, path ++ "/WAL")
        append.synced(path, lock, table, apply_frame, appended)

# Distinguishes pre-append encoding rejection from uncertain host writes.
def append.encoded(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  result: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match result:
    case Fail{_}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{InvalidArgument{}}))
    case Done{frame}:
      append.frames(path, lock, table, ByteMemTable.bytes.clone(frame))

# Validates open state before encoding or touching the WAL.
def write.encoded(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  batch: ByteWal.Batch
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match state:
    case Open{}:
      append.encoded(path, lock, table, ByteWal.encode(batch))
    case Poisoned{}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Poisoned{}, VisibleStats.Stats{0n, 0n}}, Fail{CommitUnknown{0, "database handle requires reopen"}}))

def write.count.validated(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  ordered: List<&1, ByteWal.Mutation>,
  validation: BatchPolicy.Validation
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match validation:
    case BatchPolicy.ValidBatch{}:
      write.encoded(path, lock, table, Open{}, ByteWal.Batch{ordered})
    case BatchPolicy.BatchBytesExceeded{}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}},
          Fail{ResourceLimit{}}))
    case BatchPolicy.BatchCountExceeded{}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}},
          Fail{ResourceLimit{}}))
    case _:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{InvalidArgument{}}))

def write.count.measured(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  measured: BatchPolicy.ByteBatchMeasurement
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match measured:
    case BatchPolicy.BatchMeasured{mutations, count, encoded_bytes}:
      write.count.validated(path, lock, table, mutations,
        BatchPolicy.validate_batch(count, encoded_bytes))
    case BatchPolicy.BatchTooMany{}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}},
          Fail{ResourceLimit{}}))

def write.counted(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  batch: ByteWal.Batch
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match state:
    case Poisoned{}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Poisoned{}, VisibleStats.Stats{0n, 0n}},
          Fail{CommitUnknown{0, "database handle requires reopen"}}))
    case Open{}:
      match batch:
        case ByteWal.Batch{mutations}:
          write.count.measured(path, lock, table,
            BatchPolicy.byte_batch.measure(mutations))

def write.retained(
  base_stats: VisibleStats.Stats,
  pair: Handle & Result<&1, &1, Error, Unit>
) -> Handle & Result<&1, &1, Error, Unit>:
  match pair:
    case (Handle{path, lock, table, state, _}, result):
      (Handle{path, lock, table, state, base_stats}, result)

# Keeps the original state when SST or WAL checkpoint publication fails.
# Counts the visible entries and payload bytes in the newly published SST.
def flush.stats.entries(
  entries: List<&1, ByteMemTable.Entry>,
  current: VisibleStats.Stats
) -> VisibleStats.Stats:
  match entries:
    case Nil{}: current
    case Con{ByteMemTable.Entry{Bytes.Bytes{+key_len, _}, value}, tail}:
      match value:
        case None{}: flush.stats.entries(tail, current)
        case Some{Bytes.Bytes{+value_len, _}}:
          flush.stats.entries(tail, VisibleStats.result(VisibleStats.apply(
            current, U32.to_nat(key_len), None{}, Some{U32.to_nat(value_len)})))

# Applies the flush transition after the WAL checkpoint is durable.
def flush.wal.reset(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  entries: List<&1, ByteMemTable.Entry>,
  result: Result<&1, &1, U32 & String, Unit>
) -> Handle & Result<&1, &1, Error, Unit>:
  match result:
    case Fail{(code, message)}:
      (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{Io{code, message}})
    case Done{Unit{}}:
      (Handle{path, lock, ByteMemTable.empty(), Open{},
        flush.stats.entries(entries, VisibleStats.Stats{0n, 0n})}, Done{Unit{}})

def flush.manifest(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  entries: List<&1, ByteMemTable.Entry>,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{Io{code, message}}))
    case Done{Unit{}}:
      do IO<Handle & Result<&1, &1, Error, Unit>>:
        reset : Result<&1, &1, U32 & String, Unit> <- ByteWalIo.reset_atomic(path)
        return flush.wal.reset(path, lock, table, entries, reset)

# Keeps the original table when SST publication fails; after publication,
# checkpoints the WAL through atomic replacement and retains canonical entries.
# Reverses a string while preserving all path characters.
def path.reverse(path: String, reversed: String) -> String:
  match path:
    case SNil{}: reversed
    case SCon{character, rest}:
      path.reverse(rest, SCon{character, reversed})

# Creates an independent string from its characters.
def path.clone(path: String) -> String:
  path.reverse(path.reverse(path, SNil{}), SNil{})

# Copies one natural value into two equal affine outputs.
def duplicate_nat_pair_step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (left, right): (Nat.add(left, 1n), Nat.add(right, 1n))

# Reifies one natural number as two independently owned values.
def duplicate_nat_pair(value: Nat) -> Nat & Nat:
  match value:
    case 0n: (0n, 0n)
    case 1n+rest: duplicate_nat_pair_step(duplicate_nat_pair(rest))

# Prepends one scalar to each independently rebuilt path.
def path.clone.pair.scalar(
  first: String,
  second: String,
  pair: Nat & Nat
) -> String & String:
  match pair:
    case (left, right):
      (SCon{Chr{U32.from_nat(left)}, first},
        SCon{Chr{U32.from_nat(right)}, second})

# Rebuilds two identical paths in one traversal.
def path.clone.pair.go(
  path: String,
  copies: String & String
) -> String & String:
  match path:
    case SNil{}:
      match copies:
        case (first, second):
          (path.reverse(first, SNil{}), path.reverse(second, SNil{}))
    case SCon{Chr{+scalar}, rest}:
      match copies:
        case (first, second):
          path.clone.pair.go(rest, path.clone.pair.scalar(first, second,
            duplicate_nat_pair(U32.to_nat(scalar))))

# Produces two owned copies of a canonical filesystem path.
def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, (SNil{}, SNil{}))

# Combines an initial path copy with two independently rebuilt copies.
def path.clone.triple.second(
  first: String,
  pair: String & String
) -> String & String & String:
  match pair:
    case (second, third): (first, second, third)

# Splits the duplicated suffix into the remaining two path copies.
def path.clone.triple.first(pair: String & String) -> String & String & String:
  match pair:
    case (first, suffix):
      path.clone.triple.second(first, path.clone.pair(suffix))

# Produces three independently owned copies of a canonical path.
def path.clone.triple(path: String) -> String & String & String:
  path.clone.triple.first(path.clone.pair(path))


def flush.written(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  entries: List<&1, ByteMemTable.Entry>,
  file_id: U32,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{Io{code, message}}))
    case Done{Unit{}}:
      do IO<Handle & Result<&1, &1, Error, Unit>>:
        published : Result<&1, &1, U32 & String, Unit> <-
          ByteManifestIo.write_atomic(path, ByteManifest.GenerationSst{file_id})
        flush.manifest(path, lock, table, entries, published)

def flush.snapshot.publish.file_ids(
  paths: String & (String & String),
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  pair: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  file_ids: U32 & U32
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match paths:
    case (directory, (file_directory, retained_path)):
      match pair:
        case (encoded, retained):
          match file_ids:
            case (for_path, for_manifest):
              do IO<Handle & Result<&1, &1, Error, Unit>>:
                written : Result<&1, &1, U32 & String, Unit> <-
                  ByteSstIo.write_atomic_at(directory,
                    ByteManifest.sst.generation.path(file_directory, for_path), encoded)
                flush.written(retained_path, lock, table, retained, for_manifest, written)

def flush.snapshot.publish(
  paths: String & (String & String),
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  pair: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  file_id: U32
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  flush.snapshot.publish.file_ids(paths, lock, table, pair,
    ByteManifest.clone.file.id(file_id))

def flush.snapshot.identifier(
  paths: String & (String & String),
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  entries: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  decision: ByteManifest.FileIdDecision
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match paths:
    case (directory, (file_directory, retained_path)):
      match entries:
        case (encoded, retained):
          match decision:
            case ByteManifest.FileIdAvailable{file_id}:
              flush.snapshot.publish((directory, (file_directory, retained_path)),
                lock, table, (encoded, retained), file_id)
            case ByteManifest.FileIdExhausted{}:
              IO.pure(Handle & Result<&1, &1, Error, Unit>,
                (Handle{retained_path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}},
                  Fail{ResourceLimit{}}))

def flush.snapshot.manifest(
  path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  entries: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  result: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match result:
    case Fail{ByteManifestIo.Invalid{_}}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}},
          Fail{Corruption{"byte manifest validation failed"}}))
    case Fail{ByteManifestIo.Host{code, message}}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}},
          Fail{Io{code, message}}))
    case Done{value}:
      flush.snapshot.identifier(path.clone.triple(path), lock, table, entries,
        ByteManifest.next.file.id(value))

# Retains the live table while an independently owned ordered copy is encoded.
def flush.snapshot(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  pair: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match pair:
    case (encoded, retained):
      do IO<Handle & Result<&1, &1, Error, Unit>>:
        manifest : Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue> <-
          ByteManifestIo.read(path ++ "/MANIFEST")
        flush.snapshot.manifest(path, lock, table, (encoded, retained), manifest)

# Builds a canonical snapshot without consuming the live table.
def flush.table(
  +path: String,
  lock: DbLock.Lock,
  pair: ByteMemTable.Table & List<&1, ByteMemTable.Entry>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match pair:
    case (table, entries):
      flush.snapshot(path, lock, table,
        ByteSstFile.entries.clone(ByteMemTable.ordered_entries(ByteMemTable.Table{entries})))

# Clones the table entries so flush can retain the live in-memory state.
def flush.cloned(
  +path: String,
  lock: DbLock.Lock,
  pair: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match pair:
    case (live, snapshot):
      flush.table(path, lock, (ByteMemTable.Table{live}, snapshot))

# Merges the persisted SST beneath the newest in-memory WAL delta.
def flush.sst.loaded(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  result: Result<&1, &1, U32 & String, ByteMemTable.Table>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match table:
    case ByteMemTable.Table{delta}:
      match result:
        case Fail{(code, message)}:
          IO.pure(Handle & Result<&1, &1, Error, Unit>,
            (Handle{path, lock, ByteMemTable.Table{delta}, Open{}, VisibleStats.Stats{0n, 0n}},
              Fail{recovery.error(code, message)}))
        case Done{ByteMemTable.Table{base}}:
          flush.cloned(path, lock,
            ByteSstFile.entries.clone(ByteMemTable.append(delta, base)))

def flush.manifest.loaded(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  result: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match table:
    case ByteMemTable.Table{entries}:
      match result:
        case Fail{ByteManifestIo.Invalid{_}}:
          IO.pure(Handle & Result<&1, &1, Error, Unit>,
            (Handle{path, lock, ByteMemTable.Table{entries}, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{Corruption{"byte manifest validation failed"}}))
        case Fail{ByteManifestIo.Host{code, message}}:
          IO.pure(Handle & Result<&1, &1, Error, Unit>,
            (Handle{path, lock, ByteMemTable.Table{entries}, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{Io{code, message}}))
        case Done{ByteManifest.Empty{}}:
          flush.cloned(path, lock, ByteSstFile.entries.clone(entries))
        case Done{ByteManifest.GenerationEmpty{}}:
          flush.cloned(path, lock, ByteSstFile.entries.clone(entries))
        case Done{ByteManifest.HasSst{}}:
          do IO<Handle & Result<&1, &1, Error, Unit>>:
            base : Result<&1, &1, U32 & String, ByteMemTable.Table> <-
              ByteSstIo.read(path ++ "/SST")
            flush.sst.loaded(path, lock, ByteMemTable.Table{entries}, base)
        case Done{ByteManifest.GenerationSst{file_id}}:
          do IO<Handle & Result<&1, &1, Error, Unit>>:
            base : Result<&1, &1, U32 & String, ByteMemTable.Table> <-
              ByteSstIo.read(ByteManifest.sst.generation.path(path, file_id))
            flush.sst.loaded(path, lock, ByteMemTable.Table{entries}, base)

# Clones table entries before creating a canonical snapshot.
def flush.open(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  do IO<Handle & Result<&1, &1, Error, Unit>>:
    manifest : Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue> <-
      ByteManifestIo.read(path ++ "/MANIFEST")
    flush.manifest.loaded(path, lock, table, manifest)

# Publishes the current byte table as an authenticated SST snapshot.
def flush(handle: Handle) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match handle:
    case Handle{path, lock, table, Open{}, base_stats}:
      flush.open(path, lock, table)
    case Handle{path, lock, table, Poisoned{}, base_stats}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Poisoned{}, VisibleStats.Stats{0n, 0n}}, Fail{CommitUnknown{0, "database handle requires reopen"}}))

def compact.entries(
  +path: String,
  lock: DbLock.Lock,
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match copies:
    case (retained, working):
      flush.snapshot(path, lock, ByteMemTable.Table{retained},
        ByteSstFile.entries.clone(ByteMemTable.compact.live(
          ByteMemTable.ordered_entries(ByteMemTable.Table{working}))))

def compact.sst.loaded(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  result: Result<&1, &1, U32 & String, ByteMemTable.Table>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match table:
    case ByteMemTable.Table{delta}:
      match result:
        case Fail{(code, message)}:
          IO.pure(Handle & Result<&1, &1, Error, Unit>,
            (Handle{path, lock, ByteMemTable.Table{delta}, Open{}, VisibleStats.Stats{0n, 0n}},
              Fail{recovery.error(code, message)}))
        case Done{ByteMemTable.Table{base}}:
          compact.entries(path, lock,
            ByteSstFile.entries.clone(ByteMemTable.append(delta, base)))

def compact.manifest.loaded(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  result: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match table:
    case ByteMemTable.Table{entries}:
      match result:
        case Fail{ByteManifestIo.Invalid{_}}:
          IO.pure(Handle & Result<&1, &1, Error, Unit>,
            (Handle{path, lock, ByteMemTable.Table{entries}, Open{}, VisibleStats.Stats{0n, 0n}},
              Fail{Corruption{"byte manifest validation failed"}}))
        case Fail{ByteManifestIo.Host{code, message}}:
          IO.pure(Handle & Result<&1, &1, Error, Unit>,
            (Handle{path, lock, ByteMemTable.Table{entries}, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{Io{code, message}}))
        case Done{ByteManifest.Empty{}}:
          compact.entries(path, lock, ByteSstFile.entries.clone(entries))
        case Done{ByteManifest.GenerationEmpty{}}:
          compact.entries(path, lock, ByteSstFile.entries.clone(entries))
        case Done{ByteManifest.HasSst{}}:
          do IO<Handle & Result<&1, &1, Error, Unit>>:
            base : Result<&1, &1, U32 & String, ByteMemTable.Table> <-
              ByteSstIo.read(path ++ "/SST")
            compact.sst.loaded(path, lock, ByteMemTable.Table{entries}, base)
        case Done{ByteManifest.GenerationSst{file_id}}:
          do IO<Handle & Result<&1, &1, Error, Unit>>:
            base : Result<&1, &1, U32 & String, ByteMemTable.Table> <-
              ByteSstIo.read(ByteManifest.sst.generation.path(path, file_id))
            compact.sst.loaded(path, lock, ByteMemTable.Table{entries}, base)

def compact.pathcopies(
  copies: String & String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match copies:
    case (read_path, retained_path):
      do IO<Handle & Result<&1, &1, Error, Unit>>:
        manifest : Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue> <-
          ByteManifestIo.read(read_path ++ "/MANIFEST")
        compact.manifest.loaded(retained_path, lock, table, manifest)

# Publishes a canonical byte table with tombstones removed.
def compact(handle: Handle) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match handle:
    case Handle{path, lock, table, Open{}, base_stats}:
      compact.pathcopies(path.clone.pair(path), lock, table)
    case Handle{path, lock, table, Poisoned{}, base_stats}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (Handle{path, lock, table, Poisoned{}, VisibleStats.Stats{0n, 0n}}, Fail{CommitUnknown{0, "database handle requires reopen"}}))

def get.sst.close.result(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  value: Maybe<&1, Bytes.Bytes>,
  closed: Result<&1, &1, U32 & String, Unit>
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match closed:
    case Fail{(code, message)}:
      IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{Io{code, message}}))
    case Done{Unit{}}:
      IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Done{value}))

def get.sst.closed(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  value: Maybe<&1, Bytes.Bytes>,
  cursor: SstCursor.Cursor
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  do IO<Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>>:
    closed : Result<&1, &1, U32 & String, Unit> <- SstCursor.close(cursor)
    get.sst.close.result(path, lock, table, value, closed)

def get.sst.compare.decided(
  value: Bytes.Bytes,
  cursor: SstCursor.Cursor,
  query: Bytes.Bytes,
  order: Cmp
) -> PointRead:
  Compare{value, cursor, query, order}

def get.sst.compare.order(
  value: Bytes.Bytes,
  cursor: SstCursor.Cursor,
  key: Bytes.Bytes,
  queries: Bytes.Bytes & Bytes.Bytes
) -> PointRead:
  match queries:
    case (for_comparison, for_continue):
      get.sst.compare.decided(value, cursor, for_continue,
        Keys.Bytes.cmp(key, for_comparison))

def get.sst.exhausted.cursor(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  cursor: SstCursor.Cursor
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  do IO<Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>>:
    _closed : Result<&1, &1, U32 & String, Unit> <- SstCursor.close(cursor)
    return (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{ResourceLimit{}})

def get.sst.exhausted(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: PointRead
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match state:
    case Need{cursor, _}:
      get.sst.exhausted.cursor(path, lock, table, cursor)
    case Compare{_, cursor, _, _}:
      get.sst.exhausted.cursor(path, lock, table, cursor)
    case Read{step, _}:
      match step:
        case SstCursor.Item{_, cursor}:
          get.sst.exhausted.cursor(path, lock, table, cursor)
        case SstCursor.Skip{cursor}:
          get.sst.exhausted.cursor(path, lock, table, cursor)
        case SstCursor.End{}:
          IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
            (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Done{None{}}))
        case SstCursor.Error{(code, message)}:
          IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
            (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{recovery.error(code, message)}))

def get.sst.loop(
  fuel: Nat,
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: PointRead
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match fuel:
    case 0n:
      get.sst.exhausted(path, lock, table, state)
    case 1n+rest:
      match state:
        case Need{cursor, query}:
          do IO<Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>>:
            step : SstCursor.Step <- SstCursor.next(cursor)
            get.sst.loop(rest, path, lock, table, Read{step, query})
        case Read{step, query}:
          match step:
            case SstCursor.Item{entry, cursor}:
              match entry:
                case ByteMemTable.Entry{key, val}:
                  match val:
                    case None{}:
                      get.sst.loop(rest, path, lock, table, Need{cursor, query})
                    case Some{value}:
                      get.sst.loop(rest, path, lock, table,
                        get.sst.compare.order(value, cursor, key,
                          ByteMemTable.bytes.clone(query)))
            case SstCursor.Skip{cursor}:
              get.sst.loop(rest, path, lock, table, Need{cursor, query})
            case SstCursor.End{}:
              IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
                (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Done{None{}}))
            case SstCursor.Error{(code, message)}:
              IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
                (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{recovery.error(code, message)}))
        case Compare{value, cursor, query, order}:
          match order:
            case EQ{}:
              get.sst.closed(path, lock, table, Some{value}, cursor)
            case GT{}:
              get.sst.closed(path, lock, table, None{}, cursor)
            case LT{}:
              get.sst.loop(rest, path, lock, table, Need{cursor, query})

def get.sst.opened(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  query: Bytes.Bytes,
  size: Nat,
  opened: Result<&1, &1, U32 & String, SstCursor.Cursor>
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match opened:
    case Fail{(code, message)}:
      IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{recovery.error(code, message)}))
    case Done{cursor}:
      get.sst.loop(Nat.add(size, 2n), path, lock, table, Need{cursor, query})

def get.sst.sized(
  paths: String & String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  keys: Bytes.Bytes & Bytes.Bytes,
  size: Result<&1, &1, U32 & String, Nat>
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match paths:
    case (cursor_path, retained_path):
      match keys:
        case (lower, query):
          match size:
            case Fail{(code, message)}:
              IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
                (Handle{retained_path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}},
                  Fail{io.error((code, message))}))
            case Done{size}:
              do IO<Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>>:
                opened : Result<&1, &1, U32 & String, SstCursor.Cursor> <-
                  SstCursor.open.trusted(cursor_path,
                    SstCursor.Bounds{Some{lower}, None{}, None{}})
                get.sst.opened(retained_path, lock, table, query, size, opened)

def get.sst.start(
  paths: String & (String & String),
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  keys: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match paths:
    case (size_path, (cursor_path, retained_path)):
      match keys:
        case (lower, query):
          do IO<Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>>:
            size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(size_path)
            get.sst.sized((cursor_path, retained_path), lock, table,
              (lower, query), size)

def get.sst.generation.file.paths(
  files: String & String,
  retained_path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  keys: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match files:
    case (size_path, cursor_path):
      match keys:
        case (lower, query):
          do IO<Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>>:
            size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(size_path)
            get.sst.sized((cursor_path, retained_path), lock, table,
              (lower, query), size)

def get.sst.generation.file(
  values: String & String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  keys: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match values:
    case (generation_path, retained_path):
      get.sst.generation.file.paths(path.clone.pair(generation_path),
        retained_path, lock, table, keys)

def get.sst.generation.read(
  paths: String & String,
  file_id: U32,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  key: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match paths:
    case (generation_dir, retained_path):
      get.sst.generation.file(
        (ByteManifest.sst.generation.path(generation_dir, file_id), retained_path),
        lock, table, ByteMemTable.bytes.clone(key))

def get.sst.generation.probe(
  paths: String & String,
  file_id: U32,
  lock: DbLock.Lock,
  key: Bytes.Bytes,
  pair: ByteMemTable.Table & ByteMemTable.Probe
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match paths:
    case (generation_dir, retained_path):
      match pair:
        case (table, ByteMemTable.Absent{}):
          get.sst.generation.read((generation_dir, retained_path), file_id,
            lock, table, key)
        case (table, ByteMemTable.Deleted{}):
          IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
            (Handle{retained_path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}},
              Done{None{}}))
        case (table, ByteMemTable.Present{value}):
          IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
            (Handle{retained_path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}},
              Done{Some{value}}))

def get.sst.generation.probe.start(
  paths: String & String,
  file_id: U32,
  lock: DbLock.Lock,
  keys: Bytes.Bytes & Bytes.Bytes,
  table: ByteMemTable.Table
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match paths:
    case (generation_dir, retained_path):
      match keys:
        case (probe_key, fallback_key):
          get.sst.generation.probe((generation_dir, retained_path), file_id,
            lock, fallback_key, ByteMemTable.probe(table, probe_key))

def get.sst.generation.path(
  paths: String & String,
  file_id: U32,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  key: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  get.sst.generation.probe.start(paths, file_id, lock,
    ByteMemTable.bytes.clone(key), table)

def path.append.sst.triple(paths: String & (String & String)) -> String & (String & String):
  match paths:
    case (size_dir, (cursor_dir, retained_path)):
      (size_dir ++ "/SST", (cursor_dir ++ "/SST", retained_path))

def get.sst(
  +path: String,
  lock: DbLock.Lock,
  key: Bytes.Bytes,
  table: ByteMemTable.Table
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  get.sst.start(path.append.sst.triple(path.clone.triple(path)), lock, table,
    ByteMemTable.bytes.clone(key))

def get.delta(
  +path: String,
  lock: DbLock.Lock,
  pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match pair:
    case (updated, value):
      IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
        (Handle{path, lock, updated, Open{}, VisibleStats.Stats{0n, 0n}}, Done{value}))

def get.sst.probe(
  +path: String,
  lock: DbLock.Lock,
  key: Bytes.Bytes,
  pair: ByteMemTable.Table & ByteMemTable.Probe
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match pair:
    case (table, ByteMemTable.Absent{}):
      get.sst(path, lock, key, table)
    case (table, ByteMemTable.Deleted{}):
      IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Done{None{}}))
    case (table, ByteMemTable.Present{value}):
      IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Done{Some{value}}))

def get.sst.probe.start(
  +path: String,
  lock: DbLock.Lock,
  keys: Bytes.Bytes & Bytes.Bytes,
  table: ByteMemTable.Table
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match keys:
    case (probe_key, fallback_key):
      get.sst.probe(path, lock, fallback_key,
        ByteMemTable.probe(table, probe_key))

def get.manifest(
  +path: String,
  lock: DbLock.Lock,
  key: Bytes.Bytes,
  table: ByteMemTable.Table,
  result: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match result:
    case Fail{ByteManifestIo.Invalid{_}}:
      IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{Corruption{"byte manifest validation failed"}}))
    case Fail{ByteManifestIo.Host{code, message}}:
      IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
        (Handle{path, lock, table, Open{}, VisibleStats.Stats{0n, 0n}}, Fail{Io{code, message}}))
    case Done{ByteManifest.Empty{}}:
      get.delta(path, lock, ByteMemTable.get(table, key))
    case Done{ByteManifest.GenerationEmpty{}}:
      get.delta(path, lock, ByteMemTable.get(table, key))
    case Done{ByteManifest.HasSst{}}:
      get.sst.probe.start(path, lock, ByteMemTable.bytes.clone(key), table)
    case Done{ByteManifest.GenerationSst{file_id}}:
      get.sst.generation.path(path.clone.pair(path), file_id, lock, table, key)

def get.pathcopies(
  copies: String & String,
  lock: DbLock.Lock,
  key: Bytes.Bytes,
  table: ByteMemTable.Table
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match copies:
    case (read_path, retained_path):
      do IO<Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>>:
        manifest : Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue> <-
          ByteManifestIo.read(read_path ++ "/MANIFEST")
        get.manifest(retained_path, lock, key, table, manifest)

# Reads one raw byte key while retaining the database handle.
def get.retained(
  base_stats: VisibleStats.Stats,
  pair: Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>
) -> Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>:
  match pair:
    case (Handle{path, lock, table, state, _}, result):
      (Handle{path, lock, table, state, base_stats}, result)

# Reads one raw byte key while retaining the database handle.
def get(
  handle: Handle,
  key: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>):
  match handle:
    case Handle{path, lock, table, Open{}, base_stats}:
      do IO<Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>>:
        pair : Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>> <-
          get.pathcopies(path.clone.pair(path), lock, key, table)
        return get.retained(base_stats, pair)
    case Handle{path, lock, table, Poisoned{}, base_stats}:
      IO.pure(Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>>,
        (Handle{path, lock, table, Poisoned{}, base_stats},
          Fail{CommitUnknown{0, "database handle requires reopen"}}))

def stats.remove.base.length(
  base_stats: VisibleStats.Stats,
  key_bytes: Nat,
  old_value: Maybe<&1, Bytes.Bytes>
) -> VisibleStats.Stats:
  match old_value:
    case None{}: base_stats
    case Some{Bytes.Bytes{+value_len, _}}:
      VisibleStats.result(VisibleStats.removed(base_stats, key_bytes,
        U32.to_nat(value_len)))

def batch.keys.retained(
  probe_key: Bytes.Bytes,
  pair: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (read_key, stats_key): (probe_key, read_key, stats_key)

def batch.keys.first(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (probe_key, retained):
      batch.keys.retained(probe_key, ByteMemTable.bytes.clone(retained))

def batch.keys(key: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  batch.keys.first(ByteMemTable.bytes.clone(key))

def batch.restore.handle(
  original_stats: VisibleStats.Stats,
  handle: Handle
) -> Handle:
  match handle:
    case Handle{path, lock, table, state, _}:
      Handle{path, lock, table, state, original_stats}

def batch.build(fuel: Nat, state: BatchBuildState) -> ByteMemTable.Table & List<&1, ByteWal.Mutation>:
  match fuel:
    case 0n:
      match state:
        case BatchBuild{_, table, reversed}:
          (table, List.reverse(&1, ByteWal.Mutation, reversed))
        case BatchBuildPut{_, _, _, table, reversed}:
          (table, List.reverse(&1, ByteWal.Mutation, reversed))
        case BatchBuildDelete{_, _, table, reversed}:
          (table, List.reverse(&1, ByteWal.Mutation, reversed))
    case 1n+rest:
      match state:
        case BatchBuild{mutations, table, reversed}:
          match mutations:
            case Nil{}:
              (table, List.reverse(&1, ByteWal.Mutation, reversed))
            case Con{ByteWal.Put{key, value}, tail}:
              batch.build(rest, BatchBuildPut{ByteMemTable.bytes.clone(key),
                ByteMemTable.bytes.clone(value), tail, table, reversed})
            case Con{ByteWal.Delete{key}, tail}:
              batch.build(rest, BatchBuildDelete{ByteMemTable.bytes.clone(key),
                tail, table, reversed})
        case BatchBuildPut{keys, values, tail, table, reversed}:
          match keys:
            case (candidate_key, wal_key):
              match values:
                case (candidate_value, wal_value):
                  batch.build(rest, BatchBuild{tail,
                    ByteMemTable.put(table, candidate_key, candidate_value),
                    Con{ByteWal.Put{wal_key, wal_value}, reversed}})
        case BatchBuildDelete{keys, tail, table, reversed}:
          match keys:
            case (candidate_key, wal_key):
              batch.build(rest, BatchBuild{tail, ByteMemTable.del(table, candidate_key),
                Con{ByteWal.Delete{wal_key}, reversed}})

def batch.stats.exhausted(state: BatchStatsState) -> IO(Handle & Result<&1, &1, Error, BatchPrepared>):
  match state:
    case BatchNeed{handle, _, _, original_stats, _}:
      IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
        (batch.restore.handle(original_stats, handle), Fail{ResourceLimit{}}))
    case BatchKey{handle, _, _, original_stats, _, _}:
      IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
        (batch.restore.handle(original_stats, handle), Fail{ResourceLimit{}}))
    case BatchProbe{handle, _, _, original_stats, _, _, _, _}:
      IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
        (batch.restore.handle(original_stats, handle), Fail{ResourceLimit{}}))
    case BatchRead{pair, _, _, original_stats, _, _}:
      match pair:
        case (handle, _):
          IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
            (batch.restore.handle(original_stats, handle), Fail{ResourceLimit{}}))

def batch.stats.loop(fuel: Nat, state: BatchStatsState) -> IO(Handle & Result<&1, &1, Error, BatchPrepared>):
  match fuel:
    case 0n: batch.stats.exhausted(state)
    case 1n+rest:
      match state:
        case BatchNeed{handle, mutations, entries, original_stats, base_stats}:
          match handle:
            case Handle{path, lock, table, state, _}:
              match entries:
                case Nil{}:
                  IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
                    (Handle{path, lock, table, state, original_stats},
                      Done{Prepared{mutations, base_stats}}))
                case Con{ByteMemTable.Entry{key, _}, tail}:
                  batch.stats.loop(rest, BatchKey{
                    Handle{path, lock, table, state, VisibleStats.Stats{0n, 0n}},
                    mutations, tail, original_stats, base_stats, batch.keys(key)})
        case BatchKey{handle, mutations, entries, original_stats, base_stats, keys}:
          match handle:
            case Handle{path, lock, table, state, _}:
              match keys:
                case (probe_key, (read_key, stats_key)):
                  match stats_key:
                    case Bytes.Bytes{+key_len, _}:
                      batch.stats.loop(rest, BatchProbe{
                        Handle{path, lock, ByteMemTable.empty(), state,
                          VisibleStats.Stats{0n, 0n}},
                        mutations, entries, original_stats, base_stats,
                        U32.to_nat(key_len), read_key,
                        ByteMemTable.probe(table, probe_key)})
        case BatchProbe{handle, mutations, entries, original_stats,
            base_stats, key_bytes, key, result}:
          match handle:
            case Handle{path, lock, _, state, _}:
              match result:
                case (table, ByteMemTable.Absent{}):
                  do IO<Handle & Result<&1, &1, Error, BatchPrepared>>:
                    pair : Handle & Result<&1, &1, Error, Maybe<&1, Bytes.Bytes>> <-
                      get(Handle{path, lock, table, state,
                        VisibleStats.Stats{0n, 0n}}, key)
                    batch.stats.loop(rest, BatchRead{pair, mutations, entries,
                      original_stats, base_stats, key_bytes})
                case (table, _):
                  batch.stats.loop(rest, BatchNeed{
                    Handle{path, lock, table, state, VisibleStats.Stats{0n, 0n}},
                    mutations, entries, original_stats, base_stats})
        case BatchRead{pair, mutations, entries, original_stats, base_stats, key_bytes}:
          match pair:
            case (handle, Fail{error}):
              IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
                (batch.restore.handle(original_stats, handle), Fail{error}))
            case (Handle{path, lock, table, state, _}, Done{old_value}):
              batch.stats.loop(rest, BatchNeed{
                Handle{path, lock, table, state, VisibleStats.Stats{0n, 0n}},
                mutations, entries, original_stats,
                stats.remove.base.length(base_stats, key_bytes, old_value)})

# Counts records before preparing a state that owns both the original and adjusted aggregates.
def batch.prepare.cloned(
  handle: Handle,
  mutations: List<&1, ByteWal.Mutation>,
  copies: VisibleStats.Stats & VisibleStats.Stats,
  counted: List<&1, ByteMemTable.Entry> & Nat
) -> IO(Handle & Result<&1, &1, Error, BatchPrepared>):
  match handle:
    case Handle{path, lock, table, state, _}:
      match copies:
        case (original_stats, base_stats):
          match counted:
            case (retained_entries, count):
              batch.stats.loop(Nat.add(Nat.mul(Nat.add(count, 1n), 4n), 1n),
                BatchNeed{Handle{path, lock, table, state,
                  VisibleStats.Stats{0n, 0n}}, mutations, retained_entries,
                  original_stats, base_stats})

def batch.prepare(
  handle: Handle,
  mutations: List<&1, ByteWal.Mutation>,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Handle & Result<&1, &1, Error, BatchPrepared>):
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      batch.prepare.cloned(Handle{path, lock, table, state,
        VisibleStats.Stats{0n, 0n}},
        mutations, VisibleStats.clone(base_stats),
        ByteMemTable.count.keep(entries))

def batch.validation.decided(
  handle: Handle,
  entries: List<&1, ByteMemTable.Entry>,
  mutations: List<&1, ByteWal.Mutation>,
  validation: BatchPolicy.Validation
) -> IO(Handle & Result<&1, &1, Error, BatchPrepared>):
  match validation:
    case BatchPolicy.ValidBatch{}:
      batch.prepare(handle, mutations, entries)
    case BatchPolicy.BatchBytesExceeded{}:
      IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
        (handle, Fail{ResourceLimit{}}))
    case BatchPolicy.BatchCountExceeded{}:
      IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
        (handle, Fail{ResourceLimit{}}))
    case _:
      IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
        (handle, Fail{InvalidArgument{}}))

def batch.validation.result(
  handle: Handle,
  entries: List<&1, ByteMemTable.Entry>,
  measured: BatchPolicy.ByteBatchMeasurement
) -> IO(Handle & Result<&1, &1, Error, BatchPrepared>):
  match measured:
    case BatchPolicy.BatchMeasured{mutations, count, encoded_bytes}:
      batch.validation.decided(handle, entries, mutations,
        BatchPolicy.validate_batch(count, encoded_bytes))
    case BatchPolicy.BatchTooMany{}:
      IO.pure(Handle & Result<&1, &1, Error, BatchPrepared>,
        (handle, Fail{ResourceLimit{}}))

def batch.validate(
  handle: Handle,
  mutations: List<&1, ByteWal.Mutation>,
  entries: List<&1, ByteMemTable.Entry>
) -> IO(Handle & Result<&1, &1, Error, BatchPrepared>):
  batch.validation.result(handle, entries,
    BatchPolicy.byte_batch.measure(mutations))

def batch.build.result(
  handle: Handle,
  pair: ByteMemTable.Table & List<&1, ByteWal.Mutation>
) -> IO(Handle & Result<&1, &1, Error, BatchPrepared>):
  match pair:
    case (candidate_table, mutations):
      batch.validate(handle, mutations,
        ByteMemTable.ordered_entries(candidate_table))

def batch.commit.handle(
  stats: VisibleStats.Stats,
  handle: Handle,
  result: Result<&1, &1, Error, Unit>
) -> Handle & Result<&1, &1, Error, Unit>:
  match handle:
    case Handle{path, lock, table, state, _}:
      (Handle{path, lock, table, state, stats}, result)

def batch.commit.choose(
  original_stats: VisibleStats.Stats,
  adjusted_stats: VisibleStats.Stats,
  handle: Handle,
  result: Result<&1, &1, Error, Unit>
) -> Handle & Result<&1, &1, Error, Unit>:
  match result:
    case Done{Unit{}}:
      batch.commit.handle(adjusted_stats, handle, Done{Unit{}})
    case Fail{error}:
      batch.commit.handle(original_stats, handle, Fail{error})

def batch.commit.result(
  original_stats: VisibleStats.Stats,
  adjusted_stats: VisibleStats.Stats,
  pair: Handle & Result<&1, &1, Error, Unit>
) -> Handle & Result<&1, &1, Error, Unit>:
  match pair:
    case (handle, result):
      batch.commit.choose(original_stats, adjusted_stats, handle, result)

def batch.prepare.validated(
  prepared: Handle & Result<&1, &1, Error, BatchPrepared>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match prepared:
    case (next_handle, Fail{error}):
      IO.pure(Handle & Result<&1, &1, Error, Unit>, (next_handle, Fail{error}))
    case (Handle{path, lock, table, state, original_stats}, Done{Prepared{mutations, base_stats}}):
      do IO<Handle & Result<&1, &1, Error, Unit>>:
        pair : Handle & Result<&1, &1, Error, Unit> <-
          write.counted(path, lock, table, state, ByteWal.Batch{mutations})
        return batch.commit.result(original_stats, base_stats, pair)

def batch.prepare.result(
  prepared: Handle & Result<&1, &1, Error, BatchPrepared>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  batch.prepare.validated(prepared)

def batch.prepare.built(
  handle: Handle,
  built: ByteMemTable.Table & List<&1, ByteWal.Mutation>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  do IO<Handle & Result<&1, &1, Error, Unit>>:
    prepared : Handle & Result<&1, &1, Error, BatchPrepared> <-
      batch.build.result(handle, built)
    result : Handle & Result<&1, &1, Error, Unit> <-
      batch.prepare.result(prepared)
    return result

def batch.prepare.start(
  handle: Handle,
  fuel: Nat,
  mutations: List<&1, ByteWal.Mutation>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  batch.prepare.built(handle,
    batch.build(fuel, BatchBuild{mutations, ByteMemTable.empty(), Nil{}}))

def write_batch.validated(
  handle: Handle,
  mutations: List<&1, ByteWal.Mutation>,
  count: Nat
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  batch.prepare.start(handle, Nat.add(Nat.mul(count, 2n), 1n), mutations)

def write_batch.validation.result(
  handle: Handle,
  mutations: List<&1, ByteWal.Mutation>,
  count: Nat,
  validation: BatchPolicy.Validation
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match validation:
    case BatchPolicy.ValidBatch{}: write_batch.validated(handle, mutations, count)
    case BatchPolicy.BatchBytesExceeded{}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (handle, Fail{ResourceLimit{}}))
    case BatchPolicy.BatchCountExceeded{}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (handle, Fail{ResourceLimit{}}))
    case _:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (handle, Fail{InvalidArgument{}}))

def write_batch.validation.counted(
  handle: Handle,
  mutations: List<&1, ByteWal.Mutation>,
  counts: Nat & Nat,
  encoded_bytes: Nat
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match counts:
    case (count, validation_count):
      write_batch.validation.result(handle, mutations, count,
        BatchPolicy.validate_batch(validation_count, encoded_bytes))

def write_batch.measured(
  handle: Handle,
  measured: BatchPolicy.ByteBatchMeasurement
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match measured:
    case BatchPolicy.BatchMeasured{mutations, count, encoded_bytes}:
      write_batch.validation.counted(handle, mutations,
        QueuePolicy.nat.clone.pair(count), encoded_bytes)
    case BatchPolicy.BatchTooMany{}:
      IO.pure(Handle & Result<&1, &1, Error, Unit>,
        (handle, Fail{ResourceLimit{}}))

# Reconciles each unique batch key against the SST before one atomic WAL append.
def write_batch(
  handle: Handle,
  mutations: List<&1, ByteWal.Mutation>
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  write_batch.measured(handle, BatchPolicy.byte_batch.measure(mutations))

def put.keys.retained(
  probe_key: Bytes.Bytes,
  pair: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (read_key, write_key): (probe_key, read_key, write_key)

def put.keys.first(
  pair: Bytes.Bytes & Bytes.Bytes
) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  match pair:
    case (probe_key, retained):
      put.keys.retained(probe_key, ByteMemTable.bytes.clone(retained))

def put.keys(key: Bytes.Bytes) -> Bytes.Bytes & Bytes.Bytes & Bytes.Bytes:
  put.keys.first(ByteMemTable.bytes.clone(key))

def put.absent(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  write_key: Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  write_batch(Handle{path, lock, table, state, base_stats},
    Con{ByteWal.Put{write_key, value}, Nil{}})

def put.probe.absent.nonempty(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match keys:
    case (_, write_key):
      put.absent(path, lock, table, state, base_stats,
        write_key, value)

def put.probe.present(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match keys:
    case (_, write_key):
      write_batch(Handle{path, lock, table, state, base_stats},
        Con{ByteWal.Put{write_key, value}, Nil{}})

def put.probe.absent.count(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes,
  empty: Bool
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match empty:
    case True{}:
      put.probe.present(path, lock, table, state, base_stats, keys, value)
    case False{}:
      put.probe.absent.nonempty(path, lock, table, state, base_stats,
        keys, value)

def put.probe.absent.cloned(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  copies: VisibleStats.Stats & VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match copies:
    case (measured, retained):
      match measured:
        case VisibleStats.Stats{entries, _}:
          put.probe.absent.count(path, lock, table, state, retained,
            keys, value, Nat.is_eq(entries, 0n))

def put.probe.absent(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  put.probe.absent.cloned(path, lock, table, state,
    VisibleStats.clone(base_stats), keys, value)

def put.probe(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  probe: ByteMemTable.Probe,
  keys: Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match probe:
    case ByteMemTable.Absent{}:
      put.probe.absent(path, lock, table, state, base_stats, keys, value)
    case _:
      put.probe.present(path, lock, table, state, base_stats, keys, value)

def put.probed(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  result: ByteMemTable.Table & ByteMemTable.Probe,
  keys: Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match result:
    case (table, probe):
      put.probe(path, lock, table, state, base_stats, probe, keys, value)

def put.keyed(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match keys:
    case (probe_key, (read_key, write_key)):
      put.probed(path, lock, state, base_stats,
        ByteMemTable.probe(table, probe_key),
        (read_key, write_key), value)

# Writes a raw byte key and value after subtracting the SST value it shadows.
def put(handle: Handle, key: Bytes.Bytes, value: Bytes.Bytes) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      put.keyed(path, lock, table, state, base_stats, put.keys(key), value)

def delete.absent(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  delete_key: Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  write_batch(Handle{path, lock, table, state, base_stats},
    Con{ByteWal.Delete{delete_key}, Nil{}})

def delete.probe.absent.nonempty(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match keys:
    case (_, delete_key):
      delete.absent(path, lock, table, state, base_stats, delete_key)

def delete.probe.present(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match keys:
    case (_, delete_key):
      write_batch(Handle{path, lock, table, state, base_stats},
        Con{ByteWal.Delete{delete_key}, Nil{}})

def delete.probe.absent.count(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes,
  empty: Bool
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match empty:
    case True{}:
      delete.probe.present(path, lock, table, state, base_stats, keys)
    case False{}:
      delete.probe.absent.nonempty(path, lock, table, state, base_stats, keys)

def delete.probe.absent.cloned(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  copies: VisibleStats.Stats & VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match copies:
    case (measured, retained):
      match measured:
        case VisibleStats.Stats{entries, _}:
          delete.probe.absent.count(path, lock, table, state, retained,
            keys, Nat.is_eq(entries, 0n))

def delete.probe.absent(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  delete.probe.absent.cloned(path, lock, table, state,
    VisibleStats.clone(base_stats), keys)

def delete.probe(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  probe: ByteMemTable.Probe,
  keys: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match probe:
    case ByteMemTable.Absent{}:
      delete.probe.absent(path, lock, table, state, base_stats, keys)
    case _:
      delete.probe.present(path, lock, table, state, base_stats, keys)

def delete.probed(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  result: ByteMemTable.Table & ByteMemTable.Probe,
  keys: Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match result:
    case (table, probe):
      delete.probe(path, lock, table, state, base_stats, probe, keys)

# Deletes a raw byte key after removing the SST value it shadows.
def delete.keyed(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  keys: Bytes.Bytes & Bytes.Bytes & Bytes.Bytes
) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match keys:
    case (probe_key, (read_key, delete_key)):
      delete.probed(path, lock, state, base_stats,
        ByteMemTable.probe(table, probe_key),
        (read_key, delete_key))

# Deletes a raw byte key after removing the SST value it shadows.
def delete(handle: Handle, key: Bytes.Bytes) -> IO(Handle & Result<&1, &1, Error, Unit>):
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      delete.keyed(path, lock, table, state, base_stats, put.keys(key))

def scan.sst.bounds(bounds: RangeCursor.Bounds) -> SstCursor.Bounds:
  match bounds:
    case RangeCursor.Bounds{lower, upper, prefix}:
      SstCursor.Bounds{lower, upper, prefix}

def scan.sources.opened(
  handle: Handle,
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  opened: Result<&1, &1, U32 & String, SstCursor.Cursor>
) -> IO(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>):
  match opened:
    case Fail{(code, message)}:
      IO.pure(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>,
        (handle, Fail{recovery.error(code, message)}))
    case Done{base}:
      IO.pure(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>,
        (handle, Done{VisibleCursor.open(Some{base}, delta, bounds)}))

def scan.manifest.result(
  +path: String,
  handle: Handle,
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  sst_bounds: SstCursor.Bounds,
  result: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>):
  match result:
    case Fail{ByteManifestIo.Invalid{_}}:
      IO.pure(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>,
        (handle, Fail{Corruption{"byte manifest validation failed"}}))
    case Fail{ByteManifestIo.Host{code, message}}:
      IO.pure(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>,
        (handle, Fail{Io{code, message}}))
    case Done{ByteManifest.Empty{}}:
      IO.pure(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>,
        (handle, Done{VisibleCursor.open(None{}, delta, bounds)}))
    case Done{ByteManifest.GenerationEmpty{}}:
      IO.pure(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>,
        (handle, Done{VisibleCursor.open(None{}, delta, bounds)}))
    case Done{ByteManifest.HasSst{}}:
      do IO<Handle & Result<&1, &1, Error, VisibleCursor.Cursor>>:
        opened : Result<&1, &1, U32 & String, SstCursor.Cursor> <-
          SstCursor.open.trusted(path ++ "/SST", sst_bounds)
        scan.sources.opened(handle, delta, bounds, opened)
    case Done{ByteManifest.GenerationSst{file_id}}:
      do IO<Handle & Result<&1, &1, Error, VisibleCursor.Cursor>>:
        opened : Result<&1, &1, U32 & String, SstCursor.Cursor> <-
          SstCursor.open.trusted(
            ByteManifest.sst.generation.path(path, file_id), sst_bounds)
        scan.sources.opened(handle, delta, bounds, opened)

def scan.path.kept.triple(
  copies: String & String & String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats
) -> String & String & Handle:
  match copies:
    case (exists_path, (sst_path, retained)):
      (exists_path, sst_path, Handle{retained, lock, table, state, base_stats})

def scan.path.kept(handle: Handle) -> String & String & Handle:
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      scan.path.kept.triple(path.clone.triple(path), lock, table, state,
        base_stats)

def scan.exists.start(
  paths: String & String & Handle,
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  sst_bounds: SstCursor.Bounds
) -> IO(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>):
  match paths:
    case (exists_path, (sst_path, handle)):
      do IO<Handle & Result<&1, &1, Error, VisibleCursor.Cursor>>:
        manifest : Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue> <-
          ByteManifestIo.read(exists_path ++ "/MANIFEST")
        scan.manifest.result(sst_path, handle, delta, bounds, sst_bounds, manifest)

def scan.bounds.cloned(
  handle: Handle,
  delta: List<&1, ByteMemTable.Entry>,
  copies: RangeCursor.Bounds & RangeCursor.Bounds
) -> IO(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>):
  match copies:
    case (retained, for_sst):
      scan.exists.start(scan.path.kept(handle), delta, retained,
        scan.sst.bounds(for_sst))

def scan.delta.copied(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  entries: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds
) -> IO(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>):
  match entries:
    case (retained, copied):
      scan.bounds.cloned(
        Handle{path, lock, ByteMemTable.Table{retained}, state, base_stats},
        ByteMemTable.ordered_entries(ByteMemTable.Table{copied}),
        RangeCursor.bounds.clone(bounds))

def scan.open(handle: Handle, bounds: RangeCursor.Bounds) -> IO(Handle & Result<&1, &1, Error, VisibleCursor.Cursor>):
  match handle:
    case Handle{path, lock, ByteMemTable.Table{entries}, state, base_stats}:
      scan.delta.copied(path, lock, state, base_stats,
        ByteMemTable.entries.clone(entries), bounds)

def scan.work_budget.copied(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_entries: Nat & Nat,
  payload_bytes: Nat,
  copies: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Handle & Nat:
  match base_entries:
    case (retained_base_entries, budget_base_entries):
      match copies:
        case (entries, copied):
          +delta_count = List.length(&1, ByteMemTable.Entry, copied)
          (Handle{path, lock, ByteMemTable.Table{entries}, state,
              VisibleStats.Stats{retained_base_entries, payload_bytes}},
            ScanWorkPolicy.writer_transitions(budget_base_entries, delta_count))

def scan.work_budget(handle: Handle) -> Handle & Nat:
  match handle:
    case Handle{path, lock, ByteMemTable.Table{entries}, state,
        VisibleStats.Stats{base_entries, payload_bytes}}:
      scan.work_budget.copied(path, lock, state,
        ScanWorkPolicy.nat.clone.pair(base_entries), payload_bytes,
        ByteMemTable.entries.clone(entries))

def scan.error(error: U32 & String) -> Error:
  match error:
    case (code, message): recovery.error(code, message)

# Clones canonical visible entries so a cursor can advance independently of writes.
def snapshot.entry.value(
  key: Bytes.Bytes,
  pair: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>
) -> ByteMemTable.Entry:
  match pair:
    case (_, copied_value):
      ByteMemTable.Entry{key, copied_value}

def snapshot.entry.key(
  pair: Bytes.Bytes & Bytes.Bytes,
  value: Maybe<&1, Bytes.Bytes>
) -> ByteMemTable.Entry:
  match pair:
    case (_, copied_key):
      snapshot.entry.value(copied_key, ByteMemTable.value.clone(value))

def snapshot.entries(entries: List<&1, ByteMemTable.Entry>) -> List<&1, ByteMemTable.Entry>:
  match entries:
    case Nil{}:
      Nil{}
    case Con{ByteMemTable.Entry{key, value}, tail}:
      Con{snapshot.entry.key(ByteMemTable.bytes.clone(key), value), snapshot.entries(tail)}

# Returns a stable ordered copy while preserving the live database handle.
def snapshot.table(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  cloned: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Handle & List<&1, ByteMemTable.Entry>:
  match cloned:
    case (original, copied):
      (Handle{path, lock, ByteMemTable.Table{original}, state, base_stats},
        ByteMemTable.ordered_entries(ByteMemTable.Table{copied}))

# Clones the ordered visible table while preserving the owned handle.
def snapshot(handle: Handle) -> Handle & List<&1, ByteMemTable.Entry>:
  match handle:
    case Handle{path, lock, ByteMemTable.Table{entries}, state, base_stats}:
      snapshot.table(path, lock, state, base_stats,
        ByteSstFile.entries.clone(entries))

def snapshot.limited.saved(
  pair: Handle & List<&1, ByteMemTable.Entry>
) -> Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>:
  match pair:
    case (handle, entries): (handle, Done{entries})

def snapshot.estimate(base_stats: VisibleStats.Stats, delta_bytes: Nat) -> Nat:
  match base_stats:
    case VisibleStats.Stats{entries, payload_bytes}:
      Nat.add(delta_bytes, Nat.add(payload_bytes, Nat.mul(entries, 32n)))

def snapshot.limited.saved.result(
  handle: Handle,
  result: Result<&1, &1, U32 & String, ByteMemTable.Table>
) -> IO(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>):
  match handle:
    case Handle{path, lock, ByteMemTable.Table{delta}, state, base_stats}:
      match result:
        case Fail{(code, message)}:
          IO.pure(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>,
            (Handle{path, lock, ByteMemTable.Table{delta}, state, base_stats},
              Fail{recovery.error(code, message)}))
        case Done{ByteMemTable.Table{base}}:
          IO.pure(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>,
            snapshot.limited.saved(snapshot.table(path, lock, state, base_stats,
              ByteSstFile.entries.clone(ByteMemTable.compact.live(
                ByteMemTable.append(delta, base))))))

def snapshot.manifest.result.paths(
  paths: String & String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  result: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>):
  match paths:
    case (read_path, retained_path):
      match result:
        case Fail{ByteManifestIo.Invalid{_}}:
          IO.pure(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>,
            (Handle{retained_path, lock, table, state, base_stats},
              Fail{Corruption{"byte manifest validation failed"}}))
        case Fail{ByteManifestIo.Host{code, message}}:
          IO.pure(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>,
            (Handle{retained_path, lock, table, state, base_stats}, Fail{Io{code, message}}))
        case Done{ByteManifest.Empty{}}:
          snapshot.limited.saved.result(
            Handle{retained_path, lock, table, state, base_stats}, Done{ByteMemTable.empty()})
        case Done{ByteManifest.GenerationEmpty{}}:
          snapshot.limited.saved.result(
            Handle{retained_path, lock, table, state, base_stats}, Done{ByteMemTable.empty()})
        case Done{ByteManifest.HasSst{}}:
          do IO<Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>>:
            base : Result<&1, &1, U32 & String, ByteMemTable.Table> <-
              ByteSstIo.read(read_path ++ "/SST")
            snapshot.limited.saved.result(
              Handle{retained_path, lock, table, state, base_stats}, base)
        case Done{ByteManifest.GenerationSst{file_id}}:
          do IO<Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>>:
            base : Result<&1, &1, U32 & String, ByteMemTable.Table> <-
              ByteSstIo.read(ByteManifest.sst.generation.path(read_path, file_id))
            snapshot.limited.saved.result(
              Handle{retained_path, lock, table, state, base_stats}, base)

def snapshot.manifest.result(
  handle: Handle,
  result: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>):
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      snapshot.manifest.result.paths(path.clone.pair(path), lock, table,
        state, base_stats, result)

def snapshot.limited.admitted.paths(
  paths: String & String & String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  decision: SnapshotPolicy.Decision
) -> IO(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>):
  match paths:
    case (manifest_path, (read_path, retained_path)):
      match decision:
        case SnapshotPolicy.ResourceLimit{}:
          IO.pure(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>,
            (Handle{retained_path, lock, table, state, base_stats}, Fail{ResourceLimit{}}))
        case SnapshotPolicy.Retained{_, _}:
          do IO<Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>>:
            manifest : Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue> <-
              ByteManifestIo.read(manifest_path ++ "/MANIFEST")
            snapshot.manifest.result.paths((read_path, retained_path), lock,
              table, state, base_stats, manifest)

def snapshot.limited.admitted(
  handle: Handle,
  decision: SnapshotPolicy.Decision
) -> IO(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>):
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      snapshot.limited.admitted.paths(path.clone.triple(path), lock, table,
        state, base_stats, decision)

# Preflights retained bytes before reading the published SST snapshot.
def snapshot.limited.retained.stats(
  +path: String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  stats: VisibleStats.Stats & VisibleStats.Stats,
  delta_bytes: Nat,
  max_bytes: Nat
) -> IO(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>):
  match stats:
    case (for_estimate, for_handle):
          snapshot.limited.admitted(
            Handle{path, lock, table, state, for_handle},
            SnapshotPolicy.reserve(0n, 0n,
              snapshot.estimate(for_estimate, delta_bytes), 1n, max_bytes))

def snapshot.limited.retained(
  handle: Handle,
  retained: ByteMemTable.Table & Nat,
  max_bytes: Nat
) -> IO(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>):
  match handle:
    case Handle{+path, lock, _, state, +base_stats}:
      match retained:
        case (table, delta_bytes):
          snapshot.limited.retained.stats(path, lock, table, state,
            VisibleStats.clone(base_stats), delta_bytes, max_bytes)

# Preflights retained bytes before reading the published SST snapshot.
def snapshot_limited(
  max_bytes: Nat,
  handle: Handle
) -> IO(Handle & Result<&1, &1, Error, List<&1, ByteMemTable.Entry>>):
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      snapshot.limited.retained(
        Handle{path, lock, ByteMemTable.empty(), state, base_stats},
        ByteMemTable.retained_bytes.keep(table), max_bytes)

def snapshot.root.manifest.result(
  read_path: String,
  handle: Handle,
  delta: List<&1, ByteMemTable.Entry>,
  result: Result<&1, &1, ByteManifestIo.Error, ByteManifest.ManifestValue>
) -> IO(Handle & Result<&1, &1, Error, SnapshotRoot>):
  match result:
    case Fail{ByteManifestIo.Invalid{_}}:
      IO.pure(Handle & Result<&1, &1, Error, SnapshotRoot>,
        (handle, Fail{Corruption{"byte manifest validation failed"}}))
    case Fail{ByteManifestIo.Host{code, message}}:
      IO.pure(Handle & Result<&1, &1, Error, SnapshotRoot>,
        (handle, Fail{Io{code, message}}))
    case Done{ByteManifest.Empty{}}:
      IO.pure(Handle & Result<&1, &1, Error, SnapshotRoot>,
        (handle, Done{SnapshotRoot{None{}, delta}}))
    case Done{ByteManifest.GenerationEmpty{}}:
      IO.pure(Handle & Result<&1, &1, Error, SnapshotRoot>,
        (handle, Done{SnapshotRoot{None{}, delta}}))
    case Done{ByteManifest.HasSst{}}:
      IO.pure(Handle & Result<&1, &1, Error, SnapshotRoot>,
        (handle, Done{SnapshotRoot{Some{read_path ++ "/SST"}, delta}}))
    case Done{ByteManifest.GenerationSst{file_id}}:
      IO.pure(Handle & Result<&1, &1, Error, SnapshotRoot>,
        (handle, Done{SnapshotRoot{Some{
          ByteManifest.sst.generation.path(read_path, file_id)}, delta}}))

def snapshot.root.manifest(
  paths: String & String,
  handle: Handle,
  delta: List<&1, ByteMemTable.Entry>
) -> IO(Handle & Result<&1, &1, Error, SnapshotRoot>):
  match paths:
    case (manifest_path, read_path):
      do IO<Handle & Result<&1, &1, Error, SnapshotRoot>>:
        manifest : Result<&1, &1, ByteManifestIo.Error,
          ByteManifest.ManifestValue> <-
            ByteManifestIo.read(manifest_path ++ "/MANIFEST")
        snapshot.root.manifest.result(read_path, handle, delta, manifest)

def snapshot.root.snapshot.paths(
  paths: String & String & String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  delta: List<&1, ByteMemTable.Entry>
) -> IO(Handle & Result<&1, &1, Error, SnapshotRoot>):
  match paths:
    case (manifest_path, (read_path, retained_path)):
      snapshot.root.manifest((manifest_path, read_path),
        Handle{retained_path, lock, table, state, base_stats}, delta)

def snapshot.root.snapshot.delta(
  handle: Handle,
  copied: List<&1, ByteMemTable.Entry>,
  decision: SnapshotPolicy.Decision
) -> IO(Handle & Result<&1, &1, Error, SnapshotRoot>):
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      match decision:
        case SnapshotPolicy.ResourceLimit{}:
          IO.pure(Handle & Result<&1, &1, Error, SnapshotRoot>,
            (Handle{path, lock, table, state, base_stats}, Fail{ResourceLimit{}}))
        case SnapshotPolicy.Retained{_, _}:
          snapshot.root.snapshot.paths(path.clone.triple(path), lock, table,
            state, base_stats,
            ByteMemTable.ordered_entries(ByteMemTable.Table{copied}))

def snapshot.root.preflight.estimated(
  handle: Handle,
  stats: VisibleStats.Stats,
  copied: List<&1, ByteMemTable.Entry>,
  delta_bytes: Nat,
  max_bytes: Nat
) -> IO(Handle & Result<&1, &1, Error, SnapshotRoot>):
  snapshot.root.snapshot.delta(handle, copied,
    SnapshotPolicy.reserve(0n, 0n,
      snapshot.estimate(stats, delta_bytes), 1n, max_bytes))

def snapshot.root.preflight.ready(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  stats: VisibleStats.Stats & VisibleStats.Stats,
  entries: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>,
  delta_bytes: Nat,
  max_bytes: Nat
) -> IO(Handle & Result<&1, &1, Error, SnapshotRoot>):
  match stats:
    case (for_handle, for_estimate):
      match entries:
        case (live_entries, copied_entries):
          snapshot.root.preflight.estimated(
            Handle{path, lock, ByteMemTable.Table{live_entries}, state,
              for_handle}, for_estimate, copied_entries, delta_bytes, max_bytes)

def snapshot.root.preflight(
  handle: Handle,
  delta_bytes: Nat,
  max_bytes: Nat
) -> IO(Handle & Result<&1, &1, Error, SnapshotRoot>):
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      match table:
        case ByteMemTable.Table{entries}:
          snapshot.root.preflight.ready(path, lock, state,
            VisibleStats.clone(base_stats), ByteMemTable.entries.clone(entries),
            delta_bytes, max_bytes)

def snapshot.root.retained(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  retained: ByteMemTable.Table & Nat,
  max_bytes: Nat
) -> IO(Handle & Result<&1, &1, Error, SnapshotRoot>):
  match retained:
    case (table, delta_bytes):
      snapshot.root.preflight(Handle{path, lock, table, state, base_stats},
        delta_bytes, max_bytes)

# Captures the active delta and immutable SST path within the retained-byte limit.
def snapshot_root_limited(
  max_bytes: Nat,
  handle: Handle
) -> IO(Handle & Result<&1, &1, Error, SnapshotRoot>):
  match handle:
    case Handle{path, lock, table, state, base_stats}:
      snapshot.root.retained(path, lock, state, base_stats,
        ByteMemTable.retained_bytes.keep(table), max_bytes)

def snapshot.root.sst.bounds(bounds: RangeCursor.Bounds) -> SstCursor.Bounds:
  match bounds:
    case RangeCursor.Bounds{lower, upper, prefix}:
      SstCursor.Bounds{lower, upper, prefix}

def snapshot.root.cursor.opened(
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  opened: Result<&1, &1, U32 & String, SstCursor.Cursor>
) -> IO(Result<&1, &1, Error, VisibleCursor.Cursor>):
  match opened:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, VisibleCursor.Cursor>,
        Fail{recovery.error(code, message)})
    case Done{base}:
      IO.pure(Result<&1, &1, Error, VisibleCursor.Cursor>,
        Done{VisibleCursor.open(Some{base}, delta, bounds)})

def snapshot.root.cursor.open.copied(
  bounds: RangeCursor.Bounds & RangeCursor.Bounds,
  root: SnapshotRoot
) -> IO(Result<&1, &1, Error, VisibleCursor.Cursor>):
  match bounds:
    case (visible_bounds, sst_bounds):
      match root:
        case SnapshotRoot{sst_path, delta}:
          match sst_path:
            case None{}:
              IO.pure(Result<&1, &1, Error, VisibleCursor.Cursor>,
                Done{VisibleCursor.open(None{}, delta, visible_bounds)})
            case Some{path}:
              do IO<Result<&1, &1, Error, VisibleCursor.Cursor>>:
                opened : Result<&1, &1, U32 & String, SstCursor.Cursor> <-
                  SstCursor.open.trusted(path,
                    snapshot.root.sst.bounds(sst_bounds))
                snapshot.root.cursor.opened(delta, visible_bounds, opened)

def snapshot.root.cursor.open(
  root: SnapshotRoot,
  bounds: RangeCursor.Bounds
) -> IO(Result<&1, &1, Error, VisibleCursor.Cursor>):
  snapshot.root.cursor.open.copied(RangeCursor.bounds.clone(bounds), root)

# Restores a read handle after byte lookup.
def close.released(
  result: Result<&1, &1, DurableError.Error, Unit>
) -> Result<&1, &1, Error, Unit>:
  match result:
    case Fail{error}:
      Fail{lock.error(error)}
    case Done{Unit{}}:
      Done{Unit{}}

# Releases database ownership and consumes the handle.
def close(handle: Handle) -> IO(Result<&1, &1, Error, Unit>):
  match handle:
    case Handle{path, lock, _, _, _}:
      do IO<Result<&1, &1, Error, Unit>>:
        result : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "close", path)
        return close.released(result)

def stats.aggregate.copies(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  original: List<&1, ByteMemTable.Entry>,
  copies: VisibleStats.Stats & VisibleStats.Stats,
  delta_stats: VisibleStats.Stats
) -> Handle & Stats:
  match copies:
    case (measured_base, retained_base):
      match measured_base:
        case VisibleStats.Stats{base_entries, base_payload}:
          match delta_stats:
            case VisibleStats.Stats{delta_entries, delta_payload}:
              (Handle{path, lock, ByteMemTable.Table{original}, state, retained_base},
                Stats{Nat.add(base_entries, delta_entries),
                  Nat.add(base_payload, delta_payload)})



def stats.aggregate(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  original: List<&1, ByteMemTable.Entry>,
  delta_stats: VisibleStats.Stats
) -> Handle & Stats:
  stats.aggregate.copies(path, lock, state, original,
    VisibleStats.clone(base_stats), delta_stats)

def stats.measured.result(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  original: List<&1, ByteMemTable.Entry>,
  measured: VisibleStats.Stats
) -> Handle & Stats:
  match measured:
    case VisibleStats.Stats{entries, payload_bytes}:
      stats.aggregate(path, lock, state, base_stats, original,
        VisibleStats.Stats{entries, payload_bytes})

def stats.visible(
  entries: List<&1, ByteMemTable.Entry>,
  current: VisibleStats.Stats
) -> VisibleStats.Stats:
  match entries:
    case Nil{}: current
    case Con{ByteMemTable.Entry{Bytes.Bytes{+len, _}, val}, tail}:
      match val:
        case None{}: stats.visible(tail, current)
        case Some{Bytes.Bytes{+value_len, _}}:
          stats.visible(tail, VisibleStats.result(VisibleStats.apply(current,
            U32.to_nat(len), None{}, Some{U32.to_nat(value_len)})))

def stats.measured(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  original: List<&1, ByteMemTable.Entry>,
  visible: List<&1, ByteMemTable.Entry>
) -> Handle & Stats:
  stats.measured.result(path, lock, state, base_stats, original,
    stats.visible(visible, VisibleStats.Stats{0n, 0n}))

def stats.canonical(
  +path: String,
  lock: DbLock.Lock,
  state: HandleState,
  base_stats: VisibleStats.Stats,
  pair: List<&1, ByteMemTable.Entry> & List<&1, ByteMemTable.Entry>
) -> Handle & Stats:
  match pair:
    case (original, working):
      stats.measured(path, lock, state, base_stats, original,
        ByteMemTable.compact.live(
          ByteMemTable.ordered_entries(ByteMemTable.Table{working})))

# Counts visible entries and exact key/value payload bytes.
def stats(handle: Handle) -> Handle & Stats:
  match handle:
    case Handle{path, lock, ByteMemTable.Table{entries}, state, base_stats}:
      stats.canonical(path, lock, state, base_stats,
        ByteSstFile.entries.clone(entries))
