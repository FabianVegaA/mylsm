import Base
import ../src/scan/RangeCursor.bend as RangeCursor
import ../src/scan/VisibleSeekPolicy.bend as VisibleSeekPolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def bytes.fixture(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Replaces the prior inclusive lower key without changing the upper or prefix.
law seek_replaces_only_the_inclusive_lower_bound:
  {VisibleSeekPolicy.seek.bounds(
    RangeCursor.Bounds{Some{bytes.fixture(Bytes.from_hex("00"))},
      Some{bytes.fixture(Bytes.from_hex("ff"))},
      Some{bytes.fixture(Bytes.from_hex("61"))}},
    Some{bytes.fixture(Bytes.from_hex("80"))}) ==
    RangeCursor.Bounds{Some{bytes.fixture(Bytes.from_hex("80"))},
      Some{bytes.fixture(Bytes.from_hex("ff"))},
      Some{bytes.fixture(Bytes.from_hex("61"))}} :
    RangeCursor.Bounds}

# Preserves an absent upper bound and prefix while setting a lower key.
law seek_preserves_unbounded_range_and_prefix:
  {VisibleSeekPolicy.seek.bounds(
    RangeCursor.Bounds{None{}, None{},
      Some{bytes.fixture(Bytes.from_hex("62"))}},
    Some{bytes.fixture(Bytes.from_hex("6262"))}) ==
    RangeCursor.Bounds{Some{bytes.fixture(Bytes.from_hex("6262"))}, None{},
      Some{bytes.fixture(Bytes.from_hex("62"))}} : RangeCursor.Bounds}
