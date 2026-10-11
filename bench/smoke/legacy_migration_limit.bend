import Base
import ../../src/Console.bend as Console
import ../../src/transfer/MigrateIo.bend as MigrateIo
import ../../src/transfer/MigrateRunIo.bend as MigrateRunIo
import ../../mylsm.bend as MyLSM

# Stops the fixture when migration fails to preserve the resource rejection.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Accepts only the typed source-byte budget failure.
def checked(result: Result<&1, &1, MigrateRunIo.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{MigrateRunIo.Source{MigrateIo.ResourceLimit{}}}:
      IO.print("LEGACY_MIGRATION_RESOURCE_LIMIT_REJECTED")
    case Fail{_}: fail("migration limit returned the wrong failure")
    case Done{Unit{}}: fail("oversized legacy source was published")

def main() -> IO(Unit):
  do IO<Unit>:
    source : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    destination : String <- IO.try(String, Console.get_env("MYLSM_MIGRATE_DEST"))
    result : Result<&1, &1, MigrateRunIo.Error, Unit> <-
      MyLSM.migrate_legacy(source, destination)
    checked(result)
