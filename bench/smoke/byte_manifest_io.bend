import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Confirms a missing manifest preserves its host IO error classification.
def opened(result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>) -> IO(Unit):
  match result:
    case Fail{MyLSM.Io{_, _}}: IO.print("BYTE_MANIFEST_IO_CLASSIFIED")
    case Fail{_}: IO.die(Unit, 1, "manifest IO error was reported as another error")
    case Done{handle}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "database opened without its manifest")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing(path)
    opened(result)
