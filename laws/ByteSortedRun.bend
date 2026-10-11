import Base
import ../src/ByteMemTable.bend as ByteMemTable
import ../src/ByteSortedRun.bend as ByteSortedRun
import ../src/Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def fixture.bytes(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

def fixture.memtable() -> List<&1, ByteMemTable.Entry>:
  Con{ByteMemTable.Entry{fixture.bytes(Bytes.from_hex("61")), None{}}, Nil{}}

def fixture.memtable.with.value() -> List<&1, ByteMemTable.Entry>:
  Con{ByteMemTable.Entry{fixture.bytes(Bytes.from_hex("61")),
      Some{fixture.bytes(Bytes.from_hex("fe"))}}, Nil{}}

def fixture.old.run() -> List<&1, ByteMemTable.Entry>:
  Con{ByteMemTable.Entry{fixture.bytes(Bytes.from_hex("61")),
      Some{fixture.bytes(Bytes.from_hex("0102"))}},
    Con{ByteMemTable.Entry{fixture.bytes(Bytes.from_hex("62")),
      Some{fixture.bytes(Bytes.from_hex("80ff"))}}, Nil{}}}

def merge.ordered() -> Bool:
  ByteMemTable.ordered.strict(ByteSortedRun.merge_newest(fixture.memtable(),
    Con{fixture.old.run(), Nil{}}))

def merge.keeps.newest.tombstone.go(entries: List<&1, ByteMemTable.Entry>) -> Bool:
  match entries:
    case Con{ByteMemTable.Entry{key, None{}}, _}:
      Keys.Bytes.eq(key, fixture.bytes(Bytes.from_hex("61")))
    case _:
      False{}

def merge.keeps.newest.tombstone() -> Bool:
  merge.keeps.newest.tombstone.go(ByteSortedRun.merge_newest(
    fixture.memtable(), Con{fixture.old.run(), Nil{}}))

def merge.keeps.newest.value.go(entries: List<&1, ByteMemTable.Entry>) -> Bool:
  match entries:
    case Con{ByteMemTable.Entry{key, Some{value}}, _}:
      Keys.Bytes.eq(key, fixture.bytes(Bytes.from_hex("61"))) &&
        Keys.Bytes.eq(value, fixture.bytes(Bytes.from_hex("fe")))
    case _:
      False{}

def merge.keeps.newest.value() -> Bool:
  merge.keeps.newest.value.go(ByteSortedRun.merge_newest(
    fixture.memtable.with.value(), Con{fixture.old.run(), Nil{}}))

# Merging ordered and unordered sources produces strict byte-key order.
law merged_sources_are_strictly_byte_ordered:
  {merge.ordered() == True{} : Bool}

# A newer tombstone hides an older value while remaining in the merged run.
law newest_memtable_tombstone_wins:
  {merge.keeps.newest.tombstone() == True{} : Bool}

# A newer live value wins over an older value for the same raw key.
law newest_memtable_value_wins:
  {merge.keeps.newest.value() == True{} : Bool}
