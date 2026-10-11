import Base
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Returns the maximum encoded request or response payload in bytes.
def max_payload_bytes() -> Nat:
  1073741824n

# Admits a wire payload only when it fits the shared protocol ceiling.
def payload.admitted(length: U32) -> Bool:
  U32.is_le(length, 1073741824)

# Carries one decoded request with its protocol and owner generation.
type Request is Type:
  Request{version: U32, generation: U32, request_id: U32, operation: U32,
    payload: Bytes.Bytes}

# Reports whether a request passes the pure protocol admission checks.
type Decision is Type:
  Accepted{request_id: U32, operation: U32, payload: Bytes.Bytes}
  VersionMismatch{}
  StaleGeneration{}
  UnsupportedRequestOperation{}
  ResourceLimit{}

# Separates incomplete, malformed, oversized, unsupported, and decoded frames.
type FrameDecision is Type:
  NeedMore{}
  Malformed{}
  UnknownOperation{}
  FrameTooLarge{}
  Decoded{request: Request}

# Defines response outcomes carried independently from operation payloads.
type ResponseStatus is Data:
  Success{}
  InvalidArgument{}
  NotFound{}
  Busy{}
  Timeout{}
  ResponseResourceLimit{}
  Corruption{}
  IoFailure{}
  CommitUnknown{}
  AlreadyExists{}
  UnsupportedPlatform{}
  InvalidUtf8{}
  UnsupportedFormat{}

# Carries one correlated outcome and an optional raw detail payload.
type Response is Type:
  Response{version: U32, generation: U32, request_id: U32,
    status: ResponseStatus, payload: Bytes.Bytes}

# Reports incremental framing and typed response-decoding outcomes.
type ResponseDecision is Type:
  ResponseNeedMore{}
  MalformedResponse{}
  ResponseTooLarge{}
  UnexpectedResponse{}
  UnknownResponseStatus{}
  DecodedResponse{response: Response}

# Maps a numeric response code to a supported public status.
type ResponseStatusDecision is Data:
  ValidResponseStatus{status: ResponseStatus}
  InvalidResponseStatus{}

def u32.bytes(value: U32) -> Bytes.Bytes:
  Bytes.set.u32be(Bytes.new(4), 0, value)

def magic.from_hex(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Returns the fixed identifier for versioned coordinator request frames.
def magic() -> Bytes.Bytes:
  magic.from_hex(Bytes.from_hex("4d4c5336"))

def encode.fields(
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  measured: Bytes.Bytes & U32
) -> Bytes.Bytes:
  match measured:
    case (payload, +length):
      Bytes.concat([magic(), u32.bytes(version), u32.bytes(generation),
        u32.bytes(request_id), u32.bytes(operation), u32.bytes(length), payload])

# Encodes one request with an exact payload length and operation tag.
def encode(request: Request) -> Bytes.Bytes:
  match request:
    case Request{+version, +generation, +request_id, +operation, payload}:
      encode.fields(version, generation, request_id, operation,
        Bytes.length(payload))

def response.status.code(status: ResponseStatus) -> U32:
  match status:
    case Success{}: 0
    case InvalidArgument{}: 1
    case NotFound{}: 2
    case Busy{}: 3
    case Timeout{}: 4
    case ResponseResourceLimit{}: 5
    case Corruption{}: 6
    case IoFailure{}: 7
    case CommitUnknown{}: 8
    case AlreadyExists{}: 9
    case UnsupportedPlatform{}: 10
    case InvalidUtf8{}: 11
    case UnsupportedFormat{}: 12

def response.status.decode(code: U32) -> ResponseStatusDecision:
  match code:
    case 0: ValidResponseStatus{Success{}}
    case 1: ValidResponseStatus{InvalidArgument{}}
    case 2: ValidResponseStatus{NotFound{}}
    case 3: ValidResponseStatus{Busy{}}
    case 4: ValidResponseStatus{Timeout{}}
    case 5: ValidResponseStatus{ResponseResourceLimit{}}
    case 6: ValidResponseStatus{Corruption{}}
    case 7: ValidResponseStatus{IoFailure{}}
    case 8: ValidResponseStatus{CommitUnknown{}}
    case 9: ValidResponseStatus{AlreadyExists{}}
    case 10: ValidResponseStatus{UnsupportedPlatform{}}
    case 11: ValidResponseStatus{InvalidUtf8{}}
    case 12: ValidResponseStatus{UnsupportedFormat{}}
    case _: InvalidResponseStatus{}

# Encodes a typed response status before its raw detail bytes.
def encode_response(response: Response) -> Bytes.Bytes:
  match response:
    case Response{+version, +generation, +request_id, status, payload}:
      encode.fields(version, generation, request_id, 7,
        Bytes.length(Bytes.concat([u32.bytes(response.status.code(status)), payload])))

def decode.complete.payload(
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  sliced: Bytes.Bytes & Bytes.Bytes
) -> FrameDecision:
  match sliced:
    case (_, payload):
      Decoded{Request{version, generation, request_id, operation, payload}}

def decode.complete(
  input: Bytes.Bytes,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  +payload_length: U32,
  exact: Bool
) -> FrameDecision:
  match exact:
    case False{}: Malformed{}
    case True{}:
      decode.complete.payload(version, generation, request_id,
        operation, Bytes.slice(input, 24, payload_length))

def decode.complete.classified(
  input: Bytes.Bytes,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  +payload_length: U32,
  exact: Bool,
  short: Bool
) -> FrameDecision:
  match short:
    case True{}: NeedMore{}
    case False{}:
      decode.complete(input, version, generation, request_id, operation,
        payload_length, exact)

def decode.sized(
  input: Bytes.Bytes,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  +payload_length: U32,
  exact: Bool,
  short: Bool,
  within_limit: Bool
) -> FrameDecision:
  match within_limit:
    case False{}: FrameTooLarge{}
    case True{}:
      decode.complete.classified(input, version, generation, request_id,
        operation, payload_length, exact, short)

def nat.duplicate.pair.step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (left, right): (Nat.add(1n, left), Nat.add(1n, right))

def nat.duplicate.pair(value: Nat) -> Nat & Nat:
  match value:
    case 0n: (0n, 0n)
    case 1n+rest: nat.duplicate.pair.step(nat.duplicate.pair(rest))

def nat.duplicate.triple.step(pair: Nat & Nat & Nat) -> Nat & Nat & Nat:
  match pair:
    case (first, second, third):
      (Nat.add(1n, first), Nat.add(1n, second), Nat.add(1n, third))

def nat.duplicate.triple(value: Nat) -> Nat & Nat & Nat:
  match value:
    case 0n: (0n, 0n, 0n)
    case 1n+rest: nat.duplicate.triple.step(nat.duplicate.triple(rest))

def u32.duplicate.triple.result(pair: Nat & Nat & Nat) -> U32 & U32 & U32:
  match pair:
    case (first, second, third):
      (U32.from_nat(first), U32.from_nat(second), U32.from_nat(third))

def u32.duplicate.triple(value: U32) -> U32 & U32 & U32:
  u32.duplicate.triple.result(nat.duplicate.triple(U32.to_nat(value)))

def decode.words.payload_length.size.copies(
  input: Bytes.Bytes,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  +payload_length: U32,
  exact_expected: Nat,
  short_expected: Nat,
  within_limit: Bool,
  sizes: Nat & Nat
) -> FrameDecision:
  match sizes:
    case (exact_size, short_size):
      decode.sized(input, version, generation, request_id, operation,
        payload_length,
        Nat.is_eq(exact_size, exact_expected),
        Nat.is_lt(short_size, short_expected), within_limit)

def decode.words.payload_length.expected.copies(
  input: Bytes.Bytes,
  +size: U32,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  +payload_length: U32,
  expected: Nat & Nat,
  within_limit: Bool
) -> FrameDecision:
  match expected:
    case (exact_expected, short_expected):
      decode.words.payload_length.size.copies(input, version,
        generation, request_id, operation, payload_length, exact_expected, short_expected,
        within_limit, nat.duplicate.pair(U32.to_nat(size)))

def decode.words.payload_length.expected(
  input: Bytes.Bytes,
  +size: U32,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  +payload_length: U32,
  expected: Nat,
  within_limit: Bool
) -> FrameDecision:
  decode.words.payload_length.expected.copies(input, size, version,
    generation, request_id, operation, payload_length, nat.duplicate.pair(expected),
    within_limit)

def decode.words.payload_length.copies(
  input: Bytes.Bytes,
  +size: U32,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  copies: U32 & U32 & U32,
  max_payload_bytes: Nat
) -> FrameDecision:
  match copies:
    case (frame_length, exact_length, bounded_length):
      decode.words.payload_length.expected(input, size, version, generation,
        request_id, operation, frame_length, Nat.add(24n, U32.to_nat(exact_length)),
        U32.is_le(bounded_length, U32.from_nat(max_payload_bytes)))

def decode.words.payload_length(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +size: U32,
  max_payload_bytes: Nat,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32
) -> FrameDecision:
  match pair:
    case (input, Some{payload_length}):
      decode.words.payload_length.copies(input, size, version, generation,
        request_id, operation, u32.duplicate.triple(payload_length),
        max_payload_bytes)
    case _: Malformed{}

def operation.valid(code: U32) -> Bool:
  match code:
    case 1: True{}
    case 2: True{}
    case 3: True{}
    case 4: True{}
    case 5: True{}
    case 6: True{}
    case 7: True{}
    case _: False{}

def operation.request.valid(code: U32) -> Bool:
  match code:
    case 1: True{}
    case 2: True{}
    case 3: True{}
    case 4: True{}
    case 5: True{}
    case 6: True{}
    case _: False{}

def decode.words.operation.validated(
  input: Bytes.Bytes,
  +size: U32,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  valid: Bool,
  max_payload_bytes: Nat
) -> FrameDecision:
  match valid:
    case False{}: UnknownOperation{}
    case True{}:
      decode.words.payload_length(Bytes.get.u32be(input, 20), size,
        max_payload_bytes, version, generation, request_id, operation)

def decode.words.operation.checked(
  input: Bytes.Bytes,
  +size: U32,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  codes: U32 & U32 & U32,
  max_payload_bytes: Nat
) -> FrameDecision:
  match codes:
    case (operation, code, _):
      decode.words.operation.validated(input, size, version, generation,
        request_id, operation, operation.valid(code), max_payload_bytes)

def decode.words.operation(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +size: U32,
  max_payload_bytes: Nat,
  +version: U32,
  +generation: U32,
  +request_id: U32
) -> FrameDecision:
  match pair:
    case (input, Some{operation}):
      decode.words.operation.checked(input, size, version, generation,
        request_id, u32.duplicate.triple(operation), max_payload_bytes)
    case _: Malformed{}

def decode.words.request_id(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +size: U32,
  max_payload_bytes: Nat,
  +version: U32,
  +generation: U32
) -> FrameDecision:
  match pair:
    case (input, Some{request_id}):
      decode.words.operation(Bytes.get.u32be(input, 16), size,
        max_payload_bytes, version, generation, request_id)
    case _: Malformed{}

def decode.words.generation(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +size: U32,
  max_payload_bytes: Nat,
  +version: U32
) -> FrameDecision:
  match pair:
    case (input, Some{generation}):
      decode.words.request_id(Bytes.get.u32be(input, 12), size,
        max_payload_bytes, version, generation)
    case _: Malformed{}

def decode.words.version(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +size: U32,
  max_payload_bytes: Nat
) -> FrameDecision:
  match pair:
    case (input, Some{version}):
      decode.words.generation(Bytes.get.u32be(input, 8), size,
        max_payload_bytes, version)
    case _: Malformed{}

def decode.magic.checked(
  input: Bytes.Bytes,
  +size: U32,
  max_payload_bytes: Nat,
  valid_magic: Bool
) -> FrameDecision:
  match valid_magic:
    case False{}: Malformed{}
    case True{}:
      decode.words.version(Bytes.get.u32be(input, 4), size,
        max_payload_bytes)

def decode.magic.comparison(
  comparison: Bytes.Bytes & Bytes.Bytes & Bool,
  input: Bytes.Bytes,
  +size: U32,
  max_payload_bytes: Nat
) -> FrameDecision:
  match comparison:
    case (_, _, valid):
      decode.magic.checked(input, size, max_payload_bytes, valid)

def decode.magic.slice(
  sliced: Bytes.Bytes & Bytes.Bytes,
  +size: U32,
  max_payload_bytes: Nat
) -> FrameDecision:
  match sliced:
    case (input, candidate):
      decode.magic.comparison(Bytes.eq(magic(), candidate), input, size,
        max_payload_bytes)

def decode.available(
  input: Bytes.Bytes,
  +size: U32,
  max_payload_bytes: Nat,
  enough_header: Bool
) -> FrameDecision:
  match enough_header:
    case False{}: NeedMore{}
    case True{}:
      decode.magic.slice(Bytes.slice(input, 0, 4), size, max_payload_bytes)

def decode.header.size(
  input: Bytes.Bytes,
  max_payload_bytes: Nat,
  +size: U32
) -> FrameDecision:
  decode.available(input, size, max_payload_bytes,
    Nat.is_le(24n, U32.to_nat(size)))

def decode.header.pair(
  pair: Bytes.Bytes & U32,
  max_payload_bytes: Nat
) -> FrameDecision:
  match pair:
    case (input, size):
      decode.header.size(input, max_payload_bytes, size)

def decode.header(input: Bytes.Bytes, max_payload_bytes: Nat) -> FrameDecision:
  decode.header.pair(Bytes.length(input), max_payload_bytes)

# Decodes one complete frame or reports whether more input is required.
def decode(input: Bytes.Bytes, max_payload_bytes: Nat) -> FrameDecision:
  decode.header(input, max_payload_bytes)

def decode.response.payload.slice(
  sliced: Bytes.Bytes & Bytes.Bytes,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  status: ResponseStatus
) -> ResponseDecision:
  match sliced:
    case (_, payload):
      DecodedResponse{Response{version, generation, request_id, status, payload}}

def decode.response.payload(
  pair: Bytes.Bytes & U32,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  status: ResponseStatus
) -> ResponseDecision:
  match pair:
    case (payload, +length):
      decode.response.payload.slice(Bytes.slice(payload, 4, (length - 4 : U32)),
        version, generation, request_id, status)

def decode.response.status.ready(
  input: Bytes.Bytes,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  result: ResponseStatusDecision
) -> ResponseDecision:
  match result:
    case InvalidResponseStatus{}: UnknownResponseStatus{}
    case ValidResponseStatus{status}:
      decode.response.payload(Bytes.length(input), version, generation,
        request_id, status)

def decode.response.status(
  pair: Bytes.Bytes & Maybe<&2, U32>,
  +version: U32,
  +generation: U32,
  +request_id: U32
) -> ResponseDecision:
  match pair:
    case (input, Some{code}):
      decode.response.status.ready(input, version, generation, request_id,
        response.status.decode(code))
    case _: MalformedResponse{}

def decode.response.minimum(
  input: Bytes.Bytes,
  +version: U32,
  +generation: U32,
  +request_id: U32,
  enough_status: Bool
) -> ResponseDecision:
  match enough_status:
    case False{}: MalformedResponse{}
    case True{}:
      decode.response.status(Bytes.get.u32be(input, 0), version, generation,
        request_id)

def decode.response.size(
  pair: Bytes.Bytes & U32,
  +version: U32,
  +generation: U32,
  +request_id: U32
) -> ResponseDecision:
  match pair:
    case (input, +size):
      decode.response.minimum(input, version, generation, request_id,
        Nat.is_le(4n, U32.to_nat(size)))

def decode.response.operation(
  +version: U32,
  +generation: U32,
  +request_id: U32,
  +operation: U32,
  payload: Bytes.Bytes
) -> ResponseDecision:
  match operation:
    case 7:
      decode.response.size(Bytes.length(payload), version, generation, request_id)
    case _: UnexpectedResponse{}

def decode.response.frame(decision: FrameDecision) -> ResponseDecision:
  match decision:
    case NeedMore{}: ResponseNeedMore{}
    case Malformed{}: MalformedResponse{}
    case UnknownOperation{}: UnexpectedResponse{}
    case FrameTooLarge{}: ResponseTooLarge{}
    case Decoded{Request{version, generation, request_id, operation, payload}}:
      decode.response.operation(version, generation, request_id, operation, payload)

# Decodes a response only after validating its correlated outer frame.
def decode_response(input: Bytes.Bytes, max_payload_bytes: Nat) -> ResponseDecision:
  decode.response.frame(decode(input, max_payload_bytes))

def validate.policy(
  request_id: U32,
  operation: U32,
  payload: Bytes.Bytes,
  version_valid: Bool,
  generation_valid: Bool,
  operation_valid: Bool,
  size_valid: Bool
) -> Decision:
  match version_valid:
    case False{}: VersionMismatch{}
    case True{}:
      match generation_valid:
        case False{}: StaleGeneration{}
        case True{}:
          match operation_valid:
            case False{}: UnsupportedRequestOperation{}
            case True{}:
              match size_valid:
                case False{}: ResourceLimit{}
                case True{}: Accepted{request_id, operation, payload}

def validate.sized(
  request_id: U32,
  operation: U32,
  version_valid: Bool,
  generation_valid: Bool,
  operation_valid: Bool,
  sizes: Bytes.Bytes & U32,
  max_payload_bytes: Nat
) -> Decision:
  match sizes:
    case (request_payload, +payload_length):
      validate.policy(request_id, operation, request_payload, version_valid,
        generation_valid, operation_valid,
        U32.is_le(payload_length, U32.from_nat(max_payload_bytes)))

# Validates protocol identity, active generation, and payload size.
def validate(
  request: Request,
  expected_version: U32,
  active_generation: U32,
  max_payload_bytes: Nat
) -> Decision:
  match request:
    case Request{+version, +generation, +request_id, +operation, payload}:
      validate.sized(request_id, operation,
        U32.is_eq(version, expected_version),
        U32.is_eq(generation, active_generation),
        operation.request.valid(operation),
        Bytes.length(payload), max_payload_bytes)
