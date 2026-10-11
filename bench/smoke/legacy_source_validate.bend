import Base
import ../../src/Console.bend as Console
import ../../src/MemTable.bend as MemTable
import ../../src/transfer/MigrateIo.bend as MigrateIo
import ../../src/Wal.bend as Wal

# Stops the source validation fixture after a failed assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def path.clone.pair.go(
  path: String,
  left: String,
  right: String
) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

def source.records.valid(records: List<&2, MemTable.Entry>) -> Bool:
  match records:
    case Con{MemTable.Entry{"a", Some{"one"}},
        Con{MemTable.Entry{"b", Some{"two"}}, Nil{}}}: True{}
    case _: False{}

def source.wal.valid(batches: List<&2, Wal.Batch>) -> Bool:
  match batches:
    case Con{Wal.Batch{Con{Wal.Put{"legacy", "value"}, Nil{}}}, Nil{}}:
      True{}
    case _: False{}

def snapshot.content.check(valid: Bool, expect_invalid: Bool) -> IO(Unit):
  match valid:
    case False{}: fail("legacy source snapshot lost SST or WAL records")
    case True{}:
      match expect_invalid:
        case True{}: fail("legacy source snapshot accepted corrupt WAL")
        case False{}: IO.print("LEGACY_SOURCE_SNAPSHOT_PASSED")

def snapshot.valid(
  result: Result<&1, &1, MigrateIo.Error, MigrateIo.SourceSnapshot>,
  expect_invalid: Bool
) -> IO(Unit):
  match result:
    case Fail{MigrateIo.InvalidLegacyWal{}}:
      match expect_invalid:
        case True{}: IO.pure(Unit, Unit{})
        case False{}: fail("legacy source snapshot rejected valid WAL")
    case Fail{_}: fail("legacy source snapshot returned an unexpected error")
    case Done{MigrateIo.LegacySourceSnapshot{records, batches, 2n, 1n, _}}:
      snapshot.content.check(source.records.valid(records) &&
        source.wal.valid(batches), expect_invalid)
    case Done{_}: fail("legacy source snapshot returned unexpected counts")

# Checks valid-source counts and confirms an invalid source releases its lock.
def retried(
  result: Result<&1, &1, MigrateIo.Error, MigrateIo.SourceCounts>
) -> IO(Unit):
  match result:
    case Fail{MigrateIo.InvalidLegacyWal{}}:
      IO.print("LEGACY_SOURCE_LOCK_RELEASED_AFTER_REJECTION")
    case _:
      fail("legacy source lock was not reusable after WAL rejection")

# Checks valid-source counts and confirms an invalid source releases its lock.
def verified(
  path: String,
  result: Result<&1, &1, MigrateIo.Error, MigrateIo.SourceCounts>,
  expect_invalid: Bool
) -> IO(Unit):
  match result:
    case Done{MigrateIo.LegacySourceCounts{2n, 1n, encoded_bytes}}:
      match expect_invalid:
        case True{}: fail("combined legacy verification accepted corrupt WAL")
        case False{}:
          do IO<Unit>:
            _printed : Unit <- IO.print("LEGACY_SOURCE_SINGLE_LOCK_PASSED")
            IO.print("LEGACY_SOURCE_ENCODED_BYTES=" ++ Nat.show(encoded_bytes))
    case Done{_}: fail("combined legacy verification returned unexpected counts")
    case Fail{MigrateIo.InvalidLegacyWal{}}:
      match expect_invalid:
        case True{}:
          do IO<Unit>:
            retry : Result<&1, &1, MigrateIo.Error, MigrateIo.SourceCounts> <-
              MigrateIo.verify_legacy_source(path)
            retried(retry)
        case False{}: fail("combined legacy verification rejected its valid fixture")
    case Fail{_}: fail("combined legacy verification returned an unexpected error")

def verified.paths.valid.cloned(
  retained_path: String,
  paths: String & String
) -> IO(Unit):
  match paths:
    case (snapshot_path, verify_path):
      do IO<Unit>:
        snapshot_result : Result<&1, &1, MigrateIo.Error, MigrateIo.SourceSnapshot> <-
          MigrateIo.read_legacy_source(snapshot_path)
        snapshot.valid(snapshot_result, False{})
        result : Result<&1, &1, MigrateIo.Error, MigrateIo.SourceCounts> <-
          MigrateIo.verify_legacy_source(verify_path)
        verified(retained_path, result, False{})

def verified.paths.valid(paths: String & String) -> IO(Unit):
  match paths:
    case (retained_path, verify_path):
      verified.paths.valid.cloned(retained_path, path.clone.pair(verify_path))

def verified.paths.invalid.cloned(
  retained_path: String,
  paths: String & String
) -> IO(Unit):
  match paths:
    case (snapshot_path, verify_path):
      do IO<Unit>:
        snapshot_result : Result<&1, &1, MigrateIo.Error, MigrateIo.SourceSnapshot> <-
          MigrateIo.read_legacy_source(snapshot_path)
        snapshot.valid(snapshot_result, True{})
        result : Result<&1, &1, MigrateIo.Error, MigrateIo.SourceCounts> <-
          MigrateIo.verify_legacy_source(verify_path)
        verified(retained_path, result, True{})

def verified.paths.invalid(paths: String & String) -> IO(Unit):
  match paths:
    case (retained_path, verify_path):
      verified.paths.invalid.cloned(retained_path, path.clone.pair(verify_path))

def verified.paths(paths: String & String, expect_invalid: Bool) -> IO(Unit):
  match expect_invalid:
    case True{}: verified.paths.invalid(paths)
    case False{}: verified.paths.valid(paths)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_EXPECT_INVALID"))
    verified.paths(path.clone.pair(path), String.eq(mode, "true"))
