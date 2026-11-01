import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Reports checksummed-manifest corruption as inspection data.
def inspected(result: Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection>) -> IO(Unit):
  match result:
    case Done{MyLSM.ManifestInspection{"0.6.0.0", "0.6.0.0", 4,
        MyLSM.ManifestCorrupt{}}}:
      IO.print("FORMAT_INSPECT_CORRUPT_PASSED")
    case _:
      IO.die(Unit, 1, "inspection did not report manifest corruption")

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection> <-
      MyLSM.inspect(path)
    inspected(result)
