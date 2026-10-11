import Base
import ../../src/coordinator/Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the protocol fixture at the first failed frame contract.
def require(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, message)

# Checks that one frame is rejected as malformed.
def malformed(decision: Protocol.FrameDecision) -> Bool:
  match decision:
    case Protocol.Malformed{}: True{}
    case _: False{}

# Checks that one request is rejected by the payload limit.
def too_large(decision: Protocol.FrameDecision) -> Bool:
  match decision:
    case Protocol.FrameTooLarge{}: True{}
    case _: False{}

# Checks that the decoder requests additional input bytes.
def needs_more(decision: Protocol.FrameDecision) -> Bool:
  match decision:
    case Protocol.NeedMore{}: True{}
    case _: False{}

# Recognizes unsupported operation tags rejected during frame decoding.
def unknown_operation(decision: Protocol.FrameDecision) -> Bool:
  match decision:
    case Protocol.UnknownOperation{}: True{}
    case _: False{}

# Recognizes a well-framed request rejected for its protocol version.
def invalid_version(decision: Protocol.Decision) -> Bool:
  match decision:
    case Protocol.VersionMismatch{}: True{}
    case _: False{}

def decoded.validation(decision: Protocol.FrameDecision) -> Protocol.Decision:
  match decision:
    case Protocol.Decoded{request}:
      Protocol.validate(request, 1, 9, 16n)
    case _: Protocol.ResourceLimit{}

# Verifies that a declared but incomplete payload remains resumable.
def truncated.check(sliced: Bytes.Bytes & Bytes.Bytes) -> IO(Unit):
  match sliced:
    case (_, prefix):
      require(needs_more(Protocol.decode(prefix, 16n)),
        "incomplete payloads must request more bytes")

def response.timeout(decision: Protocol.ResponseDecision) -> Bool:
  match decision:
    case Protocol.DecodedResponse{Protocol.Response{_, _, 44,
        Protocol.Timeout{}, _}}: True{}
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    empty_request : Protocol.Request = Protocol.Request{1, 9, 33, 2, Bytes.new(0)}
    large_request : Protocol.Request = Protocol.Request{1, 9, 34, 2, Bytes.new(17)}
    encoded : Bytes.Bytes = Protocol.encode(empty_request)
    truncated : Bytes.Bytes & Bytes.Bytes = Bytes.slice(
      Protocol.encode(Protocol.Request{1, 9, 35, 2, Bytes.new(1)}), 0, 24)
    require(needs_more(Protocol.decode(Bytes.new(19), 16n)),
      "incomplete headers must request more bytes")
    require(too_large(Protocol.decode(Protocol.encode(large_request), 16n)),
      "oversized requests must be rejected before dispatch")
    require(unknown_operation(Protocol.decode(
      Bytes.set.u32be(Protocol.encode(Protocol.Request{1, 9, 33, 2,
        Bytes.new(0)}), 16, 9), 16n)),
      "unknown operation tags must be rejected before dispatch")
    require(invalid_version(decoded.validation(Protocol.decode(
      Bytes.set.u32be(Protocol.encode(Protocol.Request{1, 9, 33, 2,
        Bytes.new(0)}), 4, 2), 16n))),
      "unknown protocol versions must be rejected before dispatch")
    require(malformed(Protocol.decode(Bytes.concat([encoded, Bytes.new(1)]), 16n)),
      "trailing bytes must reject the frame")
    _checked : Unit <- truncated.check(truncated)
    require(response.timeout(Protocol.decode_response(Protocol.encode_response(
      Protocol.Response{1, 9, 44, Protocol.Timeout{}, Bytes.new(2)}), 16n)),
      "response status and correlation id must survive the round trip")
    IO.print("COORDINATOR_PROTOCOL_FRAME_PASSED")
