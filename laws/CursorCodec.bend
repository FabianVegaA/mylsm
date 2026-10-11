import Base
import ../src/coordinator/CursorCodec.bend as CursorCodec
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Extracts exact byte equality from a package comparison.
def bytes.equal(pair: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match pair:
    case (_, _, equal): equal

# Returns the fixture bytes when hexadecimal decoding succeeds.
def bytes.fixture(parsed: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match parsed:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Compares a decoded item to its original binary key and value.
def item.roundtrips(
  expected_key: Bytes.Bytes,
  expected_value: Bytes.Bytes,
  decision: CursorCodec.Decision
) -> Bool:
  match decision:
    case CursorCodec.Decoded{CursorCodec.CursorItem{key, value}}:
      bytes.equal(Bytes.eq(expected_key, key)) &&
        bytes.equal(Bytes.eq(expected_value, value))
    case _: False{}

# Distinguishes a terminal response from all item frames.
law cursor_end_roundtrips:
  {CursorCodec.decode(CursorCodec.encode(CursorCodec.CursorEnd{})) ==
    CursorCodec.Decoded{CursorCodec.CursorEnd{}} : CursorCodec.Decision}

# Preserves arbitrary binary key and value bytes through one cursor frame.
law cursor_item_binary_bytes_roundtrip:
  {item.roundtrips(bytes.fixture(Bytes.from_hex("00ff")),
    bytes.fixture(Bytes.from_hex("807f00")),
    CursorCodec.decode(CursorCodec.encode(CursorCodec.CursorItem{
      bytes.fixture(Bytes.from_hex("00ff")),
      bytes.fixture(Bytes.from_hex("807f00"))}))) == True{} : Bool}

# Keeps an empty key and empty value distinct from the End marker.
law cursor_item_accepts_empty_key_and_value:
  {item.roundtrips(Bytes.new(0), Bytes.new(0),
    CursorCodec.decode(CursorCodec.encode(CursorCodec.CursorItem{
      Bytes.new(0), Bytes.new(0)}))) == True{} : Bool}

# Rejects an item response with trailing bytes after its declared value.
law cursor_item_rejects_trailing_bytes:
  {CursorCodec.decode(Bytes.concat([
    CursorCodec.encode(CursorCodec.CursorItem{Bytes.new(0), Bytes.new(0)}),
    Bytes.new(1)])) == CursorCodec.Malformed{} : CursorCodec.Decision}

# Rejects an incomplete item header before slicing key or value data.
law cursor_item_rejects_truncated_header:
  {CursorCodec.decode(Bytes.concat([CursorCodec.item.tag(), Bytes.new(4)])) ==
    CursorCodec.Malformed{} : CursorCodec.Decision}

# Rejects an unknown response tag rather than treating it as End or Item.
law cursor_rejects_unknown_tag:
  {CursorCodec.decode(bytes.fixture(Bytes.from_hex("0200"))) ==
    CursorCodec.Malformed{} : CursorCodec.Decision}
