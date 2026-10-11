import Base
import ../src/ByteMemTable.bend as ByteMemTable
import ../src/Keys.bend as Keys
import ../src/transfer/Migrate.bend as Migrate
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def fixture.bytes(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def fixture.source() -> ByteMemTable.Table:
  ByteMemTable.del(
    ByteMemTable.put(
      ByteMemTable.put(ByteMemTable.empty(),
        fixture.bytes(Bytes.from_hex("80ff")),
        fixture.bytes(Bytes.from_hex("00fe"))),
      fixture.bytes(Bytes.from_hex("ff00")),
      fixture.bytes(Bytes.from_hex("aabb"))),
    fixture.bytes(Bytes.from_hex("80ff")))

def fixture.canonical() -> List<&1, ByteMemTable.Entry>:
  Migrate.canonical.entries(fixture.source())

def fixture.only.live.entry(entries: List<&1, ByteMemTable.Entry>) -> Bool:
  match entries:
    case Con{ByteMemTable.Entry{key, Some{value}}, Nil{}}:
      Keys.Bytes.eq(key, fixture.bytes(Bytes.from_hex("ff00"))) &&
        Keys.Bytes.eq(value, fixture.bytes(Bytes.from_hex("aabb")))
    case _: False{}

# Canonical migration output sorts arbitrary raw keys in strict byte order.
law migration_canonical_output_is_strictly_byte_ordered:
  {ByteMemTable.ordered.strict(fixture.canonical()) == True{} : Bool}

# A newest tombstone hides its older value and is absent from exported data.
law migration_canonical_output_drops_shadowed_tombstones:
  {List.length(&1, ByteMemTable.Entry, fixture.canonical()) == 1n : Nat}

# The newest live mutation remains visible after canonicalization.
law migration_canonical_output_retains_newest_live_values:
  {fixture.only.live.entry(fixture.canonical()) == True{} : Bool}
