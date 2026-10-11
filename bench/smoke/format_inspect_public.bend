import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Requires a durable generation-four manifest to inspect as valid.
def inspected(
  result: Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "public manifest inspection failed")
    case Done{MyLSM.ManifestInspection{"0.6.0.0", "0.6.0.0", 4,
        MyLSM.ManifestValid{}}}:
      IO.print("PUBLIC_FORMAT_INSPECT_PASSED")
    case Done{_}:
      IO.die(Unit, 1, "public manifest inspection returned the wrong identity")

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.InspectionError, MyLSM.ManifestInspection> <-
      MyLSM.inspect(path)
    inspected(result)
