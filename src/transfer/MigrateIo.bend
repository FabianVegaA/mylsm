import Base
import ../DbLock.bend as DbLock
import ../DurableError.bend as DurableError
import ../Fs.bend as Fs
import ../Flush.bend as Flush
import ../Manifest.bend as Manifest
import ../MemTable.bend as MemTable
import ../Recover.bend as Recover
import ../Sstable.bend as Sstable
import ../SstStreamIo.bend as SstStreamIo
import ../Wal.bend as Wal
import ./LegacyWal.bend as LegacyWal
import ../SstReadPolicy.bend as SstReadPolicy
import ../coordinator/QueuePolicy.bend as QueuePolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Separates lock, host, integrity, and resource failures for read-only validation.
type Error is Data:
  LockError{error: DurableError.Error}
  HostError{code: U32, message: String}
  InvalidLegacyWal{}
  InvalidLegacyManifest{}
  InvalidLegacySst{}
  ResourceLimit{}

# Holds source ownership until read-only validation finishes.
type TableValidation is Type:
  TableValidation{lock: DbLock.Lock, path: String,
    result: Result<&1, &1, Error, Nat & Nat>,
    records: List<&2, MemTable.Entry>, batches: List<&2, Wal.Batch>}

# Reports the SST record and legacy WAL frame counts from one locked view.
type SourceCounts is Data:
  LegacySourceCounts{sst_entries: Nat, wal_frames: Nat, encoded_bytes: Nat}

# Carries the verified SST and replayed WAL records from one locked view.
type SourceSnapshot is Data:
  LegacySourceSnapshot{sst_records: List<&2, MemTable.Entry>,
    wal_batches: List<&2, Wal.Batch>, sst_entries: Nat, wal_frames: Nat,
    encoded_bytes: Nat}

# Carries one legacy SST through size admission, decoding, and entry counting.
type LegacyTableWalk is Type:
  LegacyLevels{lock: DbLock.Lock, read_path: String, release_path: String,
    levels: List<&2, List<&2, String>>, index: Nat, total_bytes: Nat,
    entries: Nat, records: List<&2, MemTable.Entry>}
  LegacyPath{lock: DbLock.Lock, read_path: String, release_path: String,
    ldir: Maybe<&2, String>, names: List<&2, String>,
    levels: List<&2, List<&2, String>>, index: Nat, total_bytes: Nat,
    entries: Nat, records: List<&2, MemTable.Entry>}
  LegacyNames{lock: DbLock.Lock, read_path: String, release_path: String,
    levels: List<&2, List<&2, String>>, index: Nat, dir: String,
    names: List<&2, String>, total_bytes: Nat, entries: Nat,
    records: List<&2, MemTable.Entry>}
  LegacySize{lock: DbLock.Lock, read_path: String, release_path: String,
    levels: List<&2, List<&2, String>>, index: Nat, dir: String,
    name: String, names: List<&2, String>, total_bytes: Nat, entries: Nat,
    result: Result<&1, &1, U32 & String, Nat>, records: List<&2, MemTable.Entry>}
  LegacyBudget{lock: DbLock.Lock, read_path: String, release_path: String,
    levels: List<&2, List<&2, String>>, index: Nat, dir: String,
    name: String, names: List<&2, String>, entries: Nat,
    decision: SstReadPolicy.TotalDecision, records: List<&2, MemTable.Entry>}
  LegacyRead{lock: DbLock.Lock, read_path: String, release_path: String,
    levels: List<&2, List<&2, String>>, index: Nat, dir: String,
    names: List<&2, String>, total_bytes: Nat, entries: Nat,
    result: Result<&1, &1, U32 & String, Sstable.Table>,
    records: List<&2, MemTable.Entry>}

def path.clone.pair.go(
  path: String,
  left: String,
  right: String
) -> String & String:
  match path:
    case SNil{}:
      (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

def table.validation(
  lock: DbLock.Lock,
  path: String,
  result: Result<&1, &1, Error, Nat & Nat>
) -> TableValidation:
  TableValidation{lock, path, result, Nil{}, Nil{}}

def table.validation.records(
  lock: DbLock.Lock,
  path: String,
  result: Result<&1, &1, Error, Nat & Nat>,
  records: List<&2, MemTable.Entry>
) -> TableValidation:
  TableValidation{lock, path, result, records, Nil{}}

def table.validation.snapshot(
  lock: DbLock.Lock,
  path: String,
  result: Result<&1, &1, Error, Nat & Nat>,
  records: List<&2, MemTable.Entry>,
  batches: List<&2, Wal.Batch>
) -> TableValidation:
  TableValidation{lock, path, result, records, batches}

def table.release.result(
  value: Result<&1, &1, Error, Nat & Nat>,
  result: Result<&1, &1, DurableError.Error, Unit>
) -> Result<&1, &1, Error, Nat & Nat>:
  match result:
    case Fail{error}: Fail{LockError{error}}
    case Done{Unit{}}: value

def table.release(state: TableValidation) -> IO(Result<&1, &1, Error, Nat & Nat>):
  match state:
    case TableValidation{lock, path, result, _, _}:
      do IO<Result<&1, &1, Error, Nat & Nat>>:
        released : Result<&1, &1, DurableError.Error, Unit> <-
          DbLock.release(lock, "migrate-verify", path)
        return table.release.result(result, released)

def table.finished(
  lock: DbLock.Lock,
  path: String,
  result: Result<&1, &1, Error, Nat & Nat>
) -> IO(TableValidation):
  IO.pure(TableValidation, table.validation(lock, path, result))

def table.finished.records(
  lock: DbLock.Lock,
  path: String,
  result: Result<&1, &1, Error, Nat & Nat>,
  records: List<&2, MemTable.Entry>
) -> IO(TableValidation):
  IO.pure(TableValidation, table.validation.records(lock, path, result, records))

def table.entries.count.keep.go(
  entries: List<&2, MemTable.Entry>,
  reversed: List<&2, MemTable.Entry>,
  count: Nat
) -> List<&2, MemTable.Entry> & Nat:
  match entries:
    case Nil{}: (List.reverse(&2, MemTable.Entry, reversed), count)
    case Con{entry, tail}:
      table.entries.count.keep.go(tail, Con{entry, reversed}, Nat.add(count, 1n))

def table.entries.count.keep(
  entries: List<&2, MemTable.Entry>
) -> List<&2, MemTable.Entry> & Nat:
  table.entries.count.keep.go(entries, Nil{}, 0n)

def table.read.next(
  read: List<&2, MemTable.Entry> & Nat,
  lock: DbLock.Lock,
  read_path: String,
  release_path: String,
  levels: List<&2, List<&2, String>>,
  index: Nat,
  dir: String,
  names: List<&2, String>,
  total_bytes: Nat,
  prior_entries: Nat,
  prior_records: List<&2, MemTable.Entry>
) -> LegacyTableWalk:
  match read:
    case (table_entries, table_count):
      LegacyNames{lock, read_path, release_path, levels, index, dir,
        names, total_bytes, Nat.add(prior_entries, table_count),
        List.append(&2, MemTable.Entry, prior_records, table_entries)}

def table.failure(code: U32) -> Error:
  Bool.pick(Error, U32.is_eq(code, SstStreamIo.resource_limit_error_code()),
    ResourceLimit{}, InvalidLegacySst{})

def table.manifest.measure(
  levels: List<&2, List<&2, String>>,
  index: Nat,
  acc: List<&2, List<&2, String>>
) -> List<&2, List<&2, String>> & Nat:
  match levels:
    case Nil{}: (List.reverse(&2, List<&2, String>, acc), index)
    case Con{level, tail}:
      table.manifest.measure(tail, Nat.add(index, 1n), Con{level, acc})

def table.walk.size(
  paths: (String & String) & ((String & String) & (String & String)),
  lock: DbLock.Lock,
  release_path: String,
  levels: List<&2, List<&2, String>>,
  index: Nat,
  names: List<&2, String>,
  total_bytes: Nat,
  entries: Nat,
  records: List<&2, MemTable.Entry>
) -> IO(LegacyTableWalk):
  match paths:
    case ((file_root, read_path), ((file_name, name), (file_dir, dir))):
      do IO<LegacyTableWalk>:
        result : Result<&1, &1, U32 & String, Nat> <-
          Fs.file_size(file_root ++ "/" ++ file_dir ++ "/" ++ file_name)
        return LegacySize{lock, read_path, release_path, levels, index,
          dir, name, names, total_bytes, entries, result, records}

def table.walk.decode(
  paths: (String & String) & (String & String),
  lock: DbLock.Lock,
  release_path: String,
  levels: List<&2, List<&2, String>>,
  index: Nat,
  name: String,
  names: List<&2, String>,
  total_bytes: Nat,
  entries: Nat,
  records: List<&2, MemTable.Entry>
) -> IO(LegacyTableWalk):
  match paths:
    case ((file_root, read_path), (file_dir, dir)):
      do IO<LegacyTableWalk>:
        result : Result<&1, &1, U32 & String, Sstable.Table> <-
          SstStreamIo.read_table_limited(
            file_root ++ "/" ++ file_dir ++ "/" ++ name, 67108864n)
        return LegacyRead{lock, read_path, release_path, levels, index,
          dir, names, total_bytes, entries, result, records}

def table.walk.level.path(
  indices: Nat & Nat,
  lock: DbLock.Lock,
  read_path: String,
  release_path: String,
  names: List<&2, String>,
  levels: List<&2, List<&2, String>>,
  total_bytes: Nat,
  entries: Nat,
  records: List<&2, MemTable.Entry>
) -> LegacyTableWalk:
  match indices:
    case (lookup_index, next_index):
      LegacyPath{lock, read_path, release_path,
        Recover.ldir_of(lookup_index), names, levels, next_index,
        total_bytes, entries, records}

def table.walk.go(fuel: Nat, state: LegacyTableWalk) -> IO(TableValidation):
  match fuel:
    case 0n:
      match state:
        case LegacyLevels{lock, _, release_path, _, _, _, _, records}:
          table.finished(lock, release_path, Fail{ResourceLimit{}})
        case LegacyPath{lock, _, release_path, _, _, _, _, _, _, records}:
          table.finished(lock, release_path, Fail{ResourceLimit{}})
        case LegacyNames{lock, _, release_path, _, _, _, _, _, _, records}:
          table.finished(lock, release_path, Fail{ResourceLimit{}})
        case LegacySize{lock, _, release_path, _, _, _, _, _, _, _, _, records}:
          table.finished(lock, release_path, Fail{ResourceLimit{}})
        case LegacyBudget{lock, _, release_path, _, _, _, _, _, _, _, records}:
          table.finished(lock, release_path, Fail{ResourceLimit{}})
        case LegacyRead{lock, _, release_path, _, _, _, _, _, _, _, records}:
          table.finished(lock, release_path, Fail{ResourceLimit{}})
    case 1n+rest:
      match state:
        case LegacyLevels{lock, read_path, release_path, levels, index,
            total_bytes, entries, records}:
          match levels:
            case Nil{}:
              table.finished.records(lock, release_path,
                Done{(entries, total_bytes)}, records)
            case Con{names, tail}:
              table.walk.go(rest, table.walk.level.path(
                QueuePolicy.nat.clone.pair(index), lock, read_path,
                release_path, names, tail, total_bytes, entries, records))
        case LegacyPath{lock, read_path, release_path, ldir, names, levels,
            index, total_bytes, entries, records}:
          match ldir:
            case None{}:
              table.finished.records(lock, release_path,
                Fail{InvalidLegacyManifest{}}, records)
            case Some{dir}:
              table.walk.go(rest, LegacyNames{lock, read_path, release_path,
                levels, index, dir, names, total_bytes, entries, records})
        case LegacyNames{lock, read_path, release_path, levels, index, dir,
            names, total_bytes, entries, records}:
          match names:
            case Nil{}:
              table.walk.go(rest, LegacyLevels{lock, read_path, release_path,
                levels, Nat.add(index, 1n), total_bytes, entries, records})
            case Con{name, tail}:
              do IO<TableValidation>:
                next : LegacyTableWalk <- table.walk.size(
                  (path.clone.pair(read_path),
                  (path.clone.pair(name), path.clone.pair(dir))),
                  lock, release_path, levels, index, tail,
                  total_bytes, entries, records)
                table.walk.go(rest, next)
        case LegacySize{lock, read_path, release_path, levels, index, dir,
            name, names, total_bytes, entries, result, records}:
          match result:
            case Fail{(code, message)}:
              table.finished.records(lock, release_path,
                Fail{HostError{code, message}}, records)
            case Done{size}:
              table.walk.go(rest, LegacyBudget{lock, read_path, release_path,
                levels, index, dir, name, names, entries,
                SstReadPolicy.total_decision(total_bytes, size, 67108864n),
                records})
        case LegacyBudget{lock, read_path, release_path, levels, index, dir,
            name, names, entries, decision, records}:
          match decision:
            case SstReadPolicy.TotalRejected{}:
              table.finished.records(lock, release_path,
                Fail{ResourceLimit{}}, records)
            case SstReadPolicy.TotalAdmitted{next_total}:
              do IO<TableValidation>:
                next : LegacyTableWalk <- table.walk.decode(
                  (path.clone.pair(read_path), path.clone.pair(dir)), lock,
                  release_path, levels, index, name, names, next_total,
                  entries, records)
                table.walk.go(rest, next)
        case LegacyRead{lock, read_path, release_path, levels, index, dir,
            names, total_bytes, entries, result, records}:
          match result:
            case Fail{(code, _)}:
              table.finished.records(lock, release_path,
                Fail{table.failure(code)}, records)
            case Done{Sstable.Tbl{table_entries, _, _, _, _, _, _, _}}:
              table.walk.go(rest, table.read.next(
                table.entries.count.keep(table_entries), lock, read_path,
                release_path, levels, index, dir, names, total_bytes,
                entries, records))

def table.walk.start.paths(
  paths: String & String,
  lock: DbLock.Lock,
  release_path: String,
  measured: List<&2, List<&2, String>> & Nat
) -> IO(TableValidation):
  match paths:
    case (read_path, _):
      match measured:
        case (levels, _):
          table.walk.go(4194305n, LegacyLevels{lock, read_path,
            release_path, levels, 0n, 0n, 0n, Nil{}})

def table.walk.start(
  lock: DbLock.Lock,
  paths: String & String,
  measured: List<&2, List<&2, String>> & Nat
) -> IO(TableValidation):
  match paths:
    case (read_path, release_path):
      table.walk.start.paths(path.clone.pair(read_path), lock, release_path,
        measured)

def table.manifest.loaded(
  state: TableValidation,
  result: Result<&1, &1, U32 & String, Manifest.Manifest>
) -> IO(TableValidation):
  match state:
    case TableValidation{lock, path, _, _, _}:
      match result:
        case Fail{_}:
          table.finished(lock, path, Fail{InvalidLegacyManifest{}})
        case Done{Manifest.M{levels}}:
          table.walk.start(lock, path.clone.pair(path),
            table.manifest.measure(levels, 0n, Nil{}))

def table.manifest.read(
  lock: DbLock.Lock,
  paths: String & String
) -> IO(TableValidation):
  match paths:
    case (read_path, retained_path):
      do IO<TableValidation>:
        manifest : Result<&1, &1, U32 & String, Manifest.Manifest> <-
          Flush.load_mfst(read_path ++ "/MANIFEST")
        table.manifest.loaded(
          table.validation(lock, retained_path, Done{(0n, 0n)}), manifest)

def table.manifest.present(
  lock: DbLock.Lock,
  path: String,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(TableValidation):
  match result:
    case Fail{(code, message)}:
      table.finished(lock, path, Fail{HostError{code, message}})
    case Done{False{}}:
      table.finished(lock, path, Fail{InvalidLegacyManifest{}})
    case Done{True{}}:
      do IO<TableValidation>:
        paths : String & String = path.clone.pair(path)
        table.manifest.read(lock, paths)

def table.locked.manifest(
  lock: DbLock.Lock,
  paths: String & String
) -> IO(Result<&1, &1, Error, Nat & Nat>):
  match paths:
    case (exists_path, retained_path):
      do IO<Result<&1, &1, Error, Nat & Nat>>:
        present : Result<&1, &1, U32 & String, Bool> <-
          Fs.exists(exists_path ++ "/MANIFEST")
        validation : TableValidation <-
          table.manifest.present(lock, retained_path, present)
        table.release(validation)

def table.locked(
  path: String,
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>
) -> IO(Result<&1, &1, Error, Nat & Nat>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Nat & Nat>, Fail{LockError{error}})
    case Done{lock}:
      do IO<Result<&1, &1, Error, Nat & Nat>>:
        paths : String & String = path.clone.pair(path)
        table.locked.manifest(lock, paths)

def table.lock.acquired(
  retained_path: String,
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>
) -> IO(Result<&1, &1, Error, Nat & Nat>):
  table.locked(retained_path, result)

def table.lock.present.start(paths: String & String) -> IO(Result<&1, &1, Error, Nat & Nat>):
  match paths:
    case (lock_path, retained_path):
      do IO<Result<&1, &1, Error, Nat & Nat>>:
        acquired : Result<&1, &1, DurableError.Error, DbLock.Lock> <-
          DbLock.acquire(lock_path, "migrate-verify")
        table.lock.acquired(retained_path, acquired)

def table.lock.present(
  path: String,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, Nat & Nat>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Nat & Nat>, Fail{HostError{code, message}})
    case Done{False{}}:
      IO.pure(Result<&1, &1, Error, Nat & Nat>,
        Fail{HostError{2, "database LOCK file is missing"}})
    case Done{True{}}:
      do IO<Result<&1, &1, Error, Nat & Nat>>:
        paths : String & String = path.clone.pair(path)
        table.lock.present.start(paths)

def table.canonical.lock(
  paths: String & String
) -> IO(Result<&1, &1, Error, Nat & Nat>):
  match paths:
    case (exists_path, retained_path):
      do IO<Result<&1, &1, Error, Nat & Nat>>:
        present : Result<&1, &1, U32 & String, Bool> <-
          Fs.exists(exists_path ++ "/LOCK")
        table.lock.present(retained_path, present)

def table.canonical(
  result: Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, Error, Nat & Nat>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Nat & Nat>, Fail{HostError{code, message}})
    case Done{path}:
      do IO<Result<&1, &1, Error, Nat & Nat>>:
        paths : String & String = path.clone.pair(path)
        table.canonical.lock(paths)

# Validates legacy manifest references and SST contents while holding the source lock.
def table.count.result(
  result: Result<&1, &1, Error, Nat & Nat>
) -> Result<&1, &1, Error, Nat>:
  match result:
    case Fail{error}: Fail{error}
    case Done{(entries, _)}: Done{entries}

# Validates legacy SST files and reports their record count under one lock.
def verify_legacy_tables(path: String) -> IO(Result<&1, &1, Error, Nat>):
  do IO<Result<&1, &1, Error, Nat>>:
    canonical : Result<&1, &1, U32 & String, String> <- Fs.canonical_path(path)
    verified : Result<&1, &1, Error, Nat & Nat> <- table.canonical(canonical)
    return table.count.result(verified)

# Bounds memory used while validating a legacy WAL file.
def max_wal_bytes() -> Nat:
  67108864n

# Preserves the primary validation result unless lock release fails.
def release.result(
  value: Result<&1, &1, Error, Nat>,
  released: Result<&1, &1, DurableError.Error, Unit>
) -> Result<&1, &1, Error, Nat>:
  match released:
    case Fail{error}: Fail{LockError{error}}
    case Done{Unit{}}: value

# Releases database ownership before returning validation status.
def release(
  lock: DbLock.Lock,
  value: Result<&1, &1, Error, Nat>,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  do IO<Result<&1, &1, Error, Nat>>:
    released : Result<&1, &1, DurableError.Error, Unit> <-
      DbLock.release(lock, "migrate-verify", path)
    return release.result(value, released)

# Converts a raw host failure after releasing the source lock.
def host.failed(
  lock: DbLock.Lock,
  error: U32 & String,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  match error:
    case (code, message):
      release(lock, Fail{HostError{code, message}}, path)

# Converts a host failure that occurred before acquiring the source lock.
def host.without_lock(error: U32 & String) -> IO(Result<&1, &1, Error, Nat>):
  match error:
    case (code, message):
      IO.pure(Result<&1, &1, Error, Nat>, Fail{HostError{code, message}})

# Releases the lock after classifying pure legacy WAL verification.
def wal.checked.result(
  lock: DbLock.Lock,
  result: LegacyWal.VerifyResult,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  match result:
    case LegacyWal.WalValid{frames}:
      release(lock, Done{frames}, path)
    case LegacyWal.WalInvalid{}:
      release(lock, Fail{InvalidLegacyWal{}}, path)

# Revalidates complete WAL bytes without repairing or truncating the source.
def wal.checked(
  lock: DbLock.Lock,
  bytes: Bytes.Bytes,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  wal.checked.result(lock, LegacyWal.verify(bytes), path)

# Classifies bounded WAL bytes after the data descriptor has closed.
def wal.read.closed.result(
  result: Result<&1, &1, U32 & String, Bytes.Bytes>,
  lock: DbLock.Lock,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  match result:
    case Fail{error}: host.failed(lock, error, path)
    case Done{bytes}: wal.checked(lock, bytes, path)

def wal.read.failure(
  error: U32 & String,
  released: Result<&1, &1, DurableError.Error, Unit>
) -> Result<&1, &1, Error, Nat>:
  match error:
    case (code, message):
      match released:
        case Fail{lock_error}: Fail{LockError{lock_error}}
        case Done{Unit{}}: Fail{HostError{code, message}}

def wal.classify(result: LegacyWal.VerifyResult) -> Result<&1, &1, Error, Nat>:
  match result:
    case LegacyWal.WalValid{frames}: Done{frames}
    case LegacyWal.WalInvalid{}: Fail{InvalidLegacyWal{}}

def wal.read.success(
  bytes: Bytes.Bytes,
  released: Result<&1, &1, DurableError.Error, Unit>
) -> Result<&1, &1, Error, Nat>:
  match released:
    case Fail{error}: Fail{LockError{error}}
    case Done{Unit{}}: wal.classify(LegacyWal.verify(bytes))

# Closes the WAL descriptor before classifying its bytes.
def wal.read.dispatch(
  result: Result<&1, &1, U32 & String, Bytes.Bytes>,
  released: Result<&1, &1, DurableError.Error, Unit>
) -> Result<&1, &1, Error, Nat>:
  match result:
    case Fail{error}: wal.read.failure(error, released)
    case Done{bytes}: wal.read.success(bytes, released)

def wal.read.closed(
  file: File,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>,
  lock: DbLock.Lock,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  do IO<Result<&1, &1, Error, Nat>>:
    _closed : Unit <- File.close(file)
    released : Result<&1, &1, DurableError.Error, Unit> <-
      DbLock.release(lock, "migrate-verify", path)
    return wal.read.dispatch(result, released)

# Routes the owned WAL file into its read result handler.
def wal.read.pair(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  lock: DbLock.Lock,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  match pair:
    case (file, result): wal.read.closed(file, result, lock, path)

# Reads a bounded WAL file while retaining the exclusive source lock.
def wal.opened(
  lock: DbLock.Lock,
  size: Nat,
  opened: Result<&1, &1, U32 & String, File>,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  match opened:
    case Fail{error}: host.failed(lock, error, path)
    case Done{file}:
      do IO<Result<&1, &1, Error, Nat>>:
        read : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, 0, U32.from_nat(size))
        wal.read.pair(read, lock, path)

# Rejects oversized WAL input before opening its data file.
def wal.sized(
  lock: DbLock.Lock,
  size: Nat,
  +path: String,
  within_limit: Bool
) -> IO(Result<&1, &1, Error, Nat>):
  match within_limit:
    case False{}: release(lock, Fail{ResourceLimit{}}, path)
    case True{}:
      do IO<Result<&1, &1, Error, Nat>>:
        opened : Result<&1, &1, U32 & String, File> <-
          File.open(path ++ "/WAL", "r")
        wal.opened(lock, size, opened, path)

# Checks file size and rejects inputs beyond the migration memory limit.
def wal.size.result(
  lock: DbLock.Lock,
  result: Result<&1, &1, U32 & String, Nat>,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  match result:
    case Fail{error}: host.failed(lock, error, path)
    case Done{+size}:
      wal.sized(lock, size, path, Nat.is_le(size, max_wal_bytes()))

# Treats a missing WAL as an empty legacy mutation stream.
def wal.present(
  lock: DbLock.Lock,
  present: Bool,
  +path: String
) -> IO(Result<&1, &1, Error, Nat>):
  match present:
    case False{}: release(lock, Done{0n}, path)
    case True{}:
      do IO<Result<&1, &1, Error, Nat>>:
        size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/WAL")
        wal.size.result(lock, size, path)

# Requires the legacy WAL path to be readable without changing it.
def wal.exists(
  lock: DbLock.Lock,
  result: Result<&1, &1, U32 & String, Bool>,
  path: String
) -> IO(Result<&1, &1, Error, Nat>):
  match result:
    case Fail{error}: host.failed(lock, error, path)
    case Done{present}: wal.present(lock, present, path)

# Continues source verification after exclusive lock acquisition.
def locked(
  +path: String,
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>
) -> IO(Result<&1, &1, Error, Nat>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Nat>, Fail{LockError{error}})
    case Done{lock}:
      do IO<Result<&1, &1, Error, Nat>>:
        present : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path ++ "/WAL")
        wal.exists(lock, present, path)

# Requires an existing stable lock file and acquires it before reading the WAL.
def lock.present(
  +path: String,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, Nat>):
  match result:
    case Fail{error}: host.without_lock(error)
    case Done{False{}}:
      IO.pure(Result<&1, &1, Error, Nat>, Fail{HostError{2, "database LOCK file is missing"}})
    case Done{True{}}:
      do IO<Result<&1, &1, Error, Nat>>:
        acquired : Result<&1, &1, DurableError.Error, DbLock.Lock> <-
          DbLock.acquire(path, "migrate-verify")
        locked(path, acquired)

# Converts a canonicalization error into the migration IO error domain.
def canonical.result(
  result: Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, Error, Nat>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, Nat>, Fail{HostError{code, message}})
    case Done{+path}:
      do IO<Result<&1, &1, Error, Nat>>:
        present : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path ++ "/LOCK")
        lock.present(path, present)

def wal.batches.measure.go(
  batches: List<&2, Wal.Batch>,
  reversed: List<&2, Wal.Batch>,
  count: Nat
) -> List<&2, Wal.Batch> & Nat:
  match batches:
    case Nil{}: (List.reverse(&2, Wal.Batch, reversed), count)
    case Con{batch, tail}:
      wal.batches.measure.go(tail, Con{batch, reversed}, Nat.add(count, 1n))

def wal.batches.measure(batches: List<&2, Wal.Batch>) -> List<&2, Wal.Batch> & Nat:
  wal.batches.measure.go(batches, Nil{}, 0n)

def wal.locked.valid.batches(
  measured: List<&2, Wal.Batch> & Nat,
  lock: DbLock.Lock,
  path: String,
  size: Nat,
  records: List<&2, MemTable.Entry>
) -> TableValidation:
  match measured:
    case (batches, frames):
      table.validation.snapshot(lock, path,
        Done{(frames, size)}, records, batches)

def wal.locked.classified(
  result: LegacyWal.ReplayResult,
  lock: DbLock.Lock,
  path: String,
  size: Nat,
  records: List<&2, MemTable.Entry>
) -> TableValidation:
  match result:
    case LegacyWal.ReplayInvalid{}:
      table.validation.records(lock, path, Fail{InvalidLegacyWal{}}, records)
    case LegacyWal.ReplayValid{batches}:
      wal.locked.valid.batches(wal.batches.measure(batches), lock, path,
        size, records)

def wal.locked.read.classify(
  result: Result<&1, &1, U32 & String, Bytes.Bytes>,
  lock: DbLock.Lock,
  path: String,
  size: Nat,
  records: List<&2, MemTable.Entry>
) -> TableValidation:
  match result:
    case Fail{(code, message)}:
      table.validation.records(lock, path, Fail{HostError{code, message}}, records)
    case Done{bytes}:
      wal.locked.classified(LegacyWal.replay(bytes), lock, path, size, records)

def wal.locked.read.closed(
  file: File,
  result: Result<&1, &1, U32 & String, Bytes.Bytes>,
  lock: DbLock.Lock,
  path: String,
  size: Nat,
  records: List<&2, MemTable.Entry>
) -> IO(TableValidation):
  do IO<TableValidation>:
    _closed : Unit <- File.close(file)
    return wal.locked.read.classify(result, lock, path, size, records)

def wal.locked.read.pair(
  pair: File & Result<&1, &1, U32 & String, Bytes.Bytes>,
  lock: DbLock.Lock,
  path: String,
  size: Nat,
  records: List<&2, MemTable.Entry>
) -> IO(TableValidation):
  match pair:
    case (file, result): wal.locked.read.closed(file, result, lock, path, size, records)

def wal.locked.opened(
  lock: DbLock.Lock,
  sizes: Nat & Nat,
  opened: Result<&1, &1, U32 & String, File>,
  path: String,
  records: List<&2, MemTable.Entry>
) -> IO(TableValidation):
  match sizes opened:
    case (read_size, retained_size) Fail{(code, message)}:
      IO.pure(TableValidation,
        table.validation.records(lock, path, Fail{HostError{code, message}}, records))
    case (read_size, retained_size) Done{file}:
      do IO<TableValidation>:
        read : File & Result<&1, &1, U32 & String, Bytes.Bytes> <-
          Fs.read_at(file, 0, U32.from_nat(read_size))
        wal.locked.read.pair(read, lock, path, retained_size, records)

def wal.locked.sized(
  lock: DbLock.Lock,
  size: Nat,
  +path: String,
  within_limit: Bool,
  records: List<&2, MemTable.Entry>
) -> IO(TableValidation):
  match within_limit:
    case False{}:
      IO.pure(TableValidation,
        table.validation.records(lock, path, Fail{ResourceLimit{}}, records))
    case True{}:
      do IO<TableValidation>:
        opened : Result<&1, &1, U32 & String, File> <-
          File.open(path ++ "/WAL", "r")
        wal.locked.opened(lock, QueuePolicy.nat.clone.pair(size), opened, path,
          records)

def wal.locked.size.result(
  lock: DbLock.Lock,
  result: Result<&1, &1, U32 & String, Nat>,
  path: String,
  records: List<&2, MemTable.Entry>
) -> IO(TableValidation):
  match result:
    case Fail{(code, message)}:
      IO.pure(TableValidation,
        table.validation.records(lock, path, Fail{HostError{code, message}}, records))
    case Done{+size}:
      wal.locked.sized(lock, size, path, Nat.is_le(size, max_wal_bytes()), records)

def wal.locked.present(
  lock: DbLock.Lock,
  present: Bool,
  +path: String,
  records: List<&2, MemTable.Entry>
) -> IO(TableValidation):
  match present:
    case False{}:
      IO.pure(TableValidation,
        table.validation.snapshot(lock, path, Done{(0n, 0n)}, records, Nil{}))
    case True{}:
      do IO<TableValidation>:
        size : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/WAL")
        wal.locked.size.result(lock, size, path, records)

def wal.locked.exists(
  lock: DbLock.Lock,
  result: Result<&1, &1, U32 & String, Bool>,
  path: String,
  records: List<&2, MemTable.Entry>
) -> IO(TableValidation):
  match result:
    case Fail{(code, message)}:
      IO.pure(TableValidation,
        table.validation.records(lock, path, Fail{HostError{code, message}}, records))
    case Done{present}: wal.locked.present(lock, present, path, records)

def source.release.result(
  value: Result<&1, &1, Error, SourceSnapshot>,
  released: Result<&1, &1, DurableError.Error, Unit>
) -> Result<&1, &1, Error, SourceSnapshot>:
  match released:
    case Fail{error}: Fail{LockError{error}}
    case Done{Unit{}}: value

def source.release(
  lock: DbLock.Lock,
  path: String,
  value: Result<&1, &1, Error, SourceSnapshot>
) -> IO(Result<&1, &1, Error, SourceSnapshot>):
  do IO<Result<&1, &1, Error, SourceSnapshot>>:
    released : Result<&1, &1, DurableError.Error, Unit> <-
      DbLock.release(lock, "migrate-verify", path)
    return source.release.result(value, released)

def source.wal.validated(
  sst: Nat & Nat,
  state: TableValidation
) -> IO(Result<&1, &1, Error, SourceSnapshot>):
  match sst state:
    case (sst_entries, sst_bytes) TableValidation{lock, path, result,
        sst_records, wal_batches}:
      match result:
        case Fail{error}:
          source.release(lock, path, Fail{error})
        case Done{(wal_frames, wal_bytes)}:
          source.release(lock, path, Done{LegacySourceSnapshot{sst_records,
            wal_batches, sst_entries, wal_frames, Nat.add(sst_bytes, wal_bytes)}})

def source.tables.present(
  sst: Nat & Nat,
  sst_records: List<&2, MemTable.Entry>,
  lock: DbLock.Lock,
  paths: String & String
) -> IO(Result<&1, &1, Error, SourceSnapshot>):
  match paths:
    case (exists_path, validation_path):
      do IO<Result<&1, &1, Error, SourceSnapshot>>:
        present : Result<&1, &1, U32 & String, Bool> <-
          Fs.exists(exists_path ++ "/WAL")
        wal : TableValidation <- wal.locked.exists(lock, present,
          validation_path, sst_records)
        source.wal.validated(sst, wal)

def source.tables.validated(
  state: TableValidation
) -> IO(Result<&1, &1, Error, SourceSnapshot>):
  match state:
    case TableValidation{lock, path, result, records, _}:
      match result:
        case Fail{error}: source.release(lock, path, Fail{error})
        case Done{sst}:
          source.tables.present(sst, records, lock, path.clone.pair(path))

def source.manifest.present(
  lock: DbLock.Lock,
  paths: String & String
) -> IO(Result<&1, &1, Error, SourceSnapshot>):
  match paths:
    case (exists_path, validation_path):
      do IO<Result<&1, &1, Error, SourceSnapshot>>:
        present : Result<&1, &1, U32 & String, Bool> <-
          Fs.exists(exists_path ++ "/MANIFEST")
        tables : TableValidation <-
          table.manifest.present(lock, validation_path, present)
        source.tables.validated(tables)

def source.locked.manifest(
  +path: String,
  result: Result<&1, &1, DurableError.Error, DbLock.Lock>
) -> IO(Result<&1, &1, Error, SourceSnapshot>):
  match result:
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, SourceSnapshot>, Fail{LockError{error}})
    case Done{lock}:
      source.manifest.present(lock, path.clone.pair(path))

def source.lock.present(
  +path: String,
  result: Result<&1, &1, U32 & String, Bool>
) -> IO(Result<&1, &1, Error, SourceSnapshot>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, SourceSnapshot>, Fail{HostError{code, message}})
    case Done{False{}}:
      IO.pure(Result<&1, &1, Error, SourceSnapshot>,
        Fail{HostError{2, "database LOCK file is missing"}})
    case Done{True{}}:
      do IO<Result<&1, &1, Error, SourceSnapshot>>:
        acquired : Result<&1, &1, DurableError.Error, DbLock.Lock> <-
          DbLock.acquire(path, "migrate-verify")
        source.locked.manifest(path, acquired)

def source.canonical(
  result: Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, Error, SourceSnapshot>):
  match result:
    case Fail{(code, message)}:
      IO.pure(Result<&1, &1, Error, SourceSnapshot>, Fail{HostError{code, message}})
    case Done{+path}:
      do IO<Result<&1, &1, Error, SourceSnapshot>>:
        present : Result<&1, &1, U32 & String, Bool> <- Fs.exists(path ++ "/LOCK")
        source.lock.present(path, present)

def source.counts(
  result: Result<&1, &1, Error, SourceSnapshot>
) -> Result<&1, &1, Error, SourceCounts>:
  match result:
    case Fail{error}: Fail{error}
    case Done{LegacySourceSnapshot{_, _, sst_entries, wal_frames, encoded_bytes}}:
      Done{LegacySourceCounts{sst_entries, wal_frames, encoded_bytes}}

# Reads legacy tables and WAL without changing source files.
def read_legacy_source(
  +path: String
) -> IO(Result<&1, &1, Error, SourceSnapshot>):
  do IO<Result<&1, &1, Error, SourceSnapshot>>:
    canonical : Result<&1, &1, U32 & String, String> <- Fs.canonical_path(path)
    source.canonical(canonical)

# Validates the locked legacy view and returns its aggregate measurements.
def verify_legacy_source(
  +path: String
) -> IO(Result<&1, &1, Error, SourceCounts>):
  do IO<Result<&1, &1, Error, SourceCounts>>:
    snapshot : Result<&1, &1, Error, SourceSnapshot> <- read_legacy_source(path)
    return source.counts(snapshot)

# Verifies a legacy WAL while holding the existing database lock read-only.
def verify_legacy_wal(+path: String) -> IO(Result<&1, &1, Error, Nat>):
  do IO<Result<&1, &1, Error, Nat>>:
    canonical : Result<&1, &1, U32 & String, String> <- Fs.canonical_path(path)
    canonical.result(canonical)
