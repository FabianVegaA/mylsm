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
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

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
def wal_encode(batch: Wal.Batch) -> Result<&1, &1, Wal.Error, Bytes.Bytes>:
  Wal.encode_frame(batch)

# Handle wal decode in the public module exports.
def wal_decode(encoded: Bytes.Bytes) -> Result<&1, &1, Wal.Error, Wal.Batch>:
  Wal.decode_frame(encoded)

# Encode an SST as packed v3 bytes.
def sst_encode(
  +entries: List<&2, MemTable.Entry>,
  +level: U32
) -> Result<&1, &1, SstFile.Error, Bytes.Bytes>:
  SstFile.encode_file(entries, level)

# Parse packed v3 bytes with strict bounds and checksum verification.
def sst_parse(
  encoded: Bytes.Bytes
) -> Result<&1, &1, SstFile.Error, Sstable.Table>:
  SstFile.parse(encoded)

# Serialize a Manifest to its exact on-disk bytes.
def mfst_serialize(mfst: Manifest.Manifest) -> Result<&1, &1, Manifest.Error, Bytes.Bytes>:
  Manifest.serialize(mfst)

# Handle mfst parse in the public module exports.
def mfst_parse(encoded: Bytes.Bytes) -> Maybe<&2, Manifest.Manifest>:
  Manifest.parse(encoded)

# --- Level 1: Sess session monad (primary API) ---
type Sess<a, -A: Kind(a)> is Kind(a <&> &1):
  Sess{run: Db.Db -> (Db.Db & A)}

def Sess.pure(a, -A: Kind(a), val: A) -> Sess<a, A>:
  Sess{db => (db, val)}

def Sess.run_go(b, -B: Kind(b), sess: Sess<b, B>, st: Db.Db) -> Db.Db & B:
  match sess:
    case Sess{run}: run(st)

def Sess.apply(a, -A: Kind(a), b, -B: Kind(b), pair: Db.Db & A, fun: A -> Sess<b, B>) -> Db.Db & B:
  match pair:
    case (st, x): Sess.run_go(b, B, fun(x), st)

def Sess.bind(a, -A: Kind(a), -B: Kind(a), sess: Sess<a, A>, fun: A -> Sess<a, B>) -> Sess<a, B>:
  Sess{st => Sess.apply(a, A, a, B, Sess.run_go(a, A, sess, st), fun)}

# Open a database handle over a directory label (pure; no IO touched).
def open(+dir: String) -> Db.Db:
  Db.open_db(dir)

# Recover a persisted database from its directory.
def open_recovering(+dir: String) -> IO(Result<&1, &1, U32 & String, Db.Db>):
  Recover.open_db(dir)


# Lists the error categories exposed by the durable API.
type ErrorKind is Data:
  NotFoundError{}
  AlreadyExistsError{}
  BusyError{}
  InvalidArgumentError{}
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
    case DurableError.InvalidArgument{}: InvalidArgumentError{}
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

# Pure put transition used by the session action.
def put_go(+db: Db.Db, +key: String, +val: String) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db.apply_done(Db.apply_and_rotate(Con{Wal.Put{key, val}, Nil{}}, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

# Pure delete transition used by the session action.
def del_go(+db: Db.Db, +key: String) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db.apply_done(Db.apply_and_rotate(Con{Wal.Del{key}, Nil{}}, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

# Pure batch transition used by the session action.
def batch_go(+db: Db.Db, +muts: List<&2, Wal.Mut>) -> Db.Db:
  match db:
    case Db.Db{dir, mem, frozen, batch_cap, bcache, levels, flushed, manifest_token, mem_count, frozen_count}:
      Db.apply_done(Db.apply_and_rotate(muts, mem, frozen, mem_count, frozen_count), dir, batch_cap, bcache, levels, flushed, manifest_token)

# Pure point-read transition used by the session action (cache-backed).
def sget_go(+db: Db.Db, +key: String) -> Db.Db & Maybe<&2, String>:
  Db.db_get_cached(db, key)

# Session step writing one key.
def sput(+key: String, +val: String) -> Sess<&2, Unit>:
  Sess{db => (put_go(db, key, val), Unit{})}

# Session step deleting one key.
def sdel(+key: String) -> Sess<&2, Unit>:
  Sess{db => (del_go(db, key), Unit{})}

# Session step applying a whole mutation batch at once.
def sbatch(+muts: List<&2, Wal.Mut>) -> Sess<&2, Unit>:
  Sess{db => (batch_go(db, muts), Unit{})}

# Session step reading one key.
def sget(+key: String) -> Sess<&2, Maybe<&2, String>>:
  Sess{db => sget_go(db, key)}

# Execute a whole session against a handle.
def run_sess(a, -A: Kind(a), st: Db.Db, sess: Sess<a, A>) -> Db.Db & A:
  Sess.run_go(a, A, sess, st)

# Project the answer out of a runner pair.
def value_of(a, -A: Kind(a), pair: Db.Db & A) -> A:
  match pair:
    case (db, x): x
