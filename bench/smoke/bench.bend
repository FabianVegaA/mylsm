import Base
import ../../mylsm.bend as MyLSM

# Takes the opened handle or stops the run.
def opened(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{handle}: IO.pure(MyLSM.Utf8.Handle, handle)
    case Fail{_}: IO.die(MyLSM.Utf8.Handle, 1, "bench database open failed")

# Takes the new handle, or opens the existing database.
def created(result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{handle}: IO.pure(MyLSM.Utf8.Handle, handle)
    case Fail{_}:
      do IO<MyLSM.Utf8.Handle>:
        existing : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
          MyLSM.Utf8.open_existing("bench-data")
        opened(existing)

# Takes the handle back after a write or stops the run.
def written(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(MyLSM.Utf8.Handle):
  match pair:
    case (handle, Done{_}): IO.pure(MyLSM.Utf8.Handle, handle)
    case (_, Fail{_}): IO.die(MyLSM.Utf8.Handle, 1, "bench put failed")

# Task 11 timing smoke benchmark. It records one acknowledged put and the
# elapsed time; larger loops can be layered on this same API after calibration.
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <- MyLSM.Utf8.create("bench-data")
    handle : MyLSM.Utf8.Handle <- created(result)
    t0 : Nat <- IO.now()
    pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
      MyLSM.Utf8.put(handle, "bench-key", "v")
    stored : MyLSM.Utf8.Handle <- written(pair)
    t1 : Nat <- IO.now()
    _closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(stored)
    IO.print("single_put_elapsed_ms=" ++ Nat.show(Nat.sub(t1, t0)))
    IO.print("single_put_ops=1")
