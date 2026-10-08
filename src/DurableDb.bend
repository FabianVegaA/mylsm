import Base
import ./Db.bend as Db
import ./DbLock.bend as DbLock
import ./DbIo.bend as DbIo
import ./DurableCommit.bend as Commit
import ./DurableError.bend as DurableError
import ./DurableDbPolicy.bend as Policy
import ./Fs.bend as Fs
import ./Recover.bend as Recover
import ./Flush.bend as Flush
import ./Manifest.bend as Manifest
import ./CompactIo.bend as Compact
import ./Wal.bend as Wal
import ./DurableBatchPolicy.bend as BatchPolicy
import ./MemTable.bend as MemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Owns the database, lock, and lifecycle state.
type Handle is Type:
  Handle{path: String, lock: DbLock.Lock, db: Db.Db, state: Policy.HandleState, operation_errors: Nat}

# Collects bounded database, cache, and error counters.
type Stats is Data:
  Stats{active_bytes: Nat, wal_bytes: Nat, memtable_entries: Nat, memtable_payload_bytes: Nat, cache_entries: Nat, operation_errors: Nat, state: Policy.HandleState}

# Tracks whether post-commit maintenance is safe to continue.
type Maintenance is Data:
  Maintained{}
  Pending{error: DurableError.Error}

# Separates commit confirmation from maintenance status.
type WriteOutcome is Data:
  WriteOutcome{maintenance: Maintenance}

def create_error.kind(exists: Bool, +code: U32, message: String, +path: String) -> DurableError.Error:
  match exists:
    case True{}:
      DurableError.Error{DurableError.AlreadyExists{}, "create", path, code, message}
    case False{}:
      DurableError.classify_open(DurableError.OpenHostFailure{code, message}, "create", path)

def create_error.code(+code: U32, message: String, +path: String) -> DurableError.Error:
  create_error.kind(U32.is_eq(code, 17), code, message, path)

def open_error.kind(missing: Bool, code: U32, message: String, operation: String, path: String) -> DurableError.Error:
  match missing:
    case True{}:
      DurableError.Error{DurableError.NotFound{}, operation, path, code, message}
    case False{}:
      DurableError.classify_recovery(code, message, operation, path)

# Performs the open error operation and returns its result.
def open_error(+code: U32, message: String, operation: String, path: String) -> DurableError.Error:
  open_error.kind(U32.is_eq(code, 2), code, message, operation, path)

# Performs the open result operation and returns its result.
def open_result(
  result: Result<&1, &1, U32 & String, Db.Db>,
  lock: DbLock.Lock,
  operation: String,
  +path: String
) -> IO(Result<&1, &1, DurableError.Error, Handle>):
  match result:
    case Fail{(code, message)}:
      do IO<Result<&1, &1, DurableError.Error, Handle>>:
        _released : Result<&1, &1, DurableError.Error, Unit> <- DbLock.release(lock, "close", path)
        return Fail{open_error(code, message, operation, path)}
    case Done{db}:
      IO.pure(Result<&1, &1, DurableError.Error, Handle>,
        Done{Handle{path, lock, db, Policy.Open{}, 0n}})

# Continues existing-open recovery after acquiring the database lock.
def locked_result(
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>,
  operation: String,
  +path: String
) -> IO(Result<&1, &1, DurableError.Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, DurableError.Error, Handle>, Fail{error})
    case Done{lock}:
      do IO<Result<&1, &1, DurableError.Error, Handle>>:
        opened : Result<&1, &1, U32 & String, Db.Db> <- Recover.open_existing_locked(path)
        open_result(opened, lock, operation, path)

# Acquires ownership only after validating the existing Manifest.
def preflight_manifest(
  manifest: Result<&1, &1, U32 & String, Manifest.Manifest>,
  +path: String
) -> IO(Result<&1, &1, DurableError.Error, Handle>):
  match manifest:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, DurableError.Error, Handle>,
        Fail{DurableError.classify_recovery(code, message, "open_existing", path)})
    case Done{_}:
      do IO<Result<&1, &1, DurableError.Error, Handle>>:
        acquired : Result<&1, &1, DurableError.Error, DbLock.Lock> <- DbLock.acquire(path, "open_existing")
        locked_result(acquired, "open_existing", path)

# Rejects a missing Manifest or begins validating the existing one.
def preflight_result(
  result: Result<&1, &1, U32 & String, Bool>,
  +path: String
) -> IO(Result<&1, &1, DurableError.Error, Handle>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, DurableError.Error, Handle>,
        Fail{open_error(code, message, "open_existing", path)})
    case Done{False{}}:
      IO.pure(Result<&1, &1, DurableError.Error, Handle>,
        Fail{DurableError.Error{DurableError.NotFound{}, "open_existing", path, 2, "manifest missing"}})
    case Done{True{}}:
      do IO<Result<&1, &1, DurableError.Error, Handle>>:
        manifest : Result<&1, &1, U32 & String, Manifest.Manifest> <- Flush.load_mfst(path ++ "/MANIFEST")
        preflight_manifest(manifest, path)

# Opens and recovers an existing database under its lock.
def open_existing(+path: String) -> IO(Result<&1, &1, DurableError.Error, Handle>):
  do IO<Result<&1, &1, DurableError.Error, Handle>>:
    present : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path ++ "/MANIFEST")
    preflight_result(present, path)

# Performs the create locked operation and returns its result.
def create_locked(
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>,
  +path: String
) -> IO(Result<&1, &1, DurableError.Error, Handle>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, DurableError.Error, Handle>, Fail{error})
    case Done{lock}:
      do IO<Result<&1, &1, DurableError.Error, Handle>>:
        initialized : Result<&1, &1, U32 & String, Db.Db> <- Recover.create_locked(path)
        open_result(initialized, lock, "create", path)

# Acquires ownership after reserving the new database directory.
def created_dir(
  result: Result<&1, &1, U32 & String, Unit>,
  +path: String
) -> IO(Result<&1, &1, DurableError.Error, Handle>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, DurableError.Error, Handle>,
        Fail{create_error.code(code, message, path)})
    case Done{Unit{}}:
      do IO<Result<&1, &1, DurableError.Error, Handle>>:
        acquired : Result<&1, &1, DurableError.Error, DbLock.Lock> <- DbLock.acquire(path, "create")
        create_locked(acquired, path)

# Creates a database and returns its owned durable handle.
def create(+path: String) -> IO(Result<&1, &1, DurableError.Error, Handle>):
  do IO<Result<&1, &1, DurableError.Error, Handle>>:
    reserved : Result<&1, &1, U32 & String, Unit> <- Fs.make_dir(path)
    created_dir(reserved, path)

# Closes the durable handle and releases its database lock.
def close(handle: Handle) -> IO(Result<&1, &1, DurableError.Error, Unit>):
  match handle:
    case Handle{path, lock, _, _, _}:
      DbLock.release(lock, "close", path)

# Returns a value for readable handles and rejects reads after uncertain commit.
def get_result(
  state: Policy.HandleState,
  pair: Db.Db & Maybe<&2, String>,
  lock: DbLock.Lock,
  +operation_errors: Nat,
  +path: String
) -> Handle & Result<&1, &1, DurableError.Error, Maybe<&2, String>>:
  match state:
    case Policy.Open{}:
      match pair:
        case (db, value):
          (Handle{path, lock, db, Policy.Open{}, operation_errors}, Done{value})
    case Policy.Poisoned{}:
      match pair:
        case (db, _):
          (Handle{path, lock, db, Policy.Poisoned{}, Policy.next_operation_errors(operation_errors)},
            Fail{DurableError.Error{
              DurableError.CommitUnknown{}, "get", path, 0, "handle requires recovery"
            }})
    case Policy.MaintenanceBlocked{}:
      match pair:
        case (db, value):
          (Handle{path, lock, db, Policy.MaintenanceBlocked{}, operation_errors}, Done{value})

# Reads a key from the owned durable database handle.
def get(handle: Handle, +key: String) -> IO(Handle & Result<&1, &1, DurableError.Error, Maybe<&2, String>>):
  match handle:
    case Handle{path, lock, db, state, operation_errors}:
      IO.pure(Handle & Result<&1, &1, DurableError.Error, Maybe<&2, String>>,
        get_result(state, Db.db_get_cached(db, key), lock, operation_errors, path))

# Preserves the confirmed commit when post-commit maintenance fails.
def maintenance_after_commit(
  result: Result<&1, &1, U32 & String, Db.Db>,
  +committed: Db.Db,
  lock: DbLock.Lock,
  operation_errors: Nat,
  +path: String
) -> IO(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>,
        (Handle{path, lock, committed, Policy.MaintenanceBlocked{}, Policy.next_operation_errors(operation_errors)},
          Done{WriteOutcome{Pending{DurableError.Error{DurableError.Io{}, "maintain", path, code, message}}}}))
    case Done{db}:
      IO.pure(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>,
        (Handle{path, lock, db, Policy.Open{}, operation_errors}, Done{WriteOutcome{Maintained{}}}))

# Maps WAL encoding limits to public write-validation causes.
def encoding_rejected_cause(error: Wal.Error) -> DurableError.WriteCause:
  match error:
    case Wal.TooLarge{}:
      DurableError.WriteLimitReached{}
    case _:
      DurableError.ValidationFailure{}

# Updates handle state from the WAL commit stage and maintains durable commits.
def committed_result(
  committed: Db.Db & Commit.Stage,
  lock: DbLock.Lock,
  operation_errors: Nat,
  +path: String
) -> IO(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>):
  match committed:
    case (db, Commit.EncodingRejected{error}):
      IO.pure(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>,
        (Handle{path, lock, db, Policy.Open{}, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.classify_write(
          DurableError.BeforeAppend{}, encoding_rejected_cause(error), "write", path)}))
    case (db, Commit.AppendRejected{code, message}):
      IO.pure(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>,
        (Handle{path, lock, db, Policy.Open{}, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.classify_write(
          DurableError.BeforeAppend{}, DurableError.WriteHostFailure{code, message}, "write", path)}))
    case (db, Commit.AppendUnknown{code, message}):
      IO.pure(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>,
        (Handle{path, lock, db, Policy.Poisoned{}, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.Error{
          DurableError.CommitUnknown{}, "write", path, code, message}}))
    case (+changed, Commit.DurableAppend{}):
      do IO<Handle & Result<&1, &1, DurableError.Error, WriteOutcome>>:
        maintenance : Result<&1, &1, U32 & String, Db.Db> <- Recover.maintain(changed)
        outcome : Handle & Result<&1, &1, DurableError.Error, WriteOutcome> <- maintenance_after_commit(maintenance, changed, lock, operation_errors, path)
        return outcome

# Commits a validated mutation batch and returns the updated owned handle.
def batch_result(
  +db: Db.Db,
  batch: Wal.Batch,
  lock: DbLock.Lock,
  operation_errors: Nat,
  +path: String,
) -> IO(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>):
  do IO<Handle & Result<&1, &1, DurableError.Error, WriteOutcome>>:
    committed : Db.Db & Commit.Stage <- DbIo.db_write_durable(db, batch)
    outcome : Handle & Result<&1, &1, DurableError.Error, WriteOutcome> <- committed_result(committed, lock, operation_errors, path)
    return outcome

# Rejects empty and oversized batches before WAL access.
def batch_count_result(
  +db: Db.Db,
  muts: List<&2, Wal.Mut>,
  lock: DbLock.Lock,
  operation_errors: Nat,
  +path: String,
  validation: BatchPolicy.Validation,
) -> IO(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>):
  match validation:
    case BatchPolicy.ValidBatch{}:
      batch_result(db, Wal.Batch{muts}, lock, operation_errors, path)
    case BatchPolicy.EmptyBatch{}:
      IO.pure(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>,
        (Handle{path, lock, db, Policy.Open{}, Policy.next_operation_errors(operation_errors)},
          Fail{DurableError.Error{
            DurableError.InvalidArgument{}, "write", path, 0, "empty batch"
          }}))
    case BatchPolicy.BatchCountExceeded{}:
      IO.pure(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>,
        (Handle{path, lock, db, Policy.Open{}, Policy.next_operation_errors(operation_errors)},
          Fail{DurableError.Error{
            DurableError.ResourceLimit{}, "write", path, 0, "batch mutation count exceeds 256"
          }}))
# Validates the mutation count before attempting a commit.
def batch_count(
  +db: Db.Db,
  +muts: List<&2, Wal.Mut>,
  lock: DbLock.Lock,
  operation_errors: Nat,
  +path: String,
) -> IO(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>):
  batch_count_result(db, muts, lock, operation_errors, path, BatchPolicy.validate_count(List.length(&2, Wal.Mut, muts)))

# Validates and commits a public mutation batch atomically.
def write_batch(
  handle: Handle,
  muts: List<&2, Wal.Mut>,
) -> IO(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>):
  match handle:
    case Handle{+path, lock, db, state, operation_errors}:
      match state:
        case Policy.Open{}:
          batch_count(db, muts, lock, operation_errors, path)
        case Policy.Poisoned{}:
          IO.pure(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>,
            (Handle{path, lock, db, Policy.Poisoned{}, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.Error{
              DurableError.CommitUnknown{}, "write", path, 0, "handle requires recovery"}}))
        case Policy.MaintenanceBlocked{}:
          IO.pure(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>,
            (Handle{path, lock, db, Policy.MaintenanceBlocked{}, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.Error{
              DurableError.Io{}, "write", path, 0, "maintenance requires recovery"}}))


# Writes one key and value through the durable handle.
def put(handle: Handle, +key: String, +value: String) -> IO(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>):
  write_batch(handle, Con{Wal.Put{key, value}, Nil{}})

# Deletes one key through the durable handle.
def delete(handle: Handle, +key: String) -> IO(Handle & Result<&1, &1, DurableError.Error, WriteOutcome>):
  write_batch(handle, Con{Wal.Del{key}, Nil{}})

# Preserves the original database when maintenance fails.
def maintenance_result(
  result: Result<&1, &1, U32 & String, Db.Db>,
  +original: Db.Db,
  operation: String,
  lock: DbLock.Lock,
  operation_errors: Nat,
  +path: String
) -> Handle & Result<&1, &1, DurableError.Error, Unit>:
  match result:
    case Fail{(code, message)}:
      (Handle{path, lock, original, Policy.MaintenanceBlocked{}, Policy.next_operation_errors(operation_errors)},
        Fail{DurableError.Error{DurableError.Io{}, operation, path, code, message}})
    case Done{db}:
      (Handle{path, lock, db, Policy.Open{}, operation_errors}, Done{Unit{}})

# Flushes the database and updates handle state from the result.
def flush_result(
  +db: Db.Db,
  lock: DbLock.Lock,
  operation_errors: Nat,
  +path: String
) -> IO(Handle & Result<&1, &1, DurableError.Error, Unit>):
  do IO<Handle & Result<&1, &1, DurableError.Error, Unit>>:
    result : Result<&1, &1, U32 & String, Db.Db> <- Flush.flush(db)
    return maintenance_result(result, db, "flush", lock, operation_errors, path)

# Compacts the database and updates handle state from the result.
def compact_result(
  +db: Db.Db,
  lock: DbLock.Lock,
  operation_errors: Nat,
  +path: String,
) -> IO(Handle & Result<&1, &1, DurableError.Error, Unit>):
  do IO<Handle & Result<&1, &1, DurableError.Error, Unit>>:
    result : Result<&1, &1, U32 & String, Db.Db> <- Compact.compact(db)
    return maintenance_result(result, db, "compact", lock, operation_errors, path)

# Flushes the durable handle and returns maintenance status.
def flush(handle: Handle) -> IO(Handle & Result<&1, &1, DurableError.Error, Unit>):
  match handle:
    case Handle{+path, lock, db, Policy.Open{}, operation_errors}:
      flush_result(db, lock, operation_errors, path)
    case Handle{+path, lock, db, Policy.Poisoned{}, operation_errors}:
      IO.pure(Handle & Result<&1, &1, DurableError.Error, Unit>,
        (Handle{path, lock, db, Policy.Poisoned{}, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.Error{
          DurableError.CommitUnknown{}, "flush", path, 0, "handle requires recovery"}}))
    case Handle{+path, lock, db, Policy.MaintenanceBlocked{}, operation_errors}:
      IO.pure(Handle & Result<&1, &1, DurableError.Error, Unit>,
        (Handle{path, lock, db, Policy.MaintenanceBlocked{}, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.Error{
          DurableError.Io{}, "flush", path, 0, "maintenance requires recovery"}}))

# Compacts the durable handle and returns maintenance status.
def compact(handle: Handle) -> IO(Handle & Result<&1, &1, DurableError.Error, Unit>):
  match handle:
    case Handle{+path, lock, db, Policy.Open{}, operation_errors}:
      compact_result(db, lock, operation_errors, path)
    case Handle{+path, lock, db, Policy.Poisoned{}, operation_errors}:
      IO.pure(Handle & Result<&1, &1, DurableError.Error, Unit>,
        (Handle{path, lock, db, Policy.Poisoned{}, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.Error{
          DurableError.CommitUnknown{}, "compact", path, 0, "handle requires recovery"}}))
    case Handle{+path, lock, db, Policy.MaintenanceBlocked{}, operation_errors}:
      IO.pure(Handle & Result<&1, &1, DurableError.Error, Unit>,
        (Handle{path, lock, db, Policy.MaintenanceBlocked{}, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.Error{
          DurableError.Io{}, "compact", path, 0, "maintenance requires recovery"}}))

# Tracks directory entries while collecting active-file sizes.
type StatsNamesState is Type:
  StatsNames{names: List<&2, String>, dir: String, total: Nat}
  StatsNamesSized{result: Result<&1, &1, U32 & String, Nat>, names: List<&2, String>, dir: String, total: Nat}

# Sums file sizes for the supplied directory entries within a fixed budget.
def stats_names(fuel: Nat, state: StatsNamesState) -> IO(Result<&1, &1, U32 & String, Nat>):
  match fuel:
    case 0n:
      IO.pure(Result<&1, &1, U32 & String, Nat>, Fail{(7, "active-byte stat limit exceeded")})
    case 1n+rest:
      match state:
        case StatsNames{names, +dir, total}:
          match names:
            case Nil{}:
              IO.pure(Result<&1, &1, U32 & String, Nat>, Done{total})
            case Con{name, tail}:
              do IO<Result<&1, &1, U32 & String, Nat>>:
                size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(dir ++ "/" ++ name)
                stats_names(rest, StatsNamesSized{size, tail, dir, total})
        case StatsNamesSized{result, names, +dir, total}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, Nat>, Fail{error})
            case Done{size}:
              stats_names(rest, StatsNames{names, dir, Nat.add(total, size)})

# Tracks Manifest levels while collecting active-file sizes.
type StatsLevelsState is Type:
  StatsLevels{levels: List<&2, List<&2, String>>, index: Nat, dir: String, total: Nat}
  StatsLevelsSized{result: Result<&1, &1, U32 & String, Nat>, levels: List<&2, List<&2, String>>, index: Nat, dir: String, total: Nat}

# Sums published SSTable sizes across Manifest levels within a fixed budget.
def stats_levels(fuel: Nat, state: StatsLevelsState) -> IO(Result<&1, &1, U32 & String, Nat>):
  match fuel:
    case 0n:
      IO.pure(Result<&1, &1, U32 & String, Nat>, Fail{(7, "active-byte stat limit exceeded")})
    case 1n+rest:
      match state:
        case StatsLevels{levels, +index, +dir, total}:
          match levels:
            case Nil{}:
              IO.pure(Result<&1, &1, U32 & String, Nat>, Done{total})
            case Con{+names, tail}:
              +level_dir = dir ++ "/l" ++ Nat.show(index)
              do IO<Result<&1, &1, U32 & String, Nat>>:
                files : Result<&1, &1, U32 & String, Nat> <- stats_names(
                  Nat.add(Nat.mul(2n, List.length(&2, String, names)), 1n),
                  StatsNames{names, level_dir, 0n})
                stats_levels(rest, StatsLevelsSized{files, tail, Nat.add(index, 1n), dir, total})
        case StatsLevelsSized{result, levels, index, +dir, total}:
          match result:
            case Fail{error}:
              IO.pure(Result<&1, &1, U32 & String, Nat>, Fail{error})
            case Done{size}:
              stats_levels(rest, StatsLevels{levels, index, dir, Nat.add(total, size)})

# Adds the sizes of all published SSTables to the Manifest size.
def stats_active_manifest_size(
  result: Result<&1, &1, U32 & String, Nat>,
  +levels: List<&2, List<&2, String>>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Nat>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Nat>, Fail{error})
    case Done{size}:
      stats_levels(Nat.add(Nat.mul(2n, List.length(&2, List<&2, String>, levels)), 1n),
        StatsLevels{levels, 0n, path, size})

# Reads the Manifest and sums only the files it references.
def stats_active_manifest(
  result: Result<&1, &1, U32 & String, Manifest.Manifest>,
  +path: String
) -> IO(Result<&1, &1, U32 & String, Nat>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, U32 & String, Nat>, Fail{error})
    case Done{Manifest.M{levels}}:
      do IO<Result<&1, &1, U32 & String, Nat>>:
        manifest_bytes : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/MANIFEST")
        stats_active_manifest_size(manifest_bytes, levels, path)

# Builds counters from file sizes and the in-memory database state.
def stats_result(
  results: Result<&1, &1, U32 & String, Nat> & Result<&1, &1, U32 & String, Nat>,
  +db: Db.Db,
  +state: Policy.HandleState,
  lock: DbLock.Lock,
  +operation_errors: Nat,
  +path: String
) -> Handle & Result<&1, &1, DurableError.Error, Stats>:
  match results:
    case (Fail{(code, message)}, _):
      (Handle{path, lock, db, state, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.classify_recovery(code, message, "stats", path)})
    case (_, Fail{(code, message)}):
      (Handle{path, lock, db, state, Policy.next_operation_errors(operation_errors)}, Fail{DurableError.Error{DurableError.Io{}, "stats", path, code, message}})
    case (Done{active_bytes}, Done{wal_bytes}):
      match db:
        case Db.Db{_, mem, frozen, _, bcache, _, _, _, mem_count, frozen_count}:
          (Handle{path, lock, db, state, operation_errors}, Done{Stats{
            active_bytes, wal_bytes, Nat.add(mem_count, frozen_count),
            Nat.add(MemTable.payload_bytes(mem), MemTable.payload_bytes(frozen)),
            List.length(&2, Db.BEntry, bcache), operation_errors, state
          }})

# Reads Manifest and WAL sizes before building the stats record.
def stats_io(
  db: Db.Db,
  state: Policy.HandleState,
  lock: DbLock.Lock,
  operation_errors: Nat,
  +path: String,
) -> IO(Handle & Result<&1, &1, DurableError.Error, Stats>):

  do IO<Handle & Result<&1, &1, DurableError.Error, Stats>>:
    manifest : Result<&1, &1, U32 & String, Manifest.Manifest> <- Flush.load_mfst(path ++ "/MANIFEST")
    active : Result<&1, &1, U32 & String, Nat> <- stats_active_manifest(manifest, path)
    wal : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(Db.wal_path(path))
    return stats_result((active, wal), db, state, lock, operation_errors, path)

# Reads bounded operational stats from the durable handle.
def stats(handle: Handle) -> IO(Handle & Result<&1, &1, DurableError.Error, Stats>):
  match handle:
    case Handle{+path, lock, db, state, operation_errors}:
      stats_io(db, state, lock, operation_errors, path)
