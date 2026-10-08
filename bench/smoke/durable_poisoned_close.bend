import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM

# Runs the closed step of this fixture.
def closed(result: Result<&1, &1, MyLSM.Error, Unit>, label: String) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      IO.print(label)
    case Fail{_}:
      IO.die(Unit, 1, "database close failed")

# Runs the seeded step of this fixture.
def seeded(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>) -> IO(Unit):
  match pair:
    case (handle, Done{_}):
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        closed(result, "SEEDED")
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "seed write failed")

# Runs the seed created step of this fixture.
def seed_created(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.put(handle, "seed", "value")
        seeded(pair)
    case Fail{_}:
      IO.die(Unit, 1, "database create failed")

# Continues the poisoned write fixture step.
def poisoned_write(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome>) -> IO(Unit):
  match pair:
    case (handle, Fail{MyLSM.Error{MyLSM.CommitUnknownError{}, _, _, _, _}}):
      do IO<Unit>:
        IO.print("POISONED")
        result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        closed(result, "POISONED_CLOSED")
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "write did not poison the handle")

# Continues the poisoned open fixture step.
def poisoned_open(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        IO.print("POISON_READY")
        pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, MyLSM.WriteOutcome> <- MyLSM.put(handle, "unknown", "value")
        poisoned_write(pair)
    case Fail{_}:
      IO.die(Unit, 1, "database open failed")

# Continues the reopened value fixture step.
def reopened_value(pair: MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{"value"}}):
      do IO<Unit>:
        IO.print("RECOVERED")
        result : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        closed(result, "REOPEN_CLOSED")
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Error, Unit> <- MyLSM.close(handle)
        IO.die(Unit, 1, "confirmed value was not recovered")

# Continues the reopened fixture step.
def reopened(result: Result<&1, &1, MyLSM.Error, MyLSM.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Handle & Result<&1, &1, MyLSM.Error, Maybe<&2, String>> <- MyLSM.get(handle, "seed")
        reopened_value(pair)
    case Fail{_}:
      IO.die(Unit, 1, "database reopen failed")

# Runs the run step of this fixture.
def run(+path: String, mode: String) -> IO(Unit):
  match mode:
    case "seed":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.create(path)
        seed_created(result)
    case "poison":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        poisoned_open(result)
    case _:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Error, MyLSM.Handle> <- MyLSM.open_existing(path)
        reopened(result)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_POISON_MODE"))
    run(path, mode)
