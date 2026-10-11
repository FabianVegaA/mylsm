import Base
import ../src/coordinator/OwnerCursorCodec.bend as Codec
import ../src/coordinator/CursorCodec.bend as CursorCodec
import ../src/coordinator/Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Returns decoded binary fixture bytes or an empty fallback.
def fixture(parsed: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match parsed:
    case Some{value}: value
    case None{}: Bytes.new(0)

# Accepts a successful owner cursor token.
law cursor_open_decodes_owner_token:
  {Codec.open(Protocol.Success{}, Protocol.snapshot.id.bytes(9)) ==
    Codec.Opened{9} : Codec.OpenDecision}

# Rejects a truncated successful owner cursor token.
law cursor_open_rejects_malformed_token:
  {Codec.open(Protocol.Success{}, Bytes.new(3)) ==
    Codec.OpenMalformed{} : Codec.OpenDecision}

# Preserves raw bytes in a successful owner cursor frame.
law cursor_next_preserves_binary_item:
  {Codec.next(Protocol.Success{}, CursorCodec.encode(CursorCodec.CursorItem{
    fixture(Bytes.from_hex("00ff")), fixture(Bytes.from_hex("807f00"))})) ==
    Codec.NextFrame{CursorCodec.CursorItem{
      fixture(Bytes.from_hex("00ff")), fixture(Bytes.from_hex("807f00"))}} :
      Codec.NextDecision}

# Rejects malformed cursor frames before exposing an item.
law cursor_next_rejects_malformed_frame:
  {Codec.next(Protocol.Success{}, Bytes.new(0)) ==
    Codec.NextMalformed{} : Codec.NextDecision}

# Accepts an exact empty successful close response.
law cursor_close_accepts_empty_success:
  {Codec.close(Protocol.Success{}, Bytes.new(0)) ==
    Codec.CloseSucceeded{} : Codec.CloseDecision}

# Rejects a successful close response with unexpected trailing data.
law cursor_close_rejects_trailing_data:
  {Codec.close(Protocol.Success{}, Bytes.new(1)) ==
    Codec.CloseMalformed{} : Codec.CloseDecision}

# Preserves an owner rejection status for typed client error mapping.
law cursor_close_preserves_rejection:
  {Codec.close(Protocol.Busy{}, Bytes.new(0)) ==
    Codec.CloseRejected{Protocol.Busy{}} : Codec.CloseDecision}
