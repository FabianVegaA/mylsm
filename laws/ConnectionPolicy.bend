import Base
import ../src/coordinator/ConnectionPolicy.bend as Policy
import ../src/coordinator/Protocol.bend as Protocol
import ../src/coordinator/QueuePolicy.bend as QueuePolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Carries the state for PayloadObservation.
type PayloadObservation is Type:
  ObservedRequest{request: Protocol.Request}
  NoRequest{}

def header.prefix(sliced: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match sliced:
    case (_, prefix): prefix

def header.two.chunks.second(
  step: Policy.HeaderStep,
  second: Bytes.Bytes
) -> Maybe<&2, U32>:
  match step:
    case Policy.HeaderPartial{chunks, received_bytes}:
      Policy.header.accepted.frame.bytes(Policy.header.step(chunks,
        received_bytes, second, 16n))
    case _: None{}

def header.two.chunks(
  first: Bytes.Bytes,
  second: Bytes.Bytes
) -> Maybe<&2, U32>:
  header.two.chunks.second(Policy.header.step(Nil{}, 0n, first, 16n),
    second)

def payload.two.chunks.second(
  step: Policy.PayloadStep,
  second: Bytes.Bytes,
  expected_bytes: U32
) -> Policy.PayloadStep:
  match step:
    case Policy.PayloadPartial{header, chunks, received_bytes}:
      Policy.payload.step(header, chunks, received_bytes, second,
        expected_bytes, 16n)
    case _: Policy.PayloadRejected{Protocol.Malformed{}}

def payload.two.chunks.sized(
  header: Bytes.Bytes,
  first: Bytes.Bytes,
  second: Bytes.Bytes,
  limits: U32 & U32 & U32
) -> Policy.PayloadStep:
  match limits:
    case (first_limit, (second_limit, _)):
      payload.two.chunks.second(Policy.payload.step(header, Nil{}, 0n,
        first, first_limit, 16n), second, second_limit)

def payload.two.chunks(
  header: Bytes.Bytes,
  first: Bytes.Bytes,
  second: Bytes.Bytes,
  expected_bytes: U32
) -> Policy.PayloadStep:
  payload.two.chunks.sized(header, first, second,
    Protocol.u32.duplicate.triple(expected_bytes))

def payload.accepted.request(step: Policy.PayloadStep) -> PayloadObservation:
  match step:
    case Policy.PayloadAccepted{request}: ObservedRequest{request}
    case _: NoRequest{}

# Verifies before deadline continues.
law before_deadline_continues:
  {Policy.deadline(4n, 5n) == Policy.Continue{} : Policy.DeadlineDecision}

# Verifies at deadline expires.
law at_deadline_expires:
  {Policy.deadline(5n, 5n) == Policy.Expire{} : Policy.DeadlineDecision}

# Verifies after deadline expires.
law after_deadline_expires:
  {Policy.deadline(6n, 5n) == Policy.Expire{} : Policy.DeadlineDecision}

# Verifies saturated admission maps to busy.
law saturated_admission_maps_to_busy:
  {Policy.admission.rejection.status(
    QueuePolicy.Saturated{}) == Protocol.Busy{} :
      Protocol.ResponseStatus}

# Verifies oversized admission maps to resource limit.
law oversized_admission_maps_to_resource_limit:
  {Policy.admission.rejection.status(
    QueuePolicy.Oversized{}) ==
    Protocol.ResponseResourceLimit{} : Protocol.ResponseStatus}

# Verifies poll timeout without connections uses idle bound.
law poll_timeout_without_connections_uses_idle_bound:
  {Policy.poll.timeout(Policy.PollTimeout{False{}, False{}, 5, 7, 3}) == 30000 : U32}

# Verifies poll timeout with connections uses shortest bound.
law poll_timeout_with_connections_uses_shortest_bound:
  {Policy.poll.timeout(Policy.PollTimeout{True{}, False{}, 5, 7, 3}) == 3 : U32}

# Verifies active queue waits for event or deadline.
law active_queue_waits_for_event_or_deadline:
  for frame_timeout_ms: U32
  for response_timeout_ms: U32
  for queue_timeout_ms: U32
  {Policy.poll.timeout(Policy.PollTimeout{True{}, True{}, frame_timeout_ms,
    response_timeout_ms, queue_timeout_ms}) ==
    U32.from_nat(Nat.min(30000n,
      Nat.min(U32.to_nat(frame_timeout_ms),
        Nat.min(U32.to_nat(response_timeout_ms),
          U32.to_nat(queue_timeout_ms))))) : U32}

# Verifies connection slot is available below limit.
law connection_slot_is_available_below_limit:
  {Policy.capacity(3n, 4n) == Policy.Available{} : Policy.CapacityDecision}

# Verifies connection limit is full at boundary.
law connection_limit_is_full_at_boundary:
  {Policy.capacity(4n, 4n) == Policy.Full{} : Policy.CapacityDecision}

# Verifies connection limit stays full after boundary.
law connection_limit_stays_full_after_boundary:
  {Policy.capacity(5n, 4n) == Policy.Full{} : Policy.CapacityDecision}

# Verifies connection id is available before u32 exhaustion.
law connection_id_is_available_before_u32_exhaustion:
  {Policy.connection.id(4294967294) == Policy.IdAvailable{} : Policy.ConnectionIdDecision}

# Verifies connection id exhaustion never wraps to zero.
law connection_id_exhaustion_never_wraps_to_zero:
  {Policy.connection.id(4294967295) == Policy.IdExhausted{} : Policy.ConnectionIdDecision}

# Verifies partial write advances only completed bytes.
law partial_write_advances_only_completed_bytes:
  {Policy.progress(7, 3, 16) == Policy.Advanced{10} : Policy.Progress}

# Verifies write progress rejects offset past total.
law write_progress_rejects_offset_past_total:
  {Policy.progress(17, 0, 16) == Policy.InvalidProgress{} : Policy.Progress}

# Verifies write progress rejects count overrun.
law write_progress_rejects_count_overrun:
  {Policy.progress(7, 10, 16) == Policy.InvalidProgress{} : Policy.Progress}

# Verifies maximum u32 offset rejects addition overflow.
law maximum_u32_offset_rejects_addition_overflow:
  {Policy.progress(4294967295, 1, 4294967295) ==
    Policy.InvalidProgress{} : Policy.Progress}

# Verifies write at total waits without advance.
law write_at_total_waits_without_advance:
  {Policy.progress(16, 0, 16) == Policy.Waiting{16} : Policy.Progress}

# Verifies read chunk minimum is below frame.
law read_chunk_minimum_is_below_frame:
  for cap: Nat
  for frame_remaining: Nat
  for rx_available: Nat
  {Nat.is_le(Nat.min(cap,
    Nat.min(frame_remaining, rx_available)), frame_remaining) == True{} : Bool}

# Verifies read chunk minimum is below rx capacity.
law read_chunk_minimum_is_below_rx_capacity:
  for cap: Nat
  for frame_remaining: Nat
  for rx_available: Nat
  {Nat.is_le(Nat.min(cap,
    Nat.min(frame_remaining, rx_available)), rx_available) == True{} : Bool}

# Verifies read chunk minimum is below cap.
law read_chunk_minimum_is_below_cap:
  for cap: Nat
  for frame_remaining: Nat
  for rx_available: Nat
  {Nat.is_le(Nat.min(cap,
    Nat.min(frame_remaining, rx_available)), cap) == True{} : Bool}

# Verifies read chunk never exceeds remaining frame.
law read_chunk_never_exceeds_remaining_frame:
  for frame_remaining: Nat
  for rx_available: Nat
  {Nat.is_le(Policy.read.chunk(frame_remaining, rx_available),
    frame_remaining) == True{} : Bool}

# Verifies read chunk never exceeds aggregate rx capacity.
law read_chunk_never_exceeds_aggregate_rx_capacity:
  for frame_remaining: Nat
  for rx_available: Nat
  {Nat.is_le(Policy.read.chunk(frame_remaining, rx_available),
    rx_available) == True{} : Bool}

# Verifies read chunk is bounded to sixty four kib.
law read_chunk_is_bounded_to_sixty_four_kib:
  for frame_remaining: Nat
  for rx_available: Nat
  {Nat.is_le(Policy.read.chunk(frame_remaining, rx_available),
    65536n) == True{} : Bool}

# Verifies zero write progress preserves offset.
law zero_write_progress_preserves_offset:
  {Policy.progress(7, 0, 16) == Policy.Waiting{7} : Policy.Progress}

# Verifies complete header admits its declared frame size.
law complete_header_admits_its_declared_frame_size:
  {Policy.header.accepted.frame.bytes(Policy.header.step(Nil{}, 0n,
    header.prefix(Bytes.slice(Protocol.encode(
      Protocol.Request{1, 7, 19, 2, Bytes.new(1)}), 0, 24)), 16n)) ==
    Some{25} : Maybe<&2, U32>}

# Verifies split header chunks preserve declared frame size.
law split_header_chunks_preserve_declared_frame_size:
  {header.two.chunks(
    header.prefix(Bytes.slice(Protocol.encode(
      Protocol.Request{1, 7, 19, 2, Bytes.new(1)}), 0, 12)),
    header.prefix(Bytes.slice(Protocol.encode(
      Protocol.Request{1, 7, 19, 2, Bytes.new(1)}), 12, 12))) ==
    Some{25} : Maybe<&2, U32>}

# Verifies split payload chunks decode one request.
law split_payload_chunks_decode_one_request:
  {payload.accepted.request(payload.two.chunks(
    header.prefix(Bytes.slice(Protocol.encode(
      Protocol.Request{1, 7, 19, 2, Bytes.new(2)}), 0, 24)),
    header.prefix(Bytes.slice(Protocol.encode(
      Protocol.Request{1, 7, 19, 2, Bytes.new(2)}), 24, 1)),
    header.prefix(Bytes.slice(Protocol.encode(
      Protocol.Request{1, 7, 19, 2, Bytes.new(2)}), 25, 1)), 2)) ==
    ObservedRequest{Protocol.Request{1, 7, 19, 2, Bytes.new(2)}} :
      PayloadObservation}

# Verifies payload chunk cannot exceed declared length.
law payload_chunk_cannot_exceed_declared_length:
  {payload.two.chunks(
    header.prefix(Bytes.slice(Protocol.encode(
      Protocol.Request{1, 7, 19, 2, Bytes.new(2)}), 0, 24)),
    Bytes.new(2), Bytes.new(0), 1) ==
    Policy.PayloadRejected{Protocol.Malformed{}} : Policy.PayloadStep}

# Verifies empty payload completes without another read.
law empty_payload_completes_without_another_read:
  {payload.accepted.request(Policy.payload.step(
    header.prefix(Bytes.slice(Protocol.encode(
      Protocol.Request{1, 7, 19, 2, Bytes.new(0)}), 0, 24)),
    Nil{}, 0n, Bytes.new(0), 0, 16n)) ==
    ObservedRequest{Protocol.Request{1, 7, 19, 2, Bytes.new(0)}} :
      PayloadObservation}
