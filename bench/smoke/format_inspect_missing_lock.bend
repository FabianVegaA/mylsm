import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Confirms inspection refuses to create a lock file for an unlocked path.
def inspected(result: Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection>) -> IO(Unit):
  match result:
    case Fail{MyLSM.InspectionIo{2, _}}:
      IO.print("FORMAT_INSPECT_MISSING_LOCK_PASSED")
    case _:
      IO.die(Unit, 1, "inspection did not reject a missing LOCK file")

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection> <-
      MyLSM.inspect(path)
    inspected(result)
