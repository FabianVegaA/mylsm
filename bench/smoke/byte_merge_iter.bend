import Base
import ../../src/ByteMemTable.bend as ByteMemTable
import ../../src/ByteSortedRun.bend as ByteSortedRun
import ../../src/Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Unwraps the binary fixture vectors.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

def merged.matches(entries: List<&1, ByteMemTable.Entry>) -> Bool:
  match entries:
    case Con{ByteMemTable.Entry{first, None{}},
        Con{ByteMemTable.Entry{second, Some{value}}, Nil{}}}:
      Cmp.is_eq(Keys.Bytes.cmp(first, packed(Bytes.from_hex("61")))) &&
        Cmp.is_eq(Keys.Bytes.cmp(second, packed(Bytes.from_hex("62")))) &&
        Cmp.is_eq(Keys.Bytes.cmp(value, packed(Bytes.from_hex("80ff"))))
    case _:
      False{}

# Fails the smoke on the first merge-contract mismatch.
def checked(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.print("byte merge newest-wins passed")
    case False{}:
      IO.die(Unit, 1, "byte merge lost ordering, tombstone, or newest value")

def main() -> IO(Unit):
  mem : List<&1, ByteMemTable.Entry> = Con{
    ByteMemTable.Entry{packed(Bytes.from_hex("61")), None{}}, Nil{}}
  old_run : List<&1, ByteMemTable.Entry> = Con{ByteMemTable.Entry{packed(Bytes.from_hex("61")),
      Some{packed(Bytes.from_hex("0102"))}},
    Con{ByteMemTable.Entry{packed(Bytes.from_hex("62")),
      Some{packed(Bytes.from_hex("80ff"))}}, Nil{}}}
  checked(merged.matches(ByteSortedRun.merge_newest(mem, Con{old_run, Nil{}})))
