import Base
import ./Protocol.bend as Protocol
import ./CursorCodec.bend as CursorCodec
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Reports one owner-issued cursor identifier or a rejected open response.
type OpenDecision is Type:
  Opened{cursor_id: U32}
  OpenRejected{status: Protocol.ResponseStatus}
  OpenMalformed{}

# Reports one decoded cursor frame or a rejected next response.
type NextDecision is Type:
  NextFrame{frame: CursorCodec.Frame}
  NextRejected{status: Protocol.ResponseStatus}
  NextMalformed{}

# Reports whether an owner acknowledged cursor closure with an exact body.
type CloseDecision is Data:
  CloseSucceeded{}
  CloseRejected{status: Protocol.ResponseStatus}
  CloseMalformed{}

# Decodes the owner cursor ID only from a successful exact token payload.
# Converts an exact token parse into a typed cursor-open decision.
def open.parsed(parsed: Maybe<&2, U32>) -> OpenDecision:
  match parsed:
    case Some{cursor_id}: Opened{cursor_id}
    case None{}: OpenMalformed{}

# Decodes a successful owner cursor-open response or preserves its rejection.
def open(status: Protocol.ResponseStatus, payload: Bytes.Bytes) -> OpenDecision:
  match status:
    case Protocol.Success{}:
      open.parsed(Protocol.snapshot.id.read(payload))
    case _: OpenRejected{status}

# Converts one exact cursor frame decode into a typed client decision.
def next.decoded(decision: CursorCodec.Decision) -> NextDecision:
  match decision:
    case CursorCodec.Decoded{frame}: NextFrame{frame}
    case CursorCodec.Malformed{}: NextMalformed{}

# Decodes a raw-byte cursor frame only from a successful owner response.
def next(status: Protocol.ResponseStatus, payload: Bytes.Bytes) -> NextDecision:
  match status:
    case Protocol.Success{}:
      next.decoded(CursorCodec.decode(payload))
    case _: NextRejected{status}

# Accepts one close payload only when its measured length is zero.
def close.measured(measured: Bytes.Bytes & U32) -> CloseDecision:
  match measured:
    case (_, 0): CloseSucceeded{}
    case _: CloseMalformed{}

# Accepts cursor close only when success carries no trailing payload.
def close(status: Protocol.ResponseStatus, payload: Bytes.Bytes) -> CloseDecision:
  match status:
    case Protocol.Success{}:
      close.measured(Bytes.length(payload))
    case _: CloseRejected{status}
