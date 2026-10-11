import Base
import ../../src/Console.bend as Console
import ../../src/transfer/MigrateIo.bend as MigrateIo

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

def verified.paths(paths: String & String, mode: String) -> IO(Unit):
  match paths:
    case (retained_path, verify_path):
      do IO<Unit>:
        result : Result<&1, &1, MigrateIo.Error, MigrateIo.SourceCounts> <-
          MigrateIo.verify_legacy_source(verify_path)
        verified(retained_path, result, String.eq(mode, "true"))

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_EXPECT_INVALID"))
    verified.paths(path.clone.pair(path), mode)
