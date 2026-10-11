import Base
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/Console.bend as Console
import ../../src/Keys.bend as Keys
import ../../src/scan/RangeCursor.bend as RangeCursor
import ../../src/scan/SstCursor.bend as SstCursor
import ../../src/scan/VisibleCursor.bend as VisibleCursor
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.fixture(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Decodes a closed hexadecimal fixture value.
def bytes(hex: String) -> Bytes.Bytes:
  bytes.fixture(Bytes.from_hex(hex))

# Stops the fixture when a merge outcome differs from its expected record.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def close.checked(
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Fail{(_, message)}: fail(message)
    case Done{Unit{}}: IO.print("VISIBLE_CURSOR_MERGE_PASSED")

# Verifies explicit source closure after the merged range reaches its end.
def finish(cursor: VisibleCursor.Cursor) -> IO(Unit):
  do IO<Unit>:
    closed : Result<&1, &1, U32 & String, Unit> <- VisibleCursor.close(cursor)
    close.checked(closed)

def third.result(result: VisibleCursor.Step) -> IO(Unit):
  match result:
    case VisibleCursor.End{}: IO.print("VISIBLE_CURSOR_MERGE_PASSED")
    case VisibleCursor.Skip{cursor}: finish(cursor)
    case VisibleCursor.Error{(_, message)}: fail(message)
    case _: fail("visible cursor emitted the shadowed SST key")

def second.checked(cursor: VisibleCursor.Cursor, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        next : VisibleCursor.Step <- VisibleCursor.next(cursor)
        third.result(next)
    case False{}: fail("visible cursor did not emit the delta-only value")

def second.result(result: VisibleCursor.Step) -> IO(Unit):
  match result:
    case VisibleCursor.Item{entry, cursor}:
      match entry:
        case ByteMemTable.Entry{key, Some{value}}:
          second.checked(cursor, Bool.and(Keys.Bytes.eq(key, bytes("0001")),
            Keys.Bytes.eq(value, bytes("33"))))
        case _: fail("visible cursor emitted an empty delta value")
    case VisibleCursor.Error{(_, message)}: fail(message)
    case _: fail("visible cursor omitted the delta-only key")

def after.tombstone(result: VisibleCursor.Step) -> IO(Unit):
  match result:
    case VisibleCursor.Skip{cursor}:
      do IO<Unit>:
        next : VisibleCursor.Step <- VisibleCursor.next(cursor)
        second.result(next)
    case VisibleCursor.Error{(_, message)}: fail(message)
    case _: fail("visible cursor did not suppress the SST value under a tombstone")

def first.checked(cursor: VisibleCursor.Cursor, valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      do IO<Unit>:
        next : VisibleCursor.Step <- VisibleCursor.next(cursor)
        after.tombstone(next)
    case False{}: fail("visible cursor did not prefer the delta replacement")

def first.result(result: VisibleCursor.Step) -> IO(Unit):
  match result:
    case VisibleCursor.Item{entry, cursor}:
      match entry:
        case ByteMemTable.Entry{key, Some{value}}:
          first.checked(cursor, Bool.and(Keys.Bytes.eq(key, bytes("00")),
            Keys.Bytes.eq(value, bytes("39"))))
        case _: fail("visible cursor emitted an empty replacement")
    case VisibleCursor.Error{(_, message)}: fail(message)
    case _: fail("visible cursor omitted the first merged value")

# Starts the incremental merge from the verified two-record SST fixture.
def opened(
  delta: List<&1, ByteMemTable.Entry>,
  bounds: RangeCursor.Bounds,
  result: Result<&1, &1, U32 & String, SstCursor.Cursor>
) -> IO(Unit):
  match result:
    case Fail{(_, message)}: fail(message)
    case Done{base}:
      do IO<Unit>:
        next : VisibleCursor.Step <-
          VisibleCursor.next(VisibleCursor.open(Some{base}, delta, bounds))
        first.result(next)

def main() -> IO(Unit):
  do IO<Unit>:
    +path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    result : Result<&1, &1, U32 & String, SstCursor.Cursor> <-
      SstCursor.open.trusted(path ++ "/SST",
        SstCursor.Bounds{None{}, None{}, None{}})
    opened([
      ByteMemTable.Entry{bytes("00"), Some{bytes("39")}},
      ByteMemTable.Entry{bytes("0000"), None{}},
      ByteMemTable.Entry{bytes("0001"), Some{bytes("33")}}
    ], RangeCursor.Bounds{None{}, None{}, None{}}, result)
