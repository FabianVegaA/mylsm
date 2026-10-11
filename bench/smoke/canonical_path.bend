import Base
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs

# Prints the resolved path or fails the fixture.
def show(result: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "database path canonicalization failed")
    case Done{path}: IO.print(path)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    canonical : Result<&1, &1, U32 & String, String> <- Fs.canonical_path(path)
    show(canonical)
