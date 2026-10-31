import Base
import ../ByteMemTable.bend as ByteMemTable
import ./Protocol.bend as Protocol
import ./QueuePolicy.bend as QueuePolicy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Classifies whether a connection has passed its deadline.
type DeadlineDecision is Data:
  Continue{}
  Expire{}

# Carries the state for PollTimeoutInput.
type PollTimeoutInput is Data:
  PollTimeout{has_connections: Bool, queue_active: Bool,
    frame_timeout_ms: U32,
    response_timeout_ms: U32, queue_timeout_ms: U32}

# Carries the state for CapacityDecision.
type CapacityDecision is Data:
  Available{}
  Full{}

# Carries the state for ConnectionIdDecision.
type ConnectionIdDecision is Data:
  IdAvailable{}
  IdExhausted{}

# Carries the state for Progress.
type Progress is Data:
  Waiting{offset: U32}
  Advanced{offset: U32}
  InvalidProgress{}

def read.chunk(frame_remaining: Nat, rx_available: Nat) -> Nat:
  Nat.min(65536n, Nat.min(frame_remaining, rx_available))

# Carries the state for HeaderStep.
type HeaderStep is Type:
  HeaderPartial{chunks: List<&1, Bytes.Bytes>, received_bytes: Nat}
  HeaderAccepted{header: Bytes.Bytes, frame_bytes: U32}
  HeaderRejected{decision: Protocol.HeaderDecision}

# Carries the state for PayloadStep.
type PayloadStep is Type:
  PayloadPartial{header: Bytes.Bytes, chunks: List<&1, Bytes.Bytes>,
    received_bytes: Nat}
  PayloadAccepted{request: Protocol.Request}
  PayloadRejected{decision: Protocol.FrameDecision}

def header.accepted.frame.bytes(step: HeaderStep) -> Maybe<&2, U32>:
  match step:
    case HeaderPartial{_, _}: None{}
    case HeaderAccepted{_, frame_bytes}: Some{frame_bytes}
    case HeaderRejected{_}: None{}

def deadline.decision(is_before: Bool) -> DeadlineDecision:
  match is_before:
    case True{}: Continue{}
    case False{}: Expire{}

# Handles deadline.
def deadline(now_ms: Nat, deadline_ms: Nat) -> DeadlineDecision:
  deadline.decision(Nat.is_lt(now_ms, deadline_ms))

def admission.rejection.status(
  reason: QueuePolicy.Rejection
) -> Protocol.ResponseStatus:
  match reason:
    case QueuePolicy.Saturated{}: Protocol.Busy{}
    case QueuePolicy.Oversized{}: Protocol.ResponseResourceLimit{}

def poll.timeout.decide(
  _queue_active: Bool,
  has_connections: Bool,
  frame_timeout_ms: U32,
  response_timeout_ms: U32,
  queue_timeout_ms: U32
) -> U32:
  match has_connections:
    case False{}: 30000
    case True{}:
      U32.from_nat(Nat.min(30000n,
        Nat.min(U32.to_nat(frame_timeout_ms),
          Nat.min(U32.to_nat(response_timeout_ms),
            U32.to_nat(queue_timeout_ms)))))

def poll.timeout(+input: PollTimeoutInput) -> U32:
  match input:
    case PollTimeout{has_connections, queue_active, frame_timeout_ms,
      response_timeout_ms, queue_timeout_ms}:
      poll.timeout.decide(queue_active, has_connections, frame_timeout_ms,
        response_timeout_ms, queue_timeout_ms)
def capacity.decision(below_limit: Bool) -> CapacityDecision:
  match below_limit:
    case True{}: Available{}
    case False{}: Full{}

# Handles capacity.
def capacity(current: Nat, maximum: Nat) -> CapacityDecision:
  capacity.decision(Nat.is_lt(current, maximum))

def connection.id.decision(is_exhausted: Bool) -> ConnectionIdDecision:
  match is_exhausted:
    case True{}: IdExhausted{}
    case False{}: IdAvailable{}

def connection.id(next_id: U32) -> ConnectionIdDecision:
  connection.id.decision(U32.is_eq(next_id, 4294967295))

def progress.zero(+offset: U32, +count: U32, is_zero: Bool) -> Progress:
  match is_zero:
    case True{}: Waiting{offset}
    case False{}: Advanced{U32.add(offset, count)}

def progress.result(+offset: U32, +count: U32, fits: Bool) -> Progress:
  match fits:
    case False{}: InvalidProgress{}
    case True{}: progress.zero(offset, count, U32.is_eq(count, 0))

def progress.valid(+offset: U32, +count: U32,
  +total: U32, valid_offset: Bool) -> Progress:
  match valid_offset:
    case False{}: InvalidProgress{}
    case True{}:
      progress.result(offset, count,
        U32.is_le(count, U32.sub(total, offset)))

# Handles progress.
def progress(+offset: U32, +count: U32, +total: U32) -> Progress:
  progress.valid(offset, count, total, U32.is_le(offset, total))

def header.classify.decision(
  decision: Protocol.HeaderDecision,
  header: Bytes.Bytes
) -> HeaderStep:
  match decision:
    case Protocol.HeaderReady{frame_bytes}:
      HeaderAccepted{header, frame_bytes}
    case _: HeaderRejected{decision}

def header.classify.cloned(
  pair: Bytes.Bytes & Bytes.Bytes,
  max_payload_bytes: Nat
) -> HeaderStep:
  match pair:
    case (header, validation):
      header.classify.decision(
        Protocol.header.inspect(validation, max_payload_bytes), header)

def header.classify.buffer(
  header: Bytes.Bytes,
  max_payload_bytes: Nat
) -> HeaderStep:
  header.classify.cloned(ByteMemTable.bytes.clone(header), max_payload_bytes)

def header.collected(
  chunks: List<&1, Bytes.Bytes>,
  next_received: Nat,
  max_payload_bytes: Nat,
  complete: Bool
) -> HeaderStep:
  match complete:
    case False{}: HeaderPartial{chunks, next_received}
    case True{}:
      header.classify.buffer(
        Bytes.concat(List.reverse(&1, Bytes.Bytes, chunks)),
        max_payload_bytes)

def header.total.complete(
  chunks: List<&1, Bytes.Bytes>,
  chunk: Bytes.Bytes,
  totals: Nat & Nat,
  max_payload_bytes: Nat
) -> HeaderStep:
  match totals:
    case (next_received, checked_received):
      header.collected(Con{chunk, chunks}, next_received,
        max_payload_bytes, Nat.is_eq(checked_received, 24n))

def header.total.result(
  chunks: List<&1, Bytes.Bytes>,
  chunk: Bytes.Bytes,
  next_received: Nat,
  max_payload_bytes: Nat,
  fits: Bool
) -> HeaderStep:
  match fits:
    case False{}: HeaderRejected{Protocol.HeaderMalformed{}}
    case True{}:
      header.total.complete(chunks, chunk,
        Protocol.nat.duplicate.pair(next_received), max_payload_bytes)

def header.total.sums(
  chunks: List<&1, Bytes.Bytes>,
  received: Nat & Nat,
  chunk: Bytes.Bytes,
  chunk_length: Nat & Nat,
  max_payload_bytes: Nat
) -> HeaderStep:
  match received:
    case (for_total, for_limit):
      match chunk_length:
        case (length_total, length_limit):
          header.total.result(chunks, chunk,
            Nat.add(for_total, length_total), max_payload_bytes,
            Nat.is_le(Nat.add(for_limit, length_limit), 24n))

def header.total(
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: Nat,
  chunk: Bytes.Bytes,
  chunk_bytes: Nat,
  max_payload_bytes: Nat
) -> HeaderStep:
  header.total.sums(chunks,
    Protocol.nat.duplicate.pair(received_bytes), chunk,
    Protocol.nat.duplicate.pair(chunk_bytes), max_payload_bytes)

def header.measured(
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: Nat,
  measured: Bytes.Bytes & U32,
  max_payload_bytes: Nat
) -> HeaderStep:
  match measured:
    case (chunk, length):
      header.total(chunks, received_bytes, chunk, U32.to_nat(length),
        max_payload_bytes)

def header.step(
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: Nat,
  chunk: Bytes.Bytes,
  max_payload_bytes: Nat
) -> HeaderStep:
  header.measured(chunks, received_bytes, Bytes.length(chunk),
    max_payload_bytes)

def payload.decoded(decision: Protocol.FrameDecision) -> PayloadStep:
  match decision:
    case Protocol.Decoded{request}: PayloadAccepted{request}
    case decision: PayloadRejected{decision}

def payload.complete(
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  chunk: Bytes.Bytes,
  max_payload_bytes: Nat
) -> PayloadStep:
  payload.decoded(Protocol.decode(Bytes.concat(Con{header,
    List.reverse(&1, Bytes.Bytes, Con{chunk, chunks})}), max_payload_bytes))

def payload.total.classified(
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  chunk: Bytes.Bytes,
  next_received: Nat,
  max_payload_bytes: Nat,
  complete: Bool
) -> PayloadStep:
  match complete:
    case False{}:
      PayloadPartial{header, Con{chunk, chunks}, next_received}
    case True{}: payload.complete(header, chunks, chunk, max_payload_bytes)

def payload.total.received(
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  chunk: Bytes.Bytes,
  received: Nat & Nat,
  expected_complete: Nat,
  max_payload_bytes: Nat
) -> PayloadStep:
  match received:
    case (next_received, checked_received):
      payload.total.classified(header, chunks, chunk, next_received,
        max_payload_bytes, Nat.is_eq(checked_received, expected_complete))

def payload.total.result(
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  chunk: Bytes.Bytes,
  next_received: Nat,
  expected_lengths: Nat & Nat,
  max_payload_bytes: Nat,
  fits: Bool
) -> PayloadStep:
  match expected_lengths:
    case (_, expected_complete):
      match fits:
        case False{}: PayloadRejected{Protocol.Malformed{}}
        case True{}:
          payload.total.received(header, chunks, chunk,
            Protocol.nat.duplicate.pair(next_received), expected_complete,
            max_payload_bytes)

def payload.total.sums(
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  received: Nat & Nat,
  chunk: Bytes.Bytes,
  chunk_bytes: Nat & Nat,
  expected_bytes: Nat & Nat,
  max_payload_bytes: Nat
) -> PayloadStep:
  match received:
    case (for_total, for_limit):
      match chunk_bytes:
        case (length_total, length_limit):
          match expected_bytes:
            case (expected_total, expected_limit):
              payload.total.result(header, chunks, chunk,
                Nat.add(for_total, length_total),
                Protocol.nat.duplicate.pair(expected_total),
                max_payload_bytes,
                Nat.is_le(Nat.add(for_limit, length_limit), expected_limit))

def payload.total(
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: Nat,
  chunk: Bytes.Bytes,
  chunk_bytes: Nat,
  expected_bytes: U32,
  max_payload_bytes: Nat
) -> PayloadStep:
  payload.total.sums(header, chunks,
    Protocol.nat.duplicate.pair(received_bytes), chunk,
    Protocol.nat.duplicate.pair(chunk_bytes),
    Protocol.nat.duplicate.pair(U32.to_nat(expected_bytes)),
    max_payload_bytes)

def payload.measured(
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: Nat,
  expected_bytes: U32,
  max_payload_bytes: Nat,
  measured: Bytes.Bytes & U32
) -> PayloadStep:
  match measured:
    case (retained_chunk, chunk_bytes):
      payload.total(header, chunks, received_bytes, retained_chunk,
        U32.to_nat(chunk_bytes), expected_bytes, max_payload_bytes)

def payload.step(
  header: Bytes.Bytes,
  chunks: List<&1, Bytes.Bytes>,
  received_bytes: Nat,
  chunk: Bytes.Bytes,
  expected_bytes: U32,
  max_payload_bytes: Nat
) -> PayloadStep:
  payload.measured(header, chunks, received_bytes, expected_bytes,
    max_payload_bytes, Bytes.length(chunk))
