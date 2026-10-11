import Base
import ../../src/Console.bend as Console
import ../../src/transfer/BackupIo.bend as BackupIo
import ../../src/transfer/MigrateRunIo.bend as MigrateRunIo
import ../../mylsm.bend as MyLSM

# Stops the fixture when migration violates its expected failure behavior.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Requires migration to preserve a bundle that already existed.
def rejected(result: Result<&1, &1, MigrateRunIo.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{MigrateRunIo.Backup{BackupIo.AlreadyExists{}}}:
      IO.print("LEGACY_MIGRATION_BUNDLE_CONFLICT_REJECTED")
    case Fail{_}: fail("bundle collision returned an unexpected migration error")
    case Done{Unit{}}: fail("bundle collision unexpectedly migrated the source")

def migrate.paths(source: String, destination: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MigrateRunIo.Error, Unit> <-
      MyLSM.migrate_legacy(source, destination)
    rejected(result)

def main() -> IO(Unit):
  do IO<Unit>:
    source : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    destination : String <- IO.try(String, Console.get_env("MYLSM_MIGRATE_DEST"))
    migrate.paths(source, destination)
