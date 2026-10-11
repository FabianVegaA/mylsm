import Base
import ../../src/Console.bend as Console
import ../../src/transfer/MigrateIo.bend as MigrateIo

# Stops the fixture after an invalid legacy table is unexpectedly admitted.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Requires corruption to reject the table without changing source bytes.
def verified(result: Result<&1, &1, MigrateIo.Error, Nat>) -> IO(Unit):
  match result:
    case Fail{MigrateIo.InvalidLegacySst{}}:
      IO.print("LEGACY_SST_CORRUPTION_REJECTED")
    case _:
      fail("legacy SST corruption was not classified as invalid")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MigrateIo.Error, Nat> <-
      MigrateIo.verify_legacy_tables(path)
    verified(result)
