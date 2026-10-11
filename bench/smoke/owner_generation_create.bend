import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console

# Reports successful cleanup after initializing the fixture database.
def closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_GENERATION_DATABASE_CREATED")
    case Fail{_}: IO.die(Unit, 1, "owner generation database close failed")

# Creates the database used by the owner restart fixture.
def opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "owner generation database creation failed")
    case Done{handle}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        closed(result)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.create(path)
    opened(result)
