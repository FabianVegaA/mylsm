import Base
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/Console.bend as Console
import ../../src/Keys.bend as Keys
import ../../src/scan/SstCursor.bend as SstCursor
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Requires the scan to end at the exclusive upper bound.
def finish(result: SstCursor.Step) -> IO(Unit):
  match result:
    case SstCursor.End{}: IO.print("SST_CURSOR_UPPER_BOUND_PASSED")
    case SstCursor.Error{(_, message)}: IO.die(Unit, 1, message)
    case _: IO.die(Unit, 1, "SST cursor returned more records than expected")

# Confirms the second byte key and terminal cursor result.
def second(result: SstCursor.Step) -> IO(Unit):
  match result:
    case SstCursor.End{}: finish(result)
    case SstCursor.Skip{_}:
      IO.die(Unit, 1, "SST upper-bound key must terminate instead of being skipped")
    case SstCursor.Error{(_, message)}: IO.die(Unit, 1, message)
    case _: IO.die(Unit, 1, "SST cursor returned the exclusive upper-bound key")

def first.key.checked(valid: Bool, cursor: SstCursor.Cursor) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        next : SstCursor.Step <-
          SstCursor.next(SstCursor.seek(cursor, Some{Bytes.new(2)}))
        second(next)
    case False{}: IO.die(Unit, 1, "SST cursor returned the wrong first key")

# Confirms the first byte key before requesting the next record.
def first(result: SstCursor.Step) -> IO(Unit):
  match result:
    case SstCursor.Item{entry, cursor}:
      match entry:
        case ByteMemTable.Entry{key, _}:
          first.key.checked(Keys.Bytes.eq(key, Bytes.new(1)), cursor)
    case SstCursor.Skip{_}:
      IO.die(Unit, 1, "unbounded SST scan unexpectedly skipped a record")
    case SstCursor.Error{(_, message)}: IO.die(Unit, 1, message)
    case _: IO.die(Unit, 1, "SST cursor returned no first record")

# Starts the verified scan and checks its first record.
def opened(result: Result<&1, &1, U32 & String, SstCursor.Cursor>) -> IO(Unit):
  match result:
    case Fail{(_, message)}: IO.die(Unit, 1, message)
    case Done{cursor}:
      do IO<Unit>:
        next : SstCursor.Step <- SstCursor.next(cursor)
        first(next)

def route.finished(result: SstCursor.Step) -> IO(Unit):
  match result:
    case SstCursor.End{}: IO.print("SST_CURSOR_KEY_ROUTE_PASSED")
    case SstCursor.Error{(_, message)}: IO.die(Unit, 1, message)
    case _: IO.die(Unit, 1, "routed SST cursor returned a later key")

def route.second.checked(cursor: SstCursor.Cursor, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        next : SstCursor.Step <- SstCursor.next(cursor)
        route.finished(next)
    case False{}:
      do IO<Unit>:
        _closed : Result<&1, &1, U32 & String, Unit> <- SstCursor.close(cursor)
        IO.die(Unit, 1, "routed SST cursor returned the wrong key")

def route.second(result: SstCursor.Step) -> IO(Unit):
  match result:
    case SstCursor.Item{entry, cursor}:
      match entry:
        case ByteMemTable.Entry{key, _}:
          route.second.checked(cursor, Keys.Bytes.eq(key, Bytes.new(2)))
    case SstCursor.Error{(_, message)}: IO.die(Unit, 1, message)
    case _: IO.die(Unit, 1, "routed SST cursor did not reach the lower key")

def route.opened(result: Result<&1, &1, U32 & String, SstCursor.Cursor>) -> IO(Unit):
  match result:
    case Fail{(_, message)}: IO.die(Unit, 1, message)
    case Done{cursor}:
      do IO<Unit>:
        next : SstCursor.Step <- SstCursor.next(cursor)
        route.second(next)

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, U32 & String, SstCursor.Cursor> <-
      SstCursor.open(path ++ "/SST",
        SstCursor.Bounds{Some{Bytes.new(1)}, Some{Bytes.new(2)},
          Some{Bytes.new(1)}})
    _opened : Unit <- opened(result)
    routed : Result<&1, &1, U32 & String, SstCursor.Cursor> <-
      SstCursor.open(path ++ "/SST",
        SstCursor.Bounds{Some{Bytes.new(2)}, None{}, None{}})
    route.opened(routed)
