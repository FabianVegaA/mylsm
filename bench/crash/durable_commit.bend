import Base
import ../../src/Console.bend as Console
import ../../mylsm.bend as MyLSM

# Runs the close result step of this fixture.
def close_result(result: Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "close failed")
    case Done{Unit{}}:
      IO.print("CLOSED")

# Runs the seed written step of this fixture.
def seed_written(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "seed write failed")
    case (handle, Done{_}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        close_result(closed)

# Runs the seed created step of this fixture.
def seed_created(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "seed create failed")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
          MyLSM.Utf8.write_batch(handle,
            [MyLSM.Utf8SetValue{"a", "old"}, MyLSM.Utf8SetValue{"b", "old"}])
        seed_written(pair)

# Runs the write finished step of this fixture.
def write_finished(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "write failed")
    case (handle, Done{_}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        close_result(closed)

# Continues the crash write fixture step.
def crash_write(handle: MyLSM.Utf8.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
      MyLSM.Utf8.write_batch(handle, [MyLSM.Utf8SetValue{"a", "new"},
        MyLSM.Utf8SetValue{"b", "new"}, MyLSM.Utf8SetValue{"pad", String.repeat("x", 70000n)}])
    write_finished(pair)

# Runs the flush result step of this fixture.
def flush_result(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "flush failed")
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        close_result(result)

# Runs the flush finished step of this fixture.
def flush_finished(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>) -> IO(Unit):
  match pair:
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "write before flush failed")
    case (handle, Done{_}):
      do IO<Unit>:
        result : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.flush(handle)
        flush_result(result)

# Continues the crash flush fixture step.
def crash_flush(handle: MyLSM.Utf8.Handle) -> IO(Unit):
  do IO<Unit>:
    pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.write_batch(handle, Con{MyLSM.Utf8SetValue{"a", "new"}, Con{MyLSM.Utf8SetValue{"b", "new"}, Nil{}}})
    flush_finished(pair)

# Runs the inspection step of this fixture.
def inspection(first: String, second: String) -> IO(String):
  match first second:
    case "old" "old": IO.pure(String, "old")
    case "new" "new": IO.pure(String, "new")
    case _ _: IO.die(String, 1, "batch recovered partially")

# Runs the inspect second step of this fixture.
def inspect_second(first: String, pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (next, Done{Some{second}}):
      do IO<Unit>:
        found : String <- inspection(first, second)
        IO.print("RECOVERED_" ++ found)
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(next)
        IO.print("CLOSED")
    case (next, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(next)
        IO.die(Unit, 1, "second key missing")

# Runs the inspect first step of this fixture.
def inspect_first(pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>) -> IO(Unit):
  match pair:
    case (handle, Done{Some{first}}):
      do IO<Unit>:
        next : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <- MyLSM.Utf8.get(handle, "b")
        inspect_second(first, next)
    case (handle, _):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        IO.die(Unit, 1, "first key missing")

# Runs the open pair step of this fixture.
def open_pair(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>, mode: String) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "open failed")
    case Done{handle}:
      match mode:
        case "wal":
          crash_write(handle)
        case "flush":
          crash_flush(handle)
        case "inspect":
          do IO<Unit>:
            pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <- MyLSM.Utf8.get(handle, "a")
            inspect_first(pair)
        case _:
          IO.die(Unit, 1, "unsupported mode")

# Runs the run mode step of this fixture.
def run_mode(+path: String, mode: String) -> IO(Unit):
  match mode:
    case "seed":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.create(path)
        seed_created(result)
    case "wal":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.open_existing(path)
        open_pair(result, mode)
    case "flush":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.open_existing(path)
        open_pair(result, mode)
    case "inspect":
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.open_existing(path)
        open_pair(result, mode)
    case _:
      IO.die(Unit, 1, "unsupported mode")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_DURABLE_MODE"))
    run_mode(path, mode)
