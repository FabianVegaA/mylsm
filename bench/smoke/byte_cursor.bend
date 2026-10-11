import Base
import ../../src/scan/Cursor.bend as Cursor
import ../../src/ByteMemTable.bend as ByteMemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def packed.parsed(result: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match result:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Decodes a fixed hexadecimal value used by the cursor fixture.
def packed(hex: String) -> Bytes.Bytes:
  packed.parsed(Bytes.from_hex(hex))

def terminal.result(step: Cursor.Step) -> IO(Unit):
  match step:
    case Cursor.CursorEnd{_}: IO.print("BYTE_CURSOR_INCREMENTAL")
    case _ : IO.die(Unit, 1, "byte cursor did not reach end")

def second.result(step: Cursor.Step) -> IO(Unit):
  match step:
    case Cursor.CursorItem{ByteMemTable.Entry{_, Some{_}}, cursor}:
      terminal.result(Cursor.next(cursor))
    case _:
      IO.die(Unit, 1, "byte cursor did not advance incrementally")

def first.result(step: Cursor.Step) -> IO(Unit):
  match step:
    case Cursor.CursorItem{ByteMemTable.Entry{_, Some{_}}, cursor}:
      second.result(Cursor.next(cursor))
    case _:
      IO.die(Unit, 1, "byte cursor did not yield its first entry")

# Builds two ordered entries that expose cursor advancement.
def entries() -> List<&1, ByteMemTable.Entry>:
  Con{
    ByteMemTable.Entry{packed("00"), Some{packed("80ff")}},
    Con{ByteMemTable.Entry{packed("ff"), Some{packed("610062")}}, Nil{}}
  }

def main() -> IO(Unit):
  first.result(Cursor.next(Cursor.open(entries())))
