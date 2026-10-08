import Base
import ../../mylsm.bend as MyLSM
import ../../src/Fs.bend as Fs
import ../../src/Console.bend as Console

# Checks the active size matches condition in this fixture.
def active_size_matches(active: Nat, manifest: Nat, table: Nat) -> Bool:
  Nat.is_eq(active, Nat.add(manifest, table))

# Runs the closed only step of this fixture.
def closed_only(result: Result<&1, &1, MyLSM.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, U32.from_nat(1n), "stats oracle final close failed")
    case Done{Unit{}}:
      IO.print("STATS_ORACLE_CLOSED")

def compare_sizes.result(matches: Bool, handle: MyLSM.Handle) -> IO(Unit):
  match matches:
    case True{}:
      do IO<Unit>:
        IO.print("ACTIVE_BYTES_EXACT")
        result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        closed_only(result)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "active-byte total differs from published files")

# Checks the compare sizes condition in this fixture.
def compare_sizes(
  active: Nat,
  manifest: Result<&1, &1, U32 & String, Nat>,
  table: Result<&1, &1, U32 & String, Nat>,
  handle: MyLSM.Handle
) -> IO(Unit):
  match manifest table:
    case Done{manifest_bytes} Done{table_bytes}:
      compare_sizes.result(active_size_matches(active, manifest_bytes, table_bytes), handle)
    case _ _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, U32.from_nat(1n), "active-byte oracle could not stat fixture files")

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
    case (handle, Done{MyLSM.DurableStats{active_bytes, _, _, _, _, _, _}}):
      do IO<Unit>:
        manifest : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/MANIFEST")
        table : Result<&1, &1, U32 & String, Nat> <- Fs.file_size(path ++ "/l0/l0-1.tbl")
        compare_sizes(active_bytes, manifest, table, handle)

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
