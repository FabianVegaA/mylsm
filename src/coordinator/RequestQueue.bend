import Base
import ./QueuePolicy.bend as Policy
import ./Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Owns one accepted coordinator request until dispatch or rejection.
type Pending is Type:
  Pending{connection_id: U32, accepted_sequence: Nat,
    deadline_ms: Nat, encoded_bytes: Nat, response_peak: Nat,
    request: Protocol.Request}

# Carries the state for Queue.
type Queue is Type:
  Queue{front: List<&1, Pending>, back: List<&1, Pending>,
    count: Nat, bytes: Nat}

# Carries the state for Admission.
type Admission is Type:
  Enqueued{queue: Queue}
  Rejected{queue: Queue, pending: Pending, reason: Policy.Rejection}

# Carries the state for TakeResult.
type TakeResult is Type:
  Empty{queue: Queue}
  Taken{queue: Queue, pending: Pending}

# Carries the state for HeadMetadata.
type HeadMetadata is Data:
  HeadMetadata{connection_id: U32, accepted_sequence: Nat,
    deadline_ms: Nat, opcode: U32, request_bytes: Nat,
    response_peak: Nat}

# Carries the state for PeekResult.
type PeekResult is Type:
  PeekResult{queue: Queue, head: Maybe<&2, HeadMetadata>}

# Carries the state for CursorPeek.
type CursorPeek is Type:
  CursorPeek{queue: Queue, cursor_id: Maybe<&2, U32>,
    connection_id: U32}

# Carries the state for CancelResult.
type CancelResult is Type:
  CancelResult{queue: Queue, cancelled: List<&1, Pending>,
    count: Nat, bytes: Nat}

# Carries the state for CancelDisposition.
type CancelDisposition is Type:
  Retained{pending: Pending}
  Cancelled{pending: Pending}

# Carries the state for CancelFold.
type CancelFold is Type:
  CancelFold{kept: List<&1, Pending>,
    cancelled: List<&1, Pending>, count: Nat, bytes: Nat}

# Handles empty.
def empty() -> Queue:
  Queue{Nil{}, Nil{}, 0n, 0n}

def u32.clone.pair(+value: U32) -> U32 & U32:
  (value, value)

def active.counted(
  front: List<&1, Pending>,
  back: List<&1, Pending>,
  bytes: Nat,
  counts: Nat & Nat
) -> Queue & Bool:
  match counts:
    case (checked_count, retained_count):
      (Queue{front, back, retained_count, bytes},
        Nat.is_lt(0n, checked_count))

# Handles active.
def active(queue: Queue) -> Queue & Bool:
  match queue:
    case Queue{front, back, +count, bytes}:
      active.counted(front, back, bytes,
        Policy.nat.clone.pair(count))

def reverse.into(
  remaining: List<&1, Pending>,
  output: List<&1, Pending>
) -> List<&1, Pending>:
  match remaining:
    case Nil{}: output
    case Con{item, tail}:
      reverse.into(tail, Con{item, output})

def pending.size(pending: Pending) -> Pending & Nat:
  match pending:
    case Pending{connection_id, accepted_sequence, deadline_ms,
      +encoded_bytes, response_peak, request}:
      (Pending{connection_id, accepted_sequence, deadline_ms,
        encoded_bytes, response_peak, request}, encoded_bytes)

def enqueue.accepted(
  queue: Queue,
  pending: Pending,
  count: Nat,
  bytes: Nat
) -> Admission:
  match queue:
    case Queue{front, back, _, _}:
      Enqueued{Queue{front, Con{pending, back}, count, bytes}}

def enqueue.result(
  queue: Queue,
  pending: Pending,
  decision: Policy.Admission
) -> Admission:
  match decision:
    case Policy.Enqueued{Policy.Occupancy{count, bytes}}:
      enqueue.accepted(queue, pending, count, bytes)
    case Policy.Rejected{_, reason}:
      Rejected{queue, pending, reason}

def queue.metrics(queue: Queue) -> Queue & Nat & Nat:
  match queue:
    case Queue{front, back, +count, +bytes}:
      (Queue{front, back, count, bytes}, count, bytes)

def enqueue.with.metrics(
  pending: Pending,
  request_bytes: Nat,
  limits: Nat & Nat,
  metrics: Queue & Nat & Nat
) -> Admission:
  match limits:
    case (max_count, max_bytes):
      match metrics:
        case (retained_queue, (count, bytes)):
          enqueue.result(retained_queue, pending,
            Policy.admit.state(Policy.Occupancy{count, bytes},
              request_bytes, max_count, max_bytes))

def enqueue.measured(
  queue: Queue,
  measured: Pending & Nat,
  limits: Nat & Nat
) -> Admission:
  match measured:
    case (pending, request_bytes):
      enqueue.with.metrics(pending, request_bytes, limits,
        queue.metrics(queue))

# Handles enqueue.
def enqueue(
  queue: Queue,
  pending: Pending,
  max_count: Nat,
  max_bytes: Nat
) -> Admission:
  enqueue.measured(queue, pending.size(pending), (max_count, max_bytes))

def take.front(
  front: List<&1, Pending>,
  back: List<&1, Pending>,
  count: Nat,
  bytes: Nat
) -> TakeResult:
  match front:
    case Nil{}: Empty{Queue{Nil{}, back, count, bytes}}
    case Con{item, tail}:
      match item:
        case Pending{connection_id, accepted_sequence, deadline_ms,
          +encoded_bytes, response_peak, request}:
          Taken{
            Queue{tail, back, Nat.sub(count, 1n),
              Nat.sub(bytes, encoded_bytes)},
            Pending{connection_id, accepted_sequence, deadline_ms,
              encoded_bytes, response_peak, request}}

# Handles take.
def take(queue: Queue) -> TakeResult:
  match queue:
    case Queue{front, back, count, bytes}:
      match front:
        case Nil{}:
          match back:
            case Nil{}: Empty{Queue{Nil{}, Nil{}, count, bytes}}
            case Con{_, _}:
              take.front(reverse.into(back, Nil{}), Nil{}, count, bytes)
        case Con{_, _}: take.front(front, back, count, bytes)

def request.opcode.copies(
  version: U32,
  generation: U32,
  request_id: U32,
  payload: Bytes.Bytes,
  copies: U32 & U32 & U32
) -> Protocol.Request & U32:
  match copies:
    case (metadata_opcode, (request_opcode, _)):
      (Protocol.Request{version, generation, request_id, request_opcode,
        payload}, metadata_opcode)

def request.opcode.copy(request: Protocol.Request)
  -> Protocol.Request & U32:
  match request:
    case Protocol.Request{version, generation, request_id, +operation,
      payload}:
      request.opcode.copies(version, generation, request_id, payload,
        Protocol.u32.duplicate.triple(operation))

def pending.head.metadata.values(
  ids: U32 & U32,
  sequences: Nat & Nat,
  deadlines: Nat & Nat,
  byte_counts: Nat & Nat,
  peak_counts: Nat & Nat,
  request_pair: Protocol.Request & U32
) -> Pending & HeadMetadata:
  match ids:
    case (pending_id, metadata_id):
      match sequences:
        case (pending_sequence, metadata_sequence):
          match deadlines:
            case (pending_deadline, metadata_deadline):
              match byte_counts:
                case (pending_bytes, metadata_bytes):
                  match peak_counts:
                    case (pending_peak, metadata_peak):
                      match request_pair:
                        case (request, opcode):
                          (Pending{pending_id, pending_sequence,
                            pending_deadline, pending_bytes, pending_peak,
                            request},
                            HeadMetadata{metadata_id, metadata_sequence,
                              metadata_deadline, opcode, metadata_bytes,
                              metadata_peak})

def pending.head.metadata(pending: Pending)
  -> Pending & HeadMetadata:
  match pending:
    case Pending{connection_id, accepted_sequence, deadline_ms,
      encoded_bytes, response_peak, request}:
      pending.head.metadata.values(u32.clone.pair(connection_id),
        Policy.nat.clone.pair(accepted_sequence),
        Policy.nat.clone.pair(deadline_ms),
        Policy.nat.clone.pair(encoded_bytes),
        Policy.nat.clone.pair(response_peak),
        request.opcode.copy(request))

def peek.front.head(
  tail: List<&1, Pending>,
  back: List<&1, Pending>,
  count: Nat,
  bytes: Nat,
  pair: Pending & HeadMetadata
) -> PeekResult:
  match pair:
    case (retained, metadata):
      PeekResult{Queue{Con{retained, tail}, back, count, bytes},
        Some{metadata}}

def peek.front(
  front: List<&1, Pending>,
  back: List<&1, Pending>,
  count: Nat,
  bytes: Nat
) -> PeekResult:
  match front:
    case Nil{}:
      PeekResult{Queue{front, back, count, bytes}, None{}}
    case Con{pending, tail}:
      peek.front.head(tail, back, count, bytes,
        pending.head.metadata(pending))

# Handles peek.
def peek(queue: Queue) -> PeekResult:
  match queue:
    case Queue{front, back, count, bytes}:
      match front:
        case Nil{}:
          match back:
            case Nil{}: PeekResult{Queue{Nil{}, Nil{}, count, bytes}, None{}}
            case Con{_, _}:
              peek.front(reverse.into(back, Nil{}), Nil{}, count, bytes)
        case Con{_, _}: peek.front(front, back, count, bytes)

def request.cursor.identifier.read(
  version: U32,
  generation: U32,
  request_id: U32,
  pair: Bytes.Bytes & Maybe<&2, U32>
) -> Protocol.Request & Maybe<&2, U32>:
  match pair:
    case (payload, cursor_id):
      (Protocol.Request{version, generation, request_id, 13, payload},
        cursor_id)

def request.cursor.identifier(request: Protocol.Request)
  -> Protocol.Request & Maybe<&2, U32>:
  match request:
    case Protocol.Request{version, generation, request_id, operation,
        payload}:
      match operation:
        case 13:
          request.cursor.identifier.read(version, generation, request_id,
            Bytes.get.u32be(payload, 0))
        case opcode:
          (Protocol.Request{version, generation, request_id, opcode,
            payload}, None{})

def peek.cursor.front.request(
  pair: Protocol.Request & Maybe<&2, U32>,
  +connection_id: U32,
  accepted_sequence: Nat,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  response_peak: Nat,
  tail: List<&1, Pending>,
  back: List<&1, Pending>,
  count: Nat,
  bytes: Nat
) -> CursorPeek:
  match pair:
    case (retained_request, cursor_id):
      CursorPeek{Queue{Con{Pending{connection_id, accepted_sequence,
        deadline_ms, encoded_bytes, response_peak, retained_request},
        tail}, back, count, bytes}, cursor_id, connection_id}

def peek.cursor.front(
  pending: Pending,
  tail: List<&1, Pending>,
  back: List<&1, Pending>,
  count: Nat,
  bytes: Nat
) -> CursorPeek:
  match pending:
    case Pending{connection_id, accepted_sequence, deadline_ms,
        encoded_bytes, response_peak, request}:
      peek.cursor.front.request(request.cursor.identifier(request),
        connection_id, accepted_sequence, deadline_ms, encoded_bytes,
        response_peak, tail, back, count, bytes)

def peek.cursor.normalized(queue: Queue) -> CursorPeek:
  match queue:
    case Queue{front, back, count, bytes}:
      match front:
        case Nil{}: CursorPeek{Queue{front, back, count, bytes}, None{}, 0}
        case Con{pending, tail}:
          peek.cursor.front(pending, tail, back, count, bytes)

def peek.cursor.result(result: PeekResult) -> CursorPeek:
  match result:
    case PeekResult{queue, _}: peek.cursor.normalized(queue)

def peek.cursor(queue: Queue) -> CursorPeek:
  peek.cursor.result(peek(queue))

def head.peak(queue: Queue, peak: Nat) -> Queue:
  match queue:
    case Queue{front, back, count, bytes}:
      match front:
        case Nil{}: Queue{Nil{}, back, count, bytes}
        case Con{pending, tail}:
          match pending:
            case Pending{connection_id, accepted_sequence, deadline_ms,
                encoded_bytes, _, request}:
              Queue{Con{Pending{connection_id, accepted_sequence,
                deadline_ms, encoded_bytes, peak, request}, tail}, back,
                count, bytes}


# Handles append.
def append(left: List<&1, Pending>, right: List<&1, Pending>) -> List<&1, Pending>:
  match left:
    case Nil{}: right
    case Con{item, tail}: Con{item, append(tail, right)}

def cancel.disposition(
  pending: Pending,
  matches: Bool
) -> CancelDisposition:
  match matches:
    case True{}: Cancelled{pending}
    case False{}: Retained{pending}

def pending.cancel.disposition.id(
  copies: U32 & U32,
  accepted_sequence: Nat,
  deadline_ms: Nat,
  encoded_bytes: Nat,
  response_peak: Nat,
  request: Protocol.Request,
  +target: U32
) -> CancelDisposition:
  match copies:
    case (connection_id, comparison_id):
      cancel.disposition(
        Pending{connection_id, accepted_sequence, deadline_ms,
          encoded_bytes, response_peak, request},
        U32.is_eq(target, comparison_id))

def pending.cancel.disposition(
  +target: U32,
  pending: Pending
) -> CancelDisposition:
  match pending:
    case Pending{connection_id, accepted_sequence, deadline_ms,
      encoded_bytes, response_peak, request}:
      pending.cancel.disposition.id(u32.clone.pair(connection_id),
        accepted_sequence, deadline_ms, encoded_bytes, response_peak,
        request, target)

def cancel.fold.retained(
  state: CancelFold,
  measured: Pending & Nat
) -> CancelFold:
  match state:
    case CancelFold{kept, cancelled, count, bytes}:
      match measured:
        case (pending, size):
          CancelFold{Con{pending, kept}, cancelled,
            Nat.add(count, 1n), Nat.add(bytes, size)}

def cancel.fold.cancelled(
  state: CancelFold,
  pending: Pending
) -> CancelFold:
  match state:
    case CancelFold{kept, cancelled, count, bytes}:
      CancelFold{kept, Con{pending, cancelled}, count, bytes}

def cancel.fold.add(
  state: CancelFold,
  disposition: CancelDisposition
) -> CancelFold:
  match disposition:
    case Retained{pending}:
      cancel.fold.retained(state, pending.size(pending))
    case Cancelled{pending}: cancel.fold.cancelled(state, pending)

def cancel.fold.loop(
  entries: List<&1, Pending>,
  +target: U32,
  state: CancelFold
) -> CancelFold:
  match entries:
    case Nil{}: state
    case Con{pending, rest}:
      cancel.fold.loop(rest, target,
        cancel.fold.add(state, pending.cancel.disposition(target, pending)))

def cancel.result.values(
  kept: List<&1, Pending>,
  cancelled: List<&1, Pending>,
  counts: Nat & Nat,
  byte_counts: Nat & Nat
) -> CancelResult:
  match counts:
    case (queue_count, result_count):
      match byte_counts:
        case (queue_bytes, result_bytes):
          CancelResult{
            Queue{reverse.into(kept, Nil{}), Nil{}, queue_count, queue_bytes},
            reverse.into(cancelled, Nil{}), result_count, result_bytes}

def cancel.result(state: CancelFold) -> CancelResult:
  match state:
    case CancelFold{kept, cancelled, count, bytes}:
      cancel.result.values(kept, cancelled,
        Policy.nat.clone.pair(count), Policy.nat.clone.pair(bytes))

# Handles cancel connection.
def cancel_connection(queue: Queue, target: U32) -> CancelResult:
  match queue:
    case Queue{front, back, _, _}:
      cancel.result(cancel.fold.loop(
        append(front, reverse.into(back, Nil{})), target,
        CancelFold{Nil{}, Nil{}, 0n, 0n}))

def cancelled.discard(entries: List<&1, Pending>) -> Unit:
  match entries:
    case Nil{}: Unit{}
    case Con{pending, rest}:
      match pending:
        case Pending{_, _, _, _, _, _}: cancelled.discard(rest)
