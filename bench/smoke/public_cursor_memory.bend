import Base
import ../../mylsm.bend as MyLSM
import ../../src/Console.bend as Console
import ../../src/Decimal.bend as Decimal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def parsed.count(parsed: Decimal.Parse) -> Nat:
  match parsed:
    case Decimal.Accepted{parsed}: Decimal.parsed_value(parsed)
    case _: 0n

def count.from.env(text: String) -> Nat:
  parsed.count(Decimal.parse_complete(text, 4294967295n))

# Encodes an ordered integer as a fixed-width byte key.
def key(index: Nat) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, U32.from_nat(index))

# Produces one fixed-size value for memory scaling measurements.
def value() -> Bytes.Bytes:
  Bytes.new(16)

def mutations.loop(
  fuel: Nat,
  +index: Nat,
  acc: List<&1, MyLSM.Bytes.Mutation>
) -> List<&1, MyLSM.Bytes.Mutation>:
  match fuel:
    case 0n: List.reverse(&1, MyLSM.Bytes.Mutation, acc)
    case 1n+rest:
      +key_index = index
      +next_index = Nat.add(index, 1n)
      mutations.loop(rest, next_index,
        Con{MyLSM.BytesPut{key(key_index), value()}, acc})

def created.closed(result: Result<&1, &1, MyLSM.Bytes.Error, Unit>) -> IO(Unit):
  match result:
    case Done{Unit{}}: IO.print("CURSOR_DATASET_CREATED")
    case Fail{_}: IO.die(Unit, 1, "cursor memory database close failed")

# Describes the public error returned by the measured database operation.
def created.error(error: MyLSM.Bytes.Error) -> String:
  match error:
    case MyLSM.Busy{}: "Busy"
    case MyLSM.Timeout{}: "Timeout"
    case MyLSM.ResourceLimit{}: "ResourceLimit"
    case MyLSM.InvalidArgument{}: "InvalidArgument"
    case MyLSM.Corruption{message}: "Corruption: " ++ message
    case MyLSM.Io{code, message}: "Io " ++ U32.show(code) ++ ": " ++ message
    case MyLSM.CommitUnknown{code, message}:
      "CommitUnknown " ++ U32.show(code) ++ ": " ++ message
    case MyLSM.NotFound{}: "NotFound"
    case MyLSM.AlreadyExists{}: "AlreadyExists"
    case MyLSM.UnsupportedPlatform{}: "UnsupportedPlatform"
    case MyLSM.UnsupportedOperation{}: "UnsupportedOperation"
    case MyLSM.StaleOwner{}: "StaleOwner"

def created.failure(
  error: MyLSM.Bytes.Error,
  stage: String,
  failed_index: Nat
) -> IO(Unit):
  IO.die(Unit, 1, "cursor memory " ++ stage ++ " failed at " ++
    Nat.show(failed_index) ++ ": " ++ created.error(error))

def created.flushed(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        created.closed(closed)
    case (handle, Fail{error}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        created.failure(error, "flush", 0n)

def created.written(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match pair:
    case (handle, Done{Unit{}}):
      do IO<Unit>:
        flushed : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.flush(handle)
        created.flushed(flushed)
    case (handle, Fail{_}):
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        IO.die(Unit, 1, "cursor memory database write failed")

# Tracks chunked dataset creation without exceeding the public batch limit.
type CreateState is Type:
  CreateNext{handle: MyLSM.Bytes.Handle, index: Nat, batch_count: Nat}
  CreateFinished{handle: MyLSM.Bytes.Handle}
  CreateWritten{
    pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit>,
    next_index: Nat
  }

def created.batch.count.last(+index: Nat, +total: Nat, last: Bool) -> Nat:
  match last:
    case True{}: Nat.sub(total, index)
    case False{}: 256n

def created.batch.count.finished(+index: Nat, +total: Nat, finished: Bool) -> Nat:
  match finished:
    case True{}: 0n
    case False{}:
      created.batch.count.last(index, total, Nat.is_le(total, Nat.add(index, 256n)))

def created.batch.count(+index: Nat, +total: Nat) -> Nat:
  created.batch.count.finished(index, total, Nat.is_le(total, index))

def created.batch.state.result(
  handle: MyLSM.Bytes.Handle,
  +index: Nat,
  batch_count: Nat
) -> CreateState:
  match batch_count:
    case 0n: CreateFinished{handle}
    case count: CreateNext{handle, index, count}

def created.batch.state(
  handle: MyLSM.Bytes.Handle,
  +index: Nat,
  +total: Nat
) -> CreateState:
  created.batch.state.result(handle, index, created.batch.count(index, total))

def created.batch.loop(fuel: Nat, +total: Nat, state: CreateState) -> IO(Unit):
  match fuel, state:
    case 0n, _:
      IO.die(Unit, 1, "cursor memory dataset creation exceeded its batch budget")
    case 1n+rest, CreateNext{handle, index, batch_count}:
      +batch_index = index
      +batch_size = batch_count
      +next_index = Nat.add(batch_index, batch_size)
      do IO<Unit>:
        mutations : List<&1, MyLSM.Bytes.Mutation> =
          mutations.loop(batch_size, batch_index, Nil{})
        written : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, Unit> <-
          MyLSM.Bytes.write_batch(handle, mutations)
        created.batch.loop(rest, total,
          CreateWritten{written, next_index})
    case 1n+rest, CreateFinished{handle}:
      created.written((handle, Done{Unit{}}))
    case 1n+rest, CreateWritten{(handle, Fail{error}), failed_index}:
      do IO<Unit>:
        _closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        created.failure(error, "batch", failed_index)
    case 1n+rest, CreateWritten{(handle, Done{Unit{}}), next_index}:
      created.batch.loop(rest, total, created.batch.state(handle, next_index, total))

def created.result(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>,
  +count: Nat
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "cursor memory database create failed")
    case Done{handle}:
      created.batch.loop(Nat.add(count, 1n), count, created.batch.state(handle, 0n, count))

def cursor.finish.closed(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  count: Nat
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "cursor memory handle did not close")
    case Done{Unit{}}: IO.print("CURSOR_RECORDS=" ++ Nat.show(count))

def cursor.finish.result(
  handle: MyLSM.Bytes.Handle,
  cursor_closed: Result<&1, &1, MyLSM.Bytes.Error, Unit>,
  count: Nat
) -> IO(Unit):
  match cursor_closed:
    case Fail{_}: IO.die(Unit, 1, "cursor memory scan did not close")
    case Done{Unit{}}:
      do IO<Unit>:
        closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
        cursor.finish.closed(closed, count)

def cursor.finish(
  handle: MyLSM.Bytes.Handle,
  cursor: MyLSM.Bytes.Cursor,
  count: Nat
) -> IO(Unit):
  do IO<Unit>:
    cursor_closed : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.scan_close(cursor)
    cursor.finish.result(handle, cursor_closed, count)

# Alternates between one cursor read and classifying its returned step.
type CursorState is Type:
  CursorNext{cursor: MyLSM.Bytes.Cursor, count: Nat}
  CursorRead{step: MyLSM.Bytes.StreamStep, count: Nat}
  CursorStop{cursor: MyLSM.Bytes.Cursor, count: Nat}

def cursor.state.next.result(
  cursor: MyLSM.Bytes.Cursor,
  count: Nat,
  stopped: Bool
) -> CursorState:
  match stopped:
    case True{}: CursorStop{cursor, count}
    case False{}: CursorNext{cursor, count}

def cursor.state.next(
  cursor: MyLSM.Bytes.Cursor,
  +count: Nat,
  +limit: Nat
) -> CursorState:
  cursor.state.next.result(cursor, count, Nat.is_le(limit, count))

def cursor.loop(
  fuel: Nat,
  handle: MyLSM.Bytes.Handle,
  state: CursorState,
  +limit: Nat
) -> IO(Unit):
  match fuel, state:
    case 0n, _:
      IO.die(Unit, 1, "cursor memory scan exceeded its record budget")
    case 1n+rest, CursorNext{cursor, count}:
      do IO<Unit>:
        step : MyLSM.Bytes.StreamStep <- MyLSM.Bytes.scan_next(cursor)
        cursor.loop(rest, handle, CursorRead{step, count}, limit)
    case 1n+rest, CursorRead{MyLSM.StreamItem{_, _, cursor}, count}:
      cursor.loop(rest, handle, cursor.state.next(cursor, Nat.add(count, 1n), limit), limit)
    case 1n+rest, CursorRead{MyLSM.StreamSkip{cursor}, count}:
      cursor.loop(rest, handle, cursor.state.next(cursor, count, limit), limit)
    case _, CursorRead{MyLSM.StreamEnd{cursor}, count}:
      cursor.finish(handle, cursor, count)
    case _, CursorRead{MyLSM.StreamFailure{_, _}, _}:
      IO.die(Unit, 1, "cursor memory scan returned an IO failure")
    case _, CursorStop{cursor, count}:
      cursor.finish(handle, cursor, count)

def scan.opened(
  pair: MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor>,
  +count: Nat
) -> IO(Unit):
  match pair:
    case (handle, Fail{_}): IO.die(Unit, 1, "cursor memory scan did not open")
    case (handle, Done{cursor}):
      cursor.loop(Nat.add(Nat.mul(count, 2n), 2n), handle,
        cursor.state.next(cursor, 0n, count), count)

# Opens a database and starts a public scan over its persisted records.
def opened(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>,
  limit: Nat
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "cursor memory database open failed")
    case Done{handle}:
      do IO<Unit>:
        pair : MyLSM.Bytes.Handle & Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Cursor> <-
          MyLSM.Bytes.scan(handle, MyLSM.ScanBounds{None{}, None{}, None{}})
        scan.opened(pair, limit)

def opened.close.result(
  result: Result<&1, &1, MyLSM.Bytes.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "cursor memory database close failed")
    case Done{Unit{}}: IO.print("CURSOR_OPENED")

def opened.close(handle: MyLSM.Bytes.Handle) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, MyLSM.Bytes.Error, Unit> <- MyLSM.Bytes.close(handle)
    opened.close.result(result)

def opened.only(
  result: Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle>
) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "cursor memory database open failed")
    case Done{handle}: opened.close(handle)

def mode.creates(mode: String) -> Bool:
  String.eq(mode, "create")

def mode.opens_only(mode: String) -> Bool:
  String.eq(mode, "open")

def run.mode.result(
  path: String,
  count: Nat,
  limit: Nat,
  create: Bool,
  open_only: Bool
) -> IO(Unit):
  match create:
    case True{}:
      do IO<Unit>:
        result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
          MyLSM.Bytes.create(path)
        created.result(result, count)
    case False{}:
      match open_only:
        case True{}:
          do IO<Unit>:
            result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
              MyLSM.Bytes.open_existing(path)
            opened.only(result)
        case False{}:
          do IO<Unit>:
            result : Result<&1, &1, MyLSM.Bytes.Error, MyLSM.Bytes.Handle> <-
              MyLSM.Bytes.open_existing(path)
            opened(result, limit)

def run.mode(path: String, +mode: String, count: Nat, limit: Nat) -> IO(Unit):
  run.mode.result(path, count, limit, mode.creates(mode), mode.opens_only(mode))

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    mode : String <- IO.try(String, Console.get_env("MYLSM_CURSOR_MODE"))
    count_text : String <- IO.try(String, Console.get_env("MYLSM_CURSOR_COUNT"))
    limit_text : String <- IO.try(String, Console.get_env("MYLSM_CURSOR_SCAN_LIMIT"))
    count : Nat = count.from.env(count_text)
    limit : Nat = count.from.env(limit_text)
    run.mode(path, mode, count, limit)
