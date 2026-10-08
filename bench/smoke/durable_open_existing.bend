import Base
import ../../src/Db.bend as Db
import ../../src/Recover.bend as Recover
import ../../src/Console.bend as Console

# Continues the missing code fixture step.
def missing_code(is_missing: Bool) -> IO(Unit):
  match is_missing:
    case True{}:
      IO.print("OPEN_NOT_FOUND")
    case False{}:
      IO.die(Unit, U32.from_nat(1n), "missing manifest returned the wrong failure")

# Continues the missing fixture step.
def missing(result: Result<&1, &1, U32 & String, Db.Db>) -> IO(Unit):
  match result:
    case Fail{(code, _)}:
      missing_code(U32.is_eq(code, 2))
    case Done{_}:
      IO.die(Unit, U32.from_nat(1n), "empty directory opened as a database")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, U32 & String, Db.Db> <- Recover.open_existing_locked(path)
    missing(result)
