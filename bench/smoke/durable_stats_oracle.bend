import Base
import ../../mylsm.bend as MyLSM
import ../../src/Fs.bend as Fs
import ../../src/Console.bend as Console
import ../../src/DurableDbPolicy.bend as DurablePolicy

# Checks the active size matches condition in this fixture.
def active_size_matches(active: Nat, manifest: Nat, table: Nat) -> Bool:
  Nat.is_eq(active, Nat.add(manifest, table))

def metrics.match(
  wal_bytes: Nat,
  actual_wal_bytes: Nat,
  memtable_entries: Nat,
  memtable_payload_bytes: Nat,
  cache_entries: Nat,
  operation_errors: Nat,
  maintenance_blocked: Bool
) -> Bool:
  Nat.is_eq(wal_bytes, actual_wal_bytes) &&
    DurablePolicy.stats.resident.empty(memtable_entries,
      memtable_payload_bytes, cache_entries, operation_errors,
      maintenance_blocked)

# Runs the closed only step of this fixture.
def closed_only(result: Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "stats oracle final close failed")
    case Done{Unit{}}:
      IO.print("STATS_ORACLE_CLOSED")

def compare_sizes.result(matches: Bool, metrics: Bool, handle: MyLSM.Handle) -> IO(Unit):
  match matches metrics:
    case True{} True{}:
      do IO<Unit>:
        IO.print("ACTIVE_BYTES_EXACT")
        IO.print("WAL_AND_RESIDENT_METRICS_EXACT")
        result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        closed_only(result)
    case _ _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "active-byte total differs from published files")

# Checks the compare sizes condition in this fixture.
def metrics.files.checked(
  wal_bytes: Nat,
  memtable_entries: Nat,
  memtable_payload_bytes: Nat,
  cache_entries: Nat,
  operation_errors: Nat,
  maintenance_blocked: Bool,
  actual_wal_bytes: Nat,
  active_bytes: Nat,
  files: Result<&1, &1, U32 & String, Nat> & Result<&1, &1, U32 & String, Nat>,
  handle: MyLSM.Handle
) -> IO(Unit):
  match files:
    case (Done{manifest_bytes}, Done{table_bytes}):
      compare_sizes.result(
        active_size_matches(active_bytes, manifest_bytes, table_bytes),
        metrics.match(wal_bytes, actual_wal_bytes, memtable_entries,
          memtable_payload_bytes, cache_entries, operation_errors,
          maintenance_blocked), handle)
    case _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "stats oracle could not stat durable files")

def metrics.checked(
  wal_bytes: Nat,
  memtable_entries: Nat,
  memtable_payload_bytes: Nat,
  cache_entries: Nat,
  operation_errors: Nat,
  maintenance_blocked: Bool,
  wal: Result<&1, &1, U32 & String, Nat>,
  active_bytes: Nat,
  manifest: Result<&1, &1, U32 & String, Nat>,
  table: Result<&1, &1, U32 & String, Nat>,
  handle: MyLSM.Handle
) -> IO(Unit):
  match wal:
    case Done{actual_wal_bytes}:
      metrics.files.checked(wal_bytes, memtable_entries,
        memtable_payload_bytes, cache_entries, operation_errors,
        maintenance_blocked, actual_wal_bytes, active_bytes,
        (manifest, table), handle)
    case Fail{_}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "stats oracle could not stat the WAL")

# Runs the stats result step of this fixture.
def stats_result(
  pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats>,
  +path: String
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "stats oracle public stats failed")
    case (handle, Done{MyLSM.DurableStats{active_bytes, wal_bytes,
        memtable_entries, memtable_payload_bytes, cache_entries,
        operation_errors, maintenance_blocked}}):
      do IO<Unit>:
        manifest : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/MANIFEST")
        table : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/l0/l0-1.tbl")
        wal : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/wal.log")
        metrics.checked(wal_bytes, memtable_entries, memtable_payload_bytes,
          cache_entries, operation_errors, maintenance_blocked, wal,
          active_bytes, manifest, table, handle)

# Runs the opened step of this fixture.
def opened(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>, +path: String) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "stats oracle reopen failed")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.DurableStats> <- MyLSM.stats(handle)
        stats_result(pair, path)

# Runs the closed step of this fixture.
def closed(result: Result<&1, &1, MyLSM.Error, Unit>, +path: String) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "stats oracle close failed")
    case Done{Unit{}}:
      do IO<Unit>:
        next : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        opened(next, path)

# Runs the flushed step of this fixture.
def flushed(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "stats oracle flush failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        closed(result, path)

# Continues the written fixture step.
def written(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>, +path: String) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "stats oracle write failed")
    case (handle, Done{_}):
      do IO<Unit>:
        pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.flush(handle)
        flushed(pair, path)

# Runs the created step of this fixture.
def created(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>, +path: String) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "stats oracle create failed")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.put(handle, "oracle-key", "oracle-value")
        written(pair, path)

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.create(path)
    created(result, path)
