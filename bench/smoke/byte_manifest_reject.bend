import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Checks that a damaged manifest cannot produce a public byte handle.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("BYTE_MANIFEST_CORRUPTION_REJECTED")
    case Done{handle}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "corrupt manifest opened successfully")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing(path)
    opened(result)
