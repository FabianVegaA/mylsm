import Base
import ../src/scan/ByteRange.bend as ByteRange
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Unwraps valid hex literals used by the closed byte vectors.
def bytes.fixture(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}:
      bytes
    case None{}:
      Bytes.new(0)

# A raw key matches a prefix containing embedded zero bytes.
law raw_prefix_with_zero_matches:
  {ByteRange.has_prefix(bytes.fixture(Bytes.from_hex("610062")), bytes.fixture(Bytes.from_hex("6100"))) == True{} : Bool}

# Empty prefixes include every key, including the empty key.
law empty_prefix_matches_empty_key:
  {ByteRange.has_prefix(Bytes.new(0), Bytes.new(0)) == True{} : Bool}

# Range upper bounds are exclusive under byte order.
law range_upper_bound_is_exclusive:
  {ByteRange.in_range(bytes.fixture(Bytes.from_hex("63")), Some{bytes.fixture(Bytes.from_hex("61"))}, Some{bytes.fixture(Bytes.from_hex("63"))}) == False{} : Bool}

# Equal half-open bounds describe the empty range.
law equal_range_bounds_exclude_the_bound:
  {ByteRange.in_range(bytes.fixture(Bytes.from_hex("62")), Some{bytes.fixture(Bytes.from_hex("62"))}, Some{bytes.fixture(Bytes.from_hex("62"))}) == False{} : Bool}

# An open lower bound admits the smallest key below the upper bound.
law open_lower_bound_admits_key:
  {ByteRange.in_range(Bytes.new(0), None{}, Some{bytes.fixture(Bytes.from_hex("00"))}) == True{} : Bool}

# An open upper bound admits a key after the inclusive lower bound.
law open_upper_bound_admits_key:
  {ByteRange.in_range(bytes.fixture(Bytes.from_hex("62")), Some{bytes.fixture(Bytes.from_hex("62"))}, None{}) == True{} : Bool}

# A sorted scan can terminate once a key reaches its exclusive upper bound.
law scan_reaches_equal_upper_bound:
  {ByteRange.at_or_after_upper(bytes.fixture(Bytes.from_hex("63")), Some{bytes.fixture(Bytes.from_hex("63"))}) == True{} : Bool}

# A sorted scan can terminate after passing its exclusive upper bound.
law scan_passes_upper_bound:
  {ByteRange.at_or_after_upper(bytes.fixture(Bytes.from_hex("64")), Some{bytes.fixture(Bytes.from_hex("63"))}) == True{} : Bool}

# Keys before the upper bound remain eligible for range filtering.
law scan_before_upper_bound:
  {ByteRange.at_or_after_upper(bytes.fixture(Bytes.from_hex("62")), Some{bytes.fixture(Bytes.from_hex("63"))}) == False{} : Bool}
