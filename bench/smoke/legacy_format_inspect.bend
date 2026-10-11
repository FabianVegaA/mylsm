import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Requires legacy package and storage identity with a valid manifest.
def inspected(
  result: Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection>
) -> IO(Unit):
  match result:
    case Done{MyLSM.ManifestInspection{"0.5.0.0", "0.4.0.0", 3,
        MyLSM.ManifestValid{}}}:
      IO.print("LEGACY_FORMAT_INSPECT_PASSED")
    case _:
      IO.die(Unit, 1, "legacy source identity or integrity was not preserved")

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection> <-
      MyLSM.inspect(path)
    inspected(result)
