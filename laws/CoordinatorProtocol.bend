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

# Admits the atomic batch operation while reserving tag seven for responses.
law batch_tag_is_a_request_operation:
  {Protocol.validate(Protocol.Request{1, 7, 19, 8, Bytes.new(0)}, 1, 7, 16n) ==
    Protocol.Accepted{19, 8, Bytes.new(0)} : Protocol.Decision}

# Admits the snapshot-open tag through request validation.
law snapshot_open_tag_is_a_request_operation:
  {Protocol.validate(Protocol.Request{1, 7, 19, 9, Bytes.new(0)}, 1, 7, 16n) ==
    Protocol.Accepted{19, 9, Bytes.new(0)} : Protocol.Decision}

# Admits the snapshot-get tag and leaves its token/key framing to decoding.
law snapshot_get_tag_is_a_request_operation:
  {Protocol.validate(Protocol.Request{1, 7, 19, 10, Bytes.new(4)}, 1, 7, 16n) ==
    Protocol.Accepted{19, 10, Bytes.new(4)} : Protocol.Decision}

# Admits the snapshot-close operation for owner dispatch.
law snapshot_close_tag_is_a_request_operation:
  {Protocol.validate(Protocol.Request{1, 7, 19, 11, Bytes.new(4)}, 1, 7, 16n) ==
    Protocol.Accepted{19, 11, Bytes.new(4)} : Protocol.Decision}

# Requires all cursor lifecycle request tags to pass protocol admission.
def snapshot.cursor.tags.valid(pair: Bool & Bool & Bool) -> Bool:
  match pair:
    case (True{}, (True{}, True{})): True{}
    case _: False{}

# Admits snapshot cursor open, next, and close requests through validation.
law snapshot_cursor_tags_are_request_operations:
  {snapshot.cursor.tags.valid((Protocol.operation.request.valid(12),
    (Protocol.operation.request.valid(13),
      Protocol.operation.request.valid(14)))) == True{} : Bool}

# Encodes snapshot identifiers as fixed-width big-endian values.
law snapshot_identifier_one_roundtrips:
  {Protocol.snapshot.id.read(Protocol.snapshot.id.bytes(1)) == Some{1} : Maybe<&2, U32>}

# Preserves the largest non-wrapping snapshot token.
law snapshot_identifier_maximum_roundtrips:
  {Protocol.snapshot.id.read(Protocol.snapshot.id.bytes(4294967295)) == Some{4294967295} : Maybe<&2, U32>}

# Rejects snapshot identifiers whose payload is not exactly four bytes.
law malformed_snapshot_identifier_payload_is_rejected:
  {Protocol.snapshot.id.read(Bytes.new(3)) == None{} : Maybe<&2, U32>}

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

# Preserves each copy of an arbitrary natural without numeric traversal.
law natural_pair_preserves_input:
  for +value: Nat
  {Protocol.nat.duplicate.pair(value) == (value, value) : Nat & Nat}

# Preserves each copy of an arbitrary fixed-width protocol word.
law word_triple_preserves_input:
  for +value: U32
  {Protocol.u32.duplicate.triple(value) == (value, value, value) : U32 & U32 & U32}

# Rejects the largest declared payload using only its fixed header.
law maximum_declared_payload_is_rejected:
  {Protocol.decode(Bytes.set.u32be(
    Protocol.encode(Protocol.Request{1, 7, 19, 2, Bytes.new(0)}),
    20, 4294967295), 16n) == Protocol.FrameTooLarge{} : Protocol.FrameDecision}

# Rejects the largest operation tag without traversing its numeric value.
law maximum_operation_tag_is_rejected:
  {Protocol.decode(Protocol.encode(
    Protocol.Request{1, 7, 19, 4294967295, Bytes.new(0)}), 16n) ==
    Protocol.UnknownOperation{} : Protocol.FrameDecision}
