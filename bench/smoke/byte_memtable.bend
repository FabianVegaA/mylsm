import Base
import ../../src/Keys.bend as Keys
import ../../src/ByteMemTable.bend as ByteMemTable
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Fails the fixture immediately when a storage contract is violated.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, message)

# Converts a hex-decoding result to an owned byte buffer.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Compares the returned value with the expected raw byte sequence.
def found_value(value: Maybe<&1, Bytes.Bytes>, expected: Bytes.Bytes) -> Bool:
  match value:
    case Some{bytes}:
      Cmp.is_eq(Keys.Bytes.cmp(bytes, expected))
    case None{}:
      False{}

# Recognizes an absent or tombstoned key result.
def is_missing(value: Maybe<&1, Bytes.Bytes>) -> Bool:
  match value:
    case None{}:
      True{}
    case Some{_}:
      False{}

def probe.deleted.checked(pair: ByteMemTable.Table & ByteMemTable.Probe) -> IO(ByteMemTable.Table):
  match pair:
    case (table, ByteMemTable.Deleted{}):
      do IO<ByteMemTable.Table>:
        require(True{}, "delta probe must identify a tombstone")
        return table
    case (table, _):
      do IO<ByteMemTable.Table>:
        require(False{}, "delta probe must distinguish a tombstone from an absent mutation")
        return table

def probe.absent.checked(pair: ByteMemTable.Table & ByteMemTable.Probe) -> IO(Unit):
  match pair:
    case (_, ByteMemTable.Absent{}):
      require(True{}, "delta probe must identify an absent mutation")
    case (_, _):
      require(False{}, "delta probe must identify keys with no mutation")

# Recognizes a present value whose encoded length is zero.
def is_empty(value: Maybe<&1, Bytes.Bytes>) -> Bool:
  match value:
    case Some{Bytes.Bytes{len, _}}:
      U32.is_eq(len, 0)
    case None{}:
      False{}

# Compares one ordered key with its fixed binary vector.
def key.is(key: Bytes.Bytes, expected: Bytes.Bytes) -> Bool:
  Cmp.is_eq(Keys.Bytes.cmp(key, expected))

# Checks a value while returning the table for the next operation.
def check_value(
  pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>,
  expected: Bytes.Bytes
) -> IO(ByteMemTable.Table):
  match pair:
    case (table, value):
      do IO<ByteMemTable.Table>:
        require(found_value(value, expected), "binary MemTable must preserve bytes and newest value")
        return table

# Checks that an empty value remains a present result.
def check_empty(pair: ByteMemTable.Table & Maybe<&1, Bytes.Bytes>) -> IO(ByteMemTable.Table):
  match pair:
    case (table, value):
      do IO<ByteMemTable.Table>:
        require(is_empty(value), "an empty byte value must remain distinct from a missing key")
        return table

# Verifies canonical byte order after newest-first mutations are collapsed.
def ordered.keys.match(entries: List<&1, ByteMemTable.Entry>) -> Bool:
  match entries:
    case Con{ByteMemTable.Entry{empty, _},
        Con{ByteMemTable.Entry{zero, _},
          Con{ByteMemTable.Entry{prefix, _},
            Con{ByteMemTable.Entry{extended, _},
              Con{ByteMemTable.Entry{tombstoned, missing},
                Con{ByteMemTable.Entry{high, _}, Nil{}}}}}}}:
      key.is(empty, packed(Bytes.from_hex(""))) &&
        key.is(zero, packed(Bytes.from_hex("00"))) &&
        key.is(prefix, packed(Bytes.from_hex("61"))) &&
        key.is(extended, packed(Bytes.from_hex("6100"))) &&
        key.is(tombstoned, packed(Bytes.from_hex("610062"))) &&
        key.is(high, packed(Bytes.from_hex("80"))) && is_missing(missing)
    case _:
      False{}

# Checks the canonical visible entry order of a byte table.
def ordered_keys(table: ByteMemTable.Table) -> Bool:
  ordered.keys.match(ByteMemTable.ordered_entries(table))

def main() -> IO(Unit):
  do IO<Unit>:
    table : ByteMemTable.Table <- IO.pure(ByteMemTable.Table, ByteMemTable.put(ByteMemTable.empty(),
      packed(Bytes.from_hex("610062")), packed(Bytes.from_hex("80ff00"))))
    updated : ByteMemTable.Table <- IO.pure(ByteMemTable.Table, ByteMemTable.put(table,
      packed(Bytes.from_hex("610062")), packed(Bytes.from_hex("00ff80"))))
    updated : ByteMemTable.Table <- check_value(ByteMemTable.get(updated,
      packed(Bytes.from_hex("610062"))), packed(Bytes.from_hex("00ff80")))
    updated : ByteMemTable.Table <- IO.pure(ByteMemTable.Table,
      ByteMemTable.put(updated, packed(Bytes.from_hex("empty-value-key")), packed(Bytes.from_hex(""))))
    updated : ByteMemTable.Table <- check_empty(ByteMemTable.get(updated,
      packed(Bytes.from_hex("empty-value-key"))))
    deleted : ByteMemTable.Table <- IO.pure(ByteMemTable.Table,
      ByteMemTable.del(updated, packed(Bytes.from_hex("610062"))))
    deleted : ByteMemTable.Table <- probe.deleted.checked(ByteMemTable.probe(deleted,
      packed(Bytes.from_hex("610062"))))
    probe.absent.checked(ByteMemTable.probe(deleted,
      packed(Bytes.from_hex("ab5e17"))))
    ordered : ByteMemTable.Table <- IO.pure(ByteMemTable.Table,
      ByteMemTable.del(ByteMemTable.put(ByteMemTable.put(ByteMemTable.put(
        ByteMemTable.put(ByteMemTable.put(ByteMemTable.put(ByteMemTable.empty(),
        packed(Bytes.from_hex("80")), packed(Bytes.from_hex("01"))),
        packed(Bytes.from_hex("610062")), packed(Bytes.from_hex("02"))),
        packed(Bytes.from_hex("6100")), packed(Bytes.from_hex("03"))),
        packed(Bytes.from_hex("61")), packed(Bytes.from_hex("04"))),
        packed(Bytes.from_hex("00")), packed(Bytes.from_hex("05"))),
        packed(Bytes.from_hex("")), packed(Bytes.from_hex("06"))),
        packed(Bytes.from_hex("610062"))))
    require(ordered_keys(ordered), "binary table must sort empty, prefix, and unsigned keys")
    IO.print("binary MemTable smoke passed")
