import Base
import ../../src/Console.bend as Console
import ../../src/transfer/MigrateIo.bend as MigrateIo
import ../../src/transfer/MigrateRunIo.bend as MigrateRunIo
import ../../mylsm.bend as MyLSM

# Stops the migration fixture when a corrupt source is unexpectedly accepted.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Requires corrupt source rejection to use the typed legacy SST error.
def checked(result: Result<&1, &1, MigrateRunIo.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{MigrateRunIo.Source{MigrateIo.InvalidLegacySst{}}}:
      IO.print("LEGACY_MIGRATION_CORRUPT_SOURCE_REJECTED")
    case Fail{_}: fail("corrupt source migration returned the wrong error")
    case Done{Unit{}}: fail("corrupt source migration published a destination")

# Attempts migration of the source selected by the host fixture.
def main() -> IO(Unit):
  do IO<Unit>:
    source : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    destination : String <- IO.try(String, Console.get_env("MYLSM_MIGRATE_DEST"))
    result : Result<&1, &1, MigrateRunIo.Error, Unit> <-
      MyLSM.migrate_legacy(source, destination)
    checked(result)
