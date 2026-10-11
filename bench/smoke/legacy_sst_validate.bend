import Base
import ../../src/Console.bend as Console
import ../../src/transfer/MigrateIo.bend as MigrateIo

# Stops the validation fixture after a failed assertion.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Requires the read-only SST validator to find both source records.
def verified(result: Result<&1, &1, MigrateIo.Error, Nat>) -> IO(Unit):
  match result:
    case Done{2n}: IO.print("LEGACY_SST_READ_ONLY_PASSED")
    case Done{_}: fail("legacy SST validation returned the wrong record count")
    case Fail{_}: fail("legacy SST validation rejected its valid fixture")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MigrateIo.Error, Nat> <-
      MigrateIo.verify_legacy_tables(path)
    verified(result)
