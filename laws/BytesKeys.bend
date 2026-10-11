import Base
import ../src/Keys.bend as Keys
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Supplies an empty buffer if the vector parser rejects its literal.
def packed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# Returns the zero-length key used by the ordering laws.
def empty_key() -> Bytes.Bytes:
  packed(Bytes.from_hex(""))

# Returns a one-byte zero key.
def zero_key() -> Bytes.Bytes:
  packed(Bytes.from_hex("00"))

# Returns a zero key extended by one byte.
def zero_extension() -> Bytes.Bytes:
  packed(Bytes.from_hex("0000"))

# Returns the highest ASCII-range byte.
def seven_f_key() -> Bytes.Bytes:
  packed(Bytes.from_hex("7f"))

# Returns the first byte above the ASCII range.
def eight_zero_key() -> Bytes.Bytes:
  packed(Bytes.from_hex("80"))

# Empty byte strings precede every nonempty key.
law empty_before_zero:
  {Keys.Bytes.cmp(empty_key(), zero_key()) == LT{} : Cmp}

# A byte prefix precedes any strict extension.
law prefix_before_extension:
  {Keys.Bytes.cmp(zero_key(), zero_extension()) == LT{} : Cmp}

# Byte comparison is unsigned across the sign boundary.
law unsigned_byte_order:
  {Keys.Bytes.cmp(seven_f_key(), eight_zero_key()) == LT{} : Cmp}

# Equal byte vectors project to true under the comparator.
law equal_vector_is_equal:
  {Keys.Bytes.eq(zero_key(), zero_key()) == True{} : Bool}
