import Base
import ../src/coordinator/RequestQueue.bend as Queue
import ../src/coordinator/Protocol.bend as Protocol
import ../src/coordinator/QueuePolicy.bend as Policy
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Verifies replacing head peak preserves fifo ownership and deadline.
law replacing_head_peak_preserves_fifo_ownership_and_deadline:
  for connection_id: U32
  for sequence: Nat
  for deadline: Nat
  for request_bytes: Nat
  for old_peak: Nat
  for new_peak: Nat
  for request: Protocol.Request
  for tail: List<&1, Queue.Pending>
  for back: List<&1, Queue.Pending>
  for count: Nat
  for bytes: Nat
  {Queue.head.peak(Queue.Queue{
    Con{Queue.Pending{connection_id, sequence, deadline, request_bytes,
      old_peak, request}, tail}, back, count, bytes}, new_peak) ==
    Queue.Queue{Con{Queue.Pending{connection_id, sequence, deadline,
      request_bytes, new_peak, request}, tail}, back, count, bytes} :
    Queue.Queue}

# Verifies cursor head exposes only the next cursor identifier.
law cursor_head_exposes_only_the_next_cursor_identifier:
  {Queue.peek.cursor(Queue.Queue{Con{Queue.Pending{3, 4n, 5n, 28n,
    36n, Protocol.Request{1, 1, 7, 13,
      Bytes.set.u32be(Bytes.new(4), 0, 11)}}, Nil{}}, Nil{}, 1n,
      28n}) == Queue.CursorPeek{Queue.Queue{
        Con{Queue.Pending{3, 4n, 5n, 28n, 36n,
          Protocol.Request{1, 1, 7, 13,
            Bytes.set.u32be(Bytes.new(4), 0, 11)}}, Nil{}},
        Nil{}, 1n, 28n}, Some{11}, 3} : Queue.CursorPeek}

# Verifies empty queue has no request.
law empty_queue_has_no_request:
  {Queue.take(Queue.empty()) == Queue.Empty{Queue.empty()} : Queue.TakeResult}

# Verifies empty queue has no active dispatch.
law empty_queue_has_no_active_dispatch:
  {Queue.active(Queue.empty()) == (Queue.empty(), False{}) : Queue.Queue & Bool}


# Verifies admission enforces count limit.
law admission_enforces_count_limit:
  {Queue.enqueue(Queue.empty(),
    Queue.Pending{1, 1n, 10n, 3n,28n,  Protocol.Request{1, 1, 1, 0, Bytes.new(0)}},
    0n, 8n) == Queue.Rejected{Queue.empty(),
      Queue.Pending{1, 1n, 10n, 3n,28n,  Protocol.Request{1, 1, 1, 0, Bytes.new(0)}},
      Policy.Saturated{}} : Queue.Admission}

# Verifies admission enforces byte limit.
law admission_enforces_byte_limit:
  {Queue.enqueue(Queue.empty(),
    Queue.Pending{1, 1n, 10n, 9n,28n,  Protocol.Request{1, 1, 1, 0, Bytes.new(0)}},
    4n, 8n) == Queue.Rejected{Queue.empty(),
      Queue.Pending{1, 1n, 10n, 9n,28n,  Protocol.Request{1, 1, 1, 0, Bytes.new(0)}},
      Policy.Oversized{}} : Queue.Admission}

# Verifies exact two request capacity rejects third 64 byte frame.
law exact_two_request_capacity_rejects_third_64_byte_frame:
  {Queue.enqueue(Queue.Queue{
    Con{Queue.Pending{1, 1n, 10n, 64n,28n,
      Protocol.Request{1, 1, 1, 2, Bytes.new(40)}},
    Con{Queue.Pending{2, 2n, 10n, 64n,28n,
      Protocol.Request{1, 1, 2, 2, Bytes.new(40)}}, Nil{}}}, Nil{}, 2n, 128n},
    Queue.Pending{3, 3n, 10n, 64n,28n,
      Protocol.Request{1, 1, 3, 2, Bytes.new(40)}}, 2n, 128n) ==
    Queue.Rejected{Queue.Queue{
      Con{Queue.Pending{1, 1n, 10n, 64n,28n,
        Protocol.Request{1, 1, 1, 2, Bytes.new(40)}},
      Con{Queue.Pending{2, 2n, 10n, 64n,28n,
        Protocol.Request{1, 1, 2, 2, Bytes.new(40)}}, Nil{}}}, Nil{}, 2n, 128n},
      Queue.Pending{3, 3n, 10n, 64n,28n,
        Protocol.Request{1, 1, 3, 2, Bytes.new(40)}},
      Policy.Saturated{}} : Queue.Admission}

# Verifies accepted request is taken first.
law accepted_request_is_taken_first:
  {Queue.take(Queue.Queue{Nil{},
    Con{Queue.Pending{1, 7n, 10n, 3n,28n,
      Protocol.Request{1, 1, 1, 0, Bytes.new(0)}}, Nil{}}, 1n, 3n}) ==
    Queue.Taken{Queue.empty(), Queue.Pending{1, 7n, 10n, 3n,28n,
      Protocol.Request{1, 1, 1, 0, Bytes.new(0)}}} : Queue.TakeResult}

# Verifies accepted request releases its accounted bytes.
law accepted_request_releases_its_accounted_bytes:
  {Queue.take(Queue.Queue{Nil{},
    Con{Queue.Pending{1, 7n, 10n, 3n,28n,
      Protocol.Request{1, 1, 1, 0, Bytes.new(0)}}, Nil{}}, 1n, 3n}) ==
    Queue.Taken{Queue.Queue{Nil{}, Nil{}, 0n, 0n}, Queue.Pending{1, 7n, 10n, 3n,28n,
      Protocol.Request{1, 1, 1, 0, Bytes.new(0)}}} : Queue.TakeResult}

# Verifies peeking keeps fifo head and queue ownership.
law peeking_keeps_fifo_head_and_queue_ownership:
  for connection_id: U32
  for accepted_sequence: Nat
  for deadline_ms: Nat
  for encoded_bytes: Nat
  for response_peak: Nat
  for payload: Bytes.Bytes
  for tail: List<&1, Queue.Pending>
  for back: List<&1, Queue.Pending>
  {Queue.peek(Queue.Queue{
    Con{Queue.Pending{connection_id, accepted_sequence, deadline_ms,
      encoded_bytes,response_peak, Protocol.Request{1, 1, 1, 7, payload}}, tail}, back,
    1n, encoded_bytes}) == Queue.PeekResult{
      Queue.Queue{Con{Queue.Pending{connection_id, accepted_sequence,
        deadline_ms, encoded_bytes,response_peak,
        Protocol.Request{1, 1, 1, 7, payload}}, tail}, back, 1n,
        encoded_bytes},
      Some{Queue.HeadMetadata{connection_id, accepted_sequence, deadline_ms,
        7, encoded_bytes, response_peak}}} : Queue.PeekResult}

# Verifies peeking normalizes back without reordering.
law peeking_normalizes_back_without_reordering:
  {Queue.peek(Queue.Queue{Nil{}, Con{
    Queue.Pending{2, 5n, 21n, 9n,28n,  Protocol.Request{1, 1, 9, 4,
      Bytes.new(3)}},
    Con{Queue.Pending{1, 4n, 20n, 6n,28n,  Protocol.Request{1, 1, 8, 7,
      Bytes.new(2)}}, Nil{}}}, 2n, 15n}) == Queue.PeekResult{
    Queue.Queue{Con{
      Queue.Pending{1, 4n, 20n, 6n,28n,  Protocol.Request{1, 1, 8, 7,
        Bytes.new(2)}},
      Con{Queue.Pending{2, 5n, 21n, 9n,28n,  Protocol.Request{1, 1, 9, 4,
        Bytes.new(3)}}, Nil{}}}, Nil{}, 2n, 15n},
    Some{Queue.HeadMetadata{1, 4n, 20n, 7, 6n, 28n}}} : Queue.PeekResult}

# Verifies cancellation preserves fifo and exact occupancy.
law cancellation_preserves_fifo_and_exact_occupancy:
  {Queue.cancel_connection(Queue.Queue{
    Con{Queue.Pending{1, 1n, 10n, 3n,28n,  Protocol.Request{1, 1, 1, 0, Bytes.new(0)}},
    Con{Queue.Pending{2, 2n, 10n, 5n,28n,  Protocol.Request{1, 1, 2, 0, Bytes.new(0)}},
    Con{Queue.Pending{1, 3n, 10n, 7n,28n,  Protocol.Request{1, 1, 3, 0, Bytes.new(0)}}, Nil{}}}},
    Nil{}, 3n, 15n}, 1) == Queue.CancelResult{
      Queue.Queue{Con{Queue.Pending{2, 2n, 10n, 5n,28n,
        Protocol.Request{1, 1, 2, 0, Bytes.new(0)}}, Nil{}}, Nil{}, 1n, 5n},
      Con{Queue.Pending{1, 1n, 10n, 3n,28n,  Protocol.Request{1, 1, 1, 0, Bytes.new(0)}},
        Con{Queue.Pending{1, 3n, 10n, 7n,28n,
          Protocol.Request{1, 1, 3, 0, Bytes.new(0)}}, Nil{}}}, 1n, 5n} :
      Queue.CancelResult}

# Verifies taking a front item preserves the remaining front and back.
law taking_a_front_item_preserves_the_remaining_front_and_back:
  for connection_id: U32
  for accepted_sequence: Nat
  for deadline_ms: Nat
  for encoded_bytes: Nat
  for request: Protocol.Request
  for tail: List<&1, Queue.Pending>
  for back: List<&1, Queue.Pending>
  for count: Nat
  for bytes: Nat
  {Queue.take.front(Con{Queue.Pending{connection_id, accepted_sequence,
      deadline_ms, encoded_bytes,28n,  request}, tail}, back, count, bytes) ==
    Queue.Taken{Queue.Queue{tail, back, Nat.sub(count, 1n),
      Nat.sub(bytes, encoded_bytes)},
      Queue.Pending{connection_id, accepted_sequence, deadline_ms,
        encoded_bytes,28n,  request}} : Queue.TakeResult}

# Verifies retained cancellation updates reverse accumulator and metrics.
law retained_cancellation_updates_reverse_accumulator_and_metrics:
  for kept: List<&1, Queue.Pending>
  for cancelled: List<&1, Queue.Pending>
  for count: Nat
  for bytes: Nat
  for pending: Queue.Pending
  for encoded_bytes: Nat
  {Queue.cancel.fold.retained(Queue.CancelFold{kept, cancelled, count, bytes},
      (pending, encoded_bytes)) ==
    Queue.CancelFold{Con{pending, kept}, cancelled, Nat.add(count, 1n),
      Nat.add(bytes, encoded_bytes)} : Queue.CancelFold}

# Verifies cancelled cancellation updates only cancelled accumulator.
law cancelled_cancellation_updates_only_cancelled_accumulator:
  for kept: List<&1, Queue.Pending>
  for cancelled: List<&1, Queue.Pending>
  for count: Nat
  for bytes: Nat
  for pending: Queue.Pending
  {Queue.cancel.fold.add(Queue.CancelFold{kept, cancelled, count, bytes},
      Queue.Cancelled{pending}) ==
    Queue.CancelFold{kept, Con{pending, cancelled}, count, bytes} :
      Queue.CancelFold}

# Verifies rejected admission preserves queue and pending.
law rejected_admission_preserves_queue_and_pending:
  for front: List<&1, Queue.Pending>
  for back: List<&1, Queue.Pending>
  for count: Nat
  for bytes: Nat
  for pending: Queue.Pending
  for rejected_count: Nat
  for rejected_bytes: Nat
  for reason: Policy.Rejection
  {Queue.enqueue.result(Queue.Queue{front, back, count, bytes}, pending,
      Policy.Rejected{Policy.Occupancy{rejected_count, rejected_bytes},
        reason}) ==
    Queue.Rejected{Queue.Queue{front, back, count, bytes}, pending, reason} :
      Queue.Admission}

# Verifies accepted admission preserves front and appends to back.
law accepted_admission_preserves_front_and_appends_to_back:
  for front: List<&1, Queue.Pending>
  for back: List<&1, Queue.Pending>
  for pending: Queue.Pending
  for count: Nat
  for bytes: Nat
  {Queue.enqueue.accepted(Queue.Queue{front, back, 0n, 0n}, pending,
      count, bytes) ==
    Queue.Enqueued{Queue.Queue{front, Con{pending, back}, count, bytes}} :
      Queue.Admission}
