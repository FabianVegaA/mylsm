import Base
import ../src/ByteMemTable.bend as ByteMemTable
import ../src/Keys.bend as Keys
import ../src/MemTable.bend as MemTable
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

def fixture.utf8.conversion() -> Result<&1, &1, U32 & String, ByteMemTable.Table>:
  Migrate.legacy.apply.chronological(Con{
    MemTable.Entry{"á", Some{"ñ"}}, Nil{}}, ByteMemTable.empty())

def fixture.utf8.visible(value: Maybe<&1, Bytes.Bytes>) -> Bool:
  match value:
    case None{}: False{}
    case Some{bytes}: Keys.Bytes.eq(bytes, fixture.bytes(Bytes.from_hex("c3b1")))

def fixture.utf8.lookup(pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>) -> Bool:
  match pair:
    case (_, value): fixture.utf8.visible(value)

def fixture.utf8.exact(result: Result<&1, &1, U32 & String, ByteMemTable.Table>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{table}:
      fixture.utf8.lookup(ByteMemTable.get(table,
        fixture.bytes(Bytes.from_hex("c3a1"))))

def fixture.chronological.result() -> Result<&1, &1, U32 & String, ByteMemTable.Table>:
  Migrate.legacy.apply.chronological(Con{
    MemTable.Entry{"key", Some{"old"}},
    Con{MemTable.Entry{"key", Some{"new"}}, Nil{}}}, ByteMemTable.empty())

def fixture.chronological.visible(value: Maybe<&1, Bytes.Bytes>) -> Bool:
  match value:
    case None{}: False{}
    case Some{bytes}: Keys.Bytes.eq(bytes, fixture.bytes(Bytes.from_hex("6e6577")))

def fixture.chronological.lookup(pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>) -> Bool:
  match pair:
    case (_, value): fixture.chronological.visible(value)

def fixture.chronological.newest(
  result: Result<&1, &1, U32 & String, ByteMemTable.Table>
) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{table}:
      fixture.chronological.lookup(ByteMemTable.get(table,
        fixture.bytes(Bytes.from_hex("6b6579"))))

# Canonical migration output sorts arbitrary raw keys in strict byte order.
law migration_canonical_output_is_strictly_byte_ordered:
  {ByteMemTable.ordered.strict(fixture.canonical()) == True{} : Bool}

# A newest tombstone hides its older value and is absent from exported data.
law migration_canonical_output_drops_shadowed_tombstones:
  {List.length(&1, ByteMemTable.Entry, fixture.canonical()) == 1n : Nat}

# The newest live mutation remains visible after canonicalization.
law migration_canonical_output_retains_newest_live_values:
  {fixture.only.live.entry(fixture.canonical()) == True{} : Bool}

# Legacy text becomes the identical RFC 3629 UTF-8 byte sequence.
law migration_converts_legacy_unicode_to_exact_utf8_bytes:
  {fixture.utf8.exact(fixture.utf8.conversion()) == True{} : Bool}

# Later durable mutations replace earlier values for the same key.
law migration_applies_legacy_mutations_chronologically:
  {fixture.chronological.newest(fixture.chronological.result()) == True{} : Bool}
