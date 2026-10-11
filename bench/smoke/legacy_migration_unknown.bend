import Base
import ../../src/Console.bend as Console
import ../../src/transfer/MigrateIo.bend as MigrateIo
import ../../src/transfer/MigrateRunIo.bend as MigrateRunIo
import ../../mylsm.bend as MyLSM

# Stops the migration fixture when an unknown-format rejection is incorrect.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Accepts only the typed invalid-manifest result from migration preflight.
def checked(result: Result<&1, &1, MigrateRunIo.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{MigrateRunIo.Source{MigrateIo.InvalidLegacyManifest{}}}:
      IO.print("LEGACY_MIGRATION_UNKNOWN_VERSION_REJECTED")
    case Fail{_}: fail("unknown migration version returned the wrong error")
    case Done{Unit{}}: fail("unknown migration version was published")

def main() -> IO(Unit):
  do IO<Unit>:
    source : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    destination : String <- IO.try(String, Console.get_env("MYLSM_MIGRATE_DEST"))
    result : Result<&1, &1, MigrateRunIo.Error, Unit> <-
      MyLSM.migrate_legacy(source, destination)
    checked(result)
