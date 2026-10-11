import Base
import ../../src/Console.bend as Console
import ../../src/Sstable.bend as Sstable
import ../../src/SstStreamIo.bend as SstStreamIo
import ../../src/transfer/MigrateIo.bend as MigrateIo

# Requires an oversized SST to be rejected before decoding.
def checked(result: Result<&1, &1, U32 & String, Sstable.Table>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("LEGACY_SST_SIZE_LIMIT_PASSED")
    case Done{_}: IO.die(Unit, 1, "oversized SST reached the decoder")

# Requires the migration validator to preserve the typed resource failure.
def migration.checked(result: Result<&1, &1, MigrateIo.Error, Nat>) -> IO(Unit):
  match result:
    case Fail{MigrateIo.ResourceLimit{}}:
      IO.print("LEGACY_MIGRATION_SIZE_LIMIT_PASSED")
    case _:
      IO.die(Unit, 1, "legacy migration did not report a resource limit")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_SST_PATH"))
    result : Result<&1, &1, U32 & String, Sstable.Table> <-
      SstStreamIo.read_table_limited(path, 67108864n)
    checked(result)
    db_path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    migration : Result<&1, &1, MigrateIo.Error, Nat> <-
      MigrateIo.verify_legacy_tables(db_path)
    migration.checked(migration)
