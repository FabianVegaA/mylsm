import Base
import ../src/coordinator/CursorOpenCodec.bend as CursorOpenCodec
import ../src/coordinator/Protocol.bend as Protocol
import ../src/scan/RangeCursor.bend as RangeCursor
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Returns decoded fixture bytes or an empty fallback.
def fixture(parsed: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match parsed:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Extracts exact byte equality from the byte package comparison.
def bytes.equal(comparison: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match comparison:
    case (_, (_, equal)): equal

# Compares two optional bounds by exact raw-byte identity.
def bound.equal(pair: Maybe<&1, Bytes.Bytes> & Maybe<&1, Bytes.Bytes>) -> Bool:
  match pair:
    case (None{}, None{}): True{}
    case (Some{expected}, Some{actual}):
      bytes.equal(Bytes.eq(expected, actual))
    case _: False{}

# Compares all three public cursor-bound fields.
def bounds.equal(pair: RangeCursor.Bounds & RangeCursor.Bounds) -> Bool:
  match pair:
    case (RangeCursor.Bounds{lower, upper, prefix},
        RangeCursor.Bounds{lower_copy, upper_copy, prefix_copy}):
      Bool.and(bound.equal((lower, lower_copy)),
        Bool.and(bound.equal((upper, upper_copy)),
          bound.equal((prefix, prefix_copy))))

# Compares a decoded request with its expected owner token and bounds.
def request.matches(
  expected_id: U32,
  expected_bounds: RangeCursor.Bounds,
  decision: CursorOpenCodec.Decision
) -> Bool:
  match decision:
    case CursorOpenCodec.Decoded{CursorOpenCodec.Request{snapshot_id, bounds}}:
      Bool.and(U32.is_eq(expected_id, snapshot_id),
        bounds.equal((expected_bounds, bounds)))
    case CursorOpenCodec.Malformed{}: False{}

# Round-trips an unbounded full-range cursor request.
law cursor_open_full_range_roundtrips:
  {request.matches(7, RangeCursor.Bounds{None{}, None{}, None{}},
    CursorOpenCodec.decode(CursorOpenCodec.encode.range(7, None{}, None{}))) ==
    True{} : Bool}

# Preserves embedded zero and high-bit range keys byte for byte.
law cursor_open_binary_range_roundtrips:
  {request.matches(9, RangeCursor.Bounds{
      Some{fixture(Bytes.from_hex("00ff"))},
      Some{fixture(Bytes.from_hex("807f00"))}, None{}},
    CursorOpenCodec.decode(CursorOpenCodec.encode.range(9,
      Some{fixture(Bytes.from_hex("00ff"))},
      Some{fixture(Bytes.from_hex("807f00"))}))) == True{} : Bool}

# Preserves an empty prefix as a present prefix bound.
law cursor_open_empty_prefix_roundtrips:
  {request.matches(11, RangeCursor.Bounds{None{}, None{}, Some{Bytes.new(0)}},
    CursorOpenCodec.decode(CursorOpenCodec.encode.prefix(11, Bytes.new(0)))) ==
    True{} : Bool}

# Preserves arbitrary raw bytes in a prefix bound.
law cursor_open_binary_prefix_roundtrips:
  {request.matches(13, RangeCursor.Bounds{None{}, None{},
      Some{fixture(Bytes.from_hex("00ff80"))}},
    CursorOpenCodec.decode(CursorOpenCodec.encode.prefix(13,
      fixture(Bytes.from_hex("00ff80"))))) == True{} : Bool}

# Rejects a cursor-open payload with a truncated owner token.
law cursor_open_rejects_short_snapshot_token:
  {CursorOpenCodec.decode(Bytes.new(3)) == CursorOpenCodec.Malformed{} :
    CursorOpenCodec.Decision}

# Rejects a range bound whose declared bytes exceed the request frame.
law cursor_open_rejects_truncated_range_bound:
  {CursorOpenCodec.decode(Bytes.concat([Protocol.u32.bytes(7),
    Protocol.u32.bytes(0), Protocol.u32.bytes(2), Bytes.new(1)])) ==
    CursorOpenCodec.Malformed{} : CursorOpenCodec.Decision}

# Rejects trailing bytes after otherwise complete range fields.
law cursor_open_rejects_range_trailing_bytes:
  {CursorOpenCodec.decode(Bytes.concat([
    CursorOpenCodec.encode.range(7, None{}, None{}), Bytes.new(1)])) ==
    CursorOpenCodec.Malformed{} : CursorOpenCodec.Decision}

# Rejects unknown cursor-open modes before reading bound fields.
law cursor_open_rejects_unknown_mode:
  {CursorOpenCodec.decode(Bytes.concat([Protocol.u32.bytes(7),
    Protocol.u32.bytes(2), CursorOpenCodec.bound.absent()])) ==
    CursorOpenCodec.Malformed{} : CursorOpenCodec.Decision}
