import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the fixture after a public open or read failure.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

# Reports that the newly discovered owner session closed cleanly.
def closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("OWNER_GENERATION_CLIENT_PASSED")
    case Fail{_}: fail("owner generation client close failed")

def get.closed(
  handle: MyLSM.Bytes.Handle,
  result: Result<&1, &1, MyLSM.Bytes.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match result:
    case Done{None{}}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        closed(result)
    case _:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.close(handle)
        fail("owner generation client read failed")

def get.pair(
  pair:
    MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
      Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (handle, result): get.closed(handle, result)

# Reads an absent key through the owner generation discovered at open.
def opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("owner generation client could not open owner")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error,
          Maybe<&1, Bytes.Bytes>> <- MyLSM.Bytes.get(handle, Bytes.new(0))
        get.pair(pair)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
      MyLSM.Bytes.open_existing_wait(path, 1000, 10)
    opened(result)
