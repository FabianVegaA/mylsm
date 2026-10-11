import Base
import ../../src/Console.bend as Console
import ../../src/transfer/MigrateIo.bend as MigrateIo

# Requires the combined legacy SST source budget to fail before decoding.
def verified(result: Result<&1, &1, MigrateIo.Error, Nat>) -> IO(Unit):
  match result:
    case Fail{MigrateIo.ResourceLimit{}}:
      IO.print("LEGACY_SST_AGGREGATE_LIMIT_PASSED")
    case _:
      IO.die(Unit, 1, "aggregate legacy SST budget was not enforced")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MigrateIo.Error, Nat> <-
      MigrateIo.verify_legacy_tables(path)
    verified(result)
