import Base
import ../src/coordinator/Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Admits a payload at the generation-four encoded record ceiling.
law protocol_payload_at_record_ceiling_is_admitted:
  {Protocol.payload.admitted(1073741824) == True{} : Bool}

# Rejects one byte beyond the generation-four encoded record ceiling.
law protocol_payload_over_record_ceiling_is_rejected:
  {Protocol.payload.admitted(1073741825) == False{} : Bool}

# Extracts the identifier only from an accepted protocol decision.
def accepted_id(decision: Protocol.Decision) -> Maybe<&1, U32>:
  match decision:
    case Protocol.Accepted{request_id, _, _}: Some{request_id}
    case _: None{}

def accepted.operation(decision: Protocol.Decision) -> Maybe<&1, U32>:
  match decision:
    case Protocol.Accepted{_, operation, _}: Some{operation}
    case _: None{}

def frame.payload.equal(comparison: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match comparison:
    case (_, _, equal): equal

def response.roundtrips(
  expected: Protocol.Response,
  decision: Protocol.ResponseDecision
) -> Bool:
  match expected decision:
    case Protocol.Response{version, generation, request_id, status, payload}
        Protocol.DecodedResponse{Protocol.Response{decoded_version,
          decoded_generation, decoded_id, decoded_status, decoded_payload}}:
      U32.is_eq(version, decoded_version) &&
        U32.is_eq(generation, decoded_generation) &&
        U32.is_eq(request_id, decoded_id) &&
        U32.is_eq(Protocol.response.status.code(status),
          Protocol.response.status.code(decoded_status)) &&
        frame.payload.equal(Bytes.eq(payload, decoded_payload))
    case _ _:
      False{}

def frame.roundtrips(
  expected: Protocol.Request,
  decision: Protocol.FrameDecision
) -> Bool:
  match expected decision:
    case Protocol.Request{version, generation, request_id, operation, payload}
        Protocol.Decoded{Protocol.Request{decoded_version, decoded_generation,
          decoded_id, decoded_operation, decoded_payload}}:
      U32.is_eq(version, decoded_version) &&
        U32.is_eq(generation, decoded_generation) &&
        U32.is_eq(request_id, decoded_id) &&
        U32.is_eq(operation, decoded_operation) &&
        frame.payload.equal(Bytes.eq(payload, decoded_payload))
    case _ _:
      False{}

# Current-generation requests within the payload cap are accepted.
law current_owner_request_is_accepted:
  {accepted_id(Protocol.validate(Protocol.Request{1, 7, 19, 2, Bytes.new(0)}, 1, 7, 16n)) == Some{19} : Maybe<&1, U32>}

# Keeps the validated operation tag available to the owner dispatcher.
law accepted_request_retains_operation_tag:
  {accepted.operation(Protocol.validate(Protocol.Request{1, 7, 19, 2, Bytes.new(0)}, 1, 7, 16n)) == Some{2} : Maybe<&1, U32>}

# Requests from unsupported protocol versions are rejected.
law unsupported_protocol_version_is_rejected:
  {Protocol.validate(Protocol.Request{2, 7, 19, 2, Bytes.new(0)}, 1, 7, 16n) == Protocol.VersionMismatch{} : Protocol.Decision}

# Requests targeting an obsolete owner generation are rejected.
law stale_owner_generation_is_rejected:
  {Protocol.validate(Protocol.Request{1, 6, 19, 2, Bytes.new(0)}, 1, 7, 16n) == Protocol.StaleGeneration{} : Protocol.Decision}

# Requests above the configured payload cap are rejected.
law request_over_limit_is_rejected:
  {Protocol.validate(Protocol.Request{1, 7, 19, 2, Bytes.new(17)}, 1, 7, 16n) == Protocol.ResourceLimit{} : Protocol.Decision}

# Keeps the response-only tag out of the request dispatcher.
law response_tag_is_not_a_request_operation:
  {Protocol.validate(Protocol.Request{1, 7, 19, 7, Bytes.new(0)}, 1, 7, 16n) == Protocol.UnsupportedRequestOperation{} : Protocol.Decision}

# Round-trips the operation tag and payload in an exact request frame.
law encoded_request_decodes_exactly:
  {frame.roundtrips(Protocol.Request{1, 7, 19, 2, Bytes.new(0)},
    Protocol.decode(Protocol.encode(Protocol.Request{1, 7, 19, 2, Bytes.new(0)}), 16n)) == True{} : Bool}

# Reports an incomplete fixed header as requiring more bytes.
law truncated_frame_requests_more_bytes:
  {Protocol.decode(Bytes.new(19), 16n) == Protocol.NeedMore{} : Protocol.FrameDecision}

def frame.prefix.decision(
  sliced: Bytes.Bytes & Bytes.Bytes
) -> Protocol.FrameDecision:
  match sliced:
    case (_, prefix): Protocol.decode(prefix, 16n)

# Reports an incomplete payload as requiring more bytes.
law truncated_payload_requests_more_bytes:
  {frame.prefix.decision(Bytes.slice(
    Protocol.encode(Protocol.Request{1, 7, 19, 2, Bytes.new(1)}), 0, 24)) ==
    Protocol.NeedMore{} : Protocol.FrameDecision}

# Rejects bytes following the declared frame payload.
law trailing_frame_bytes_are_rejected:
  {Protocol.decode(Bytes.concat([
    Protocol.encode(Protocol.Request{1, 7, 19, 2, Bytes.new(0)}), Bytes.new(1)]), 16n) ==
    Protocol.Malformed{} : Protocol.FrameDecision}

# Rejects oversized payloads before creating a decoded request.
law oversized_payload_is_rejected_before_dispatch:
  {Protocol.decode(Protocol.encode(Protocol.Request{1, 7, 19, 2, Bytes.new(17)}), 16n) == Protocol.FrameTooLarge{} : Protocol.FrameDecision}

# Rejects operation tags outside the supported request set.
law unknown_operation_tag_is_rejected:
  {Protocol.decode(Protocol.encode(Protocol.Request{1, 7, 19, 255, Bytes.new(0)}), 16n) == Protocol.UnknownOperation{} : Protocol.FrameDecision}

# Round-trips a typed response status and its independent detail payload.
law encoded_response_decodes_exactly:
  {response.roundtrips(Protocol.Response{1, 7, 20, Protocol.Timeout{}, Bytes.new(2)},
    Protocol.decode_response(Protocol.encode_response(
      Protocol.Response{1, 7, 20, Protocol.Timeout{}, Bytes.new(2)}), 16n)) ==
    True{} : Bool}

# Round-trips the explicit unsupported-platform response status.
law unsupported_platform_response_decodes:
  {response.roundtrips(Protocol.Response{1, 7, 21,
    Protocol.UnsupportedPlatform{}, Bytes.new(0)},
    Protocol.decode_response(Protocol.encode_response(Protocol.Response{1, 7,
      21, Protocol.UnsupportedPlatform{}, Bytes.new(0)}), 16n)) == True{} : Bool}

# Round-trips the explicit already-exists response status.
law already_exists_response_decodes:
  {response.roundtrips(Protocol.Response{1, 7, 22, Protocol.AlreadyExists{},
    Bytes.new(0)}, Protocol.decode_response(Protocol.encode_response(
      Protocol.Response{1, 7, 22, Protocol.AlreadyExists{}, Bytes.new(0)}),
      16n)) == True{} : Bool}

# Rejects response codes outside the typed status set.
law unknown_response_status_is_rejected:
  {Protocol.decode_response(Protocol.encode(Protocol.Request{1, 7, 20, 7,
    Bytes.concat([Protocol.u32.bytes(99), Bytes.new(0)])}), 16n) ==
    Protocol.UnknownResponseStatus{} : Protocol.ResponseDecision}
