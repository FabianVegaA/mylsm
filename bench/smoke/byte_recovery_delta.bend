import Base
import ../../src/ByteDurableDb.bend as ByteDurableDb
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/scan/VisibleStats.bend as VisibleStats
import ../../src/Console.bend as Console
import ../../src/DbLock.bend as DbLock

# Rejects a recovered SST that was copied into the active WAL delta.
def empty_result(empty: Bool) -> IO(Unit):
  match empty:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "SST recovery must retain only the WAL delta in memory")

def checked.count(
  entries: List<&1, ByteMemTable.Entry> & Nat,
  +path: String,
  lock: DbLock.Lock,
  state: ByteDurableDb.HandleState
) -> IO(Unit):
  match entries:
    case (retained, count):
      do IO<Unit>:
        _empty : Unit <- empty_result(Nat.is_eq(count, 0n))
        _closed : Result<&1, &1, ByteDurableDb.Error, Unit> <-
          ByteDurableDb.close(ByteDurableDb.Handle{path, lock,
            ByteMemTable.Table{retained}, state, VisibleStats.Stats{0n, 0n}})
        IO.print("BYTE_RECOVERY_DELTA_PASSED")

# Verifies recovery retains only current WAL mutations in memory.
def checked(handle: ByteDurableDb.Handle) -> IO(Unit):
  match handle:
    case ByteDurableDb.Handle{path, lock, ByteMemTable.Table{entries}, state, _}:
      checked.count(ByteMemTable.count.keep(entries), path, lock, state)

# Checks the recovered handle after opening the SST-only fixture.
def opened(result: Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.Handle>) -> IO(Unit):
  match result:
    case Done{handle}: checked(handle)
    case Fail{_}: IO.die(Unit, 1, "SST-only database open failed")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, ByteDurableDb.Error, ByteDurableDb.Handle> <-
      ByteDurableDb.open_existing(path)
    opened(result)
