import Base
import ../../mylsm.bend as MyLSM
import ./demo_helpers.bend as Demo

# Holds the values the demo prints after its writes and delete.
type Report is Data:
  Report{before: String, answer: String, after: String}

# Stops the demo with a message after a failed database step.
def fail(-A: Type, message: String) -> IO(A):
  IO.die(A, 1, "demo failed: " ++ message)

# Takes the opened handle or stops the demo.
def opened(
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>
) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{handle}: IO.pure(MyLSM.Utf8.Handle, handle)
    case Fail{_}: fail(MyLSM.Utf8.Handle, "open")

def created.or.opened(
  +dir: String,
  result: Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle>
) -> IO(MyLSM.Utf8.Handle):
  match result:
    case Done{handle}: IO.pure(MyLSM.Utf8.Handle, handle)
    case Fail{_}:
      do IO<MyLSM.Utf8.Handle>:
        existing : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
          MyLSM.Utf8.open_existing(dir)
        opened(existing)

# Opens the demo database, creating it on first use.
def open(+dir: String) -> IO(MyLSM.Utf8.Handle):
  do IO<MyLSM.Utf8.Handle>:
    created : Result<&1, &1, MyLSM.Utf8.Error, MyLSM.Utf8.Handle> <-
      MyLSM.Utf8.create(dir)
    created.or.opened(dir, created)

# Takes the handle back after a write or stops the demo.
def written(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit>
) -> IO(MyLSM.Utf8.Handle):
  match pair:
    case (handle, Done{_}): IO.pure(MyLSM.Utf8.Handle, handle)
    case (_, Fail{_}): fail(MyLSM.Utf8.Handle, "write")

# Writes one key and value.
def put(handle: MyLSM.Utf8.Handle, key: String, value: String) -> IO(MyLSM.Utf8.Handle):
  do IO<MyLSM.Utf8.Handle>:
    pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
      MyLSM.Utf8.put(handle, key, value)
    written(pair)

# Deletes one key.
def delete(handle: MyLSM.Utf8.Handle, key: String) -> IO(MyLSM.Utf8.Handle):
  do IO<MyLSM.Utf8.Handle>:
    pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Unit> <-
      MyLSM.Utf8.delete(handle, key)
    written(pair)

# Shows a read value or stops the demo.
def read(
  pair: MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>>
) -> IO(MyLSM.Utf8.Handle & String):
  match pair:
    case (handle, Done{value}):
      IO.pure(MyLSM.Utf8.Handle & String, (handle, Demo.show_maybe(value)))
    case (_, Fail{_}): fail(MyLSM.Utf8.Handle & String, "read")

# Reads one key and shows it the way the demo prints values.
def get(handle: MyLSM.Utf8.Handle, key: String) -> IO(MyLSM.Utf8.Handle & String):
  do IO<MyLSM.Utf8.Handle & String>:
    pair : MyLSM.Utf8.Handle & Result<&1, &1, MyLSM.Utf8.Error, Maybe<&2, String>> <-
      MyLSM.Utf8.get(handle, key)
    read(pair)

# Prints the demo report after the database closes.
def finish(closed: Result<&1, &1, MyLSM.Utf8.Error, Unit>, report: Report) -> IO(Unit):
  match closed:
    case Fail{_}: fail(Unit, "close")
    case Done{Unit{}}:
      match report:
        case Report{before, answer, after}:
          do IO<Unit>:
            compute : Nat <- IO.pure(Nat, Demo.worker_gpu!(32n, 0n))
            _title : Unit <- IO.print("MyLSM demo")
            _hello : Unit <- IO.print("  hello = " ++ before)
            _answer : Unit <- IO.print("  answer = " ++ answer)
            _after : Unit <- IO.print("  hello after delete = " ++ after)
            _compute : Unit <- IO.print("  compute = " ++ Nat.show(compute))
            IO.print("MYLSM DEMO OK")

def checked.after(
  before: String,
  answer: String,
  pair: MyLSM.Utf8.Handle & String
) -> IO(Unit):
  match pair:
    case (handle, after):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Utf8.Error, Unit> <- MyLSM.Utf8.close(handle)
        finish(closed, Report{before, answer, after})

def checked.answer(before: String, pair: MyLSM.Utf8.Handle & String) -> IO(Unit):
  match pair:
    case (handle, answer):
      do IO<Unit>:
        deleted : MyLSM.Utf8.Handle <- delete(handle, "hello")
        after : MyLSM.Utf8.Handle & String <- get(deleted, "hello")
        checked.after(before, answer, after)

def checked.before(pair: MyLSM.Utf8.Handle & String) -> IO(Unit):
  match pair:
    case (handle, before):
      do IO<Unit>:
        answer : MyLSM.Utf8.Handle & String <- get(handle, "answer")
        checked.answer(before, answer)

def main() -> IO(Unit):
  do IO<Unit>:
    handle : MyLSM.Utf8.Handle <- open(".mylsm-demo-data")
    first : MyLSM.Utf8.Handle <- put(handle, "hello", "world")
    second : MyLSM.Utf8.Handle <- put(first, "answer", "42")
    before : MyLSM.Utf8.Handle & String <- get(second, "hello")
    checked.before(before)
