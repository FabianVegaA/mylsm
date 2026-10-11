import Base
import ../../src/scan/RangeCursor.bend as Cursor
import ../../src/ByteMemTable.bend as ByteMemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def packed.parsed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Decodes fixed hexadecimal keys used by the bounded cursor fixture.
def packed(hex: String) -> Bytes.Bytes:
  packed.parsed(Bytes.from_hex(hex))

# Creates a prefix-filtered range with an inclusive lower bound.
def bounds() -> Cursor.Bounds:
  Cursor.Bounds{Some{packed("00")}, None{}, Some{packed("00")}}

# Builds one matching and one nonmatching ordered byte key.
def entries() -> List<&1, ByteMemTable.Entry>:
  Con{
    ByteMemTable.Entry{packed("0001"), Some{packed("80ff")}},
    Con{ByteMemTable.Entry{packed("ff"), Some{packed("610062")}}, Nil{}}
  }

def upper.bounds() -> Cursor.Bounds:
  Cursor.Bounds{None{}, Some{packed("63")}, None{}}

def upper.entries() -> List<&1, ByteMemTable.Entry>:
  Con{ByteMemTable.Entry{packed("63"), Some{packed("31")}},
    Con{ByteMemTable.Entry{packed("64"), Some{packed("32")}}, Nil{}}}

def upper.stop.result(step: Cursor.Step) -> IO(Unit):
  match step:
    case Cursor.RangeEnd{Cursor.RangeEnded{}, _}:
      IO.print("BYTE_RANGE_CURSOR_UPPER_STOP_PASSED")
    case _: IO.die(Unit, 1, "ordered cursor read past its exclusive upper bound")

def terminal.result(step: Cursor.Step) -> IO(Unit):
  match step:
    case Cursor.RangeEnd{_, _}: IO.print("BYTE_RANGE_CURSOR_FILTERED")
    case _: IO.die(Unit, 1, "bounded byte cursor did not finish after filtering")

def skipped.result(step: Cursor.Step) -> IO(Unit):
  match step:
    case Cursor.RangeSkip{cursor, retained}:
      terminal.result(Cursor.next(cursor, Cursor.bounds.clone(retained)))
    case _: IO.die(Unit, 1, "byte prefix cursor did not skip the nonmatching key")

def first.result(step: Cursor.Step) -> IO(Unit):
  match step:
    case Cursor.RangeItem{_, cursor, retained}:
      skipped.result(Cursor.next(cursor, Cursor.bounds.clone(retained)))
    case _: IO.die(Unit, 1, "byte prefix cursor did not return its matching key")

def main() -> IO(Unit):
  do IO<Unit>:
    first.result(Cursor.next(Cursor.seek.cursor(Cursor.open(entries()),
      Some{packed("0001")}), Cursor.bounds.clone(bounds())))
    upper.stop.result(Cursor.next(Cursor.open(upper.entries()),
      Cursor.bounds.clone(upper.bounds())))
