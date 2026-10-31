import Base
import ./RequestQueue.bend as RequestQueue
import ./Protocol.bend as Protocol

# Carries the state for DispatchReservation.
type DispatchReservation is Type:
  DispatchReservation{connection_id: U32, request_bytes: Nat,
    payload_limit: U32, peak_bytes: Nat}

# Carries the state for FrameReservation.
type FrameReservation is Type:
  FrameReservation{connection_id: U32, reserved_bytes: Nat}

# Carries the state for InFlight.
type InFlight is Type:
  ReservedRequest{reservation: DispatchReservation,
    request: Protocol.Request}
  DispatchedRequest{reservation: DispatchReservation}

# Carries the state for DispatchStart.
type DispatchStart is Type:
  DispatchStarted{flight: InFlight, request: Protocol.Request}
  DispatchAlreadyStarted{flight: InFlight}

# Carries the state for DispatchCompletion.
type DispatchCompletion is Type:
  DispatchCompleted{reservation: DispatchReservation,
    response: Protocol.Response}
  DispatchCompletionRejected{flight: InFlight,
    response: Protocol.Response}

# Carries the state for TxDecision.
type TxDecision is Data:
  Reserve{}
  WaitForCapacity{}
  Reject{}

# Carries the state for TxReservation.
type TxReservation is Data:
  TxReserved{used_bytes: Nat}
  TxWaiting{used_bytes: Nat}
  TxRejected{used_bytes: Nat}

# Carries the state for RxInterest.
type RxInterest is Data:
  ReadEnabled{}
  ReadPaused{}
  ClosePeer{}

# Carries the state for RxReservationDecision.
type RxReservationDecision is Data:
  ReserveFrame{reserved_bytes: Nat}
  WaitForFrameCredit{used_bytes: Nat}
  RejectFrame{used_bytes: Nat}


# Carries the state for BoundDecision.
type BoundDecision is Data:
  Bounded{payload_bytes: U32, peak_bytes: Nat}
  InvalidRequest{}
  TooLarge{}

# Carries the state for QueueDecision.
type QueueDecision is Data:
  KeepHead{}
  DispatchHead{}
  RejectHead{}
  ExpireHead{}

# Carries the state for CursorAdmissionDecision.
type CursorAdmissionDecision is Data:
  PrepareCursorNext{}
  WaitForEarlierCursorNext{}

# Carries the state for HeadPolicy.
type HeadPolicy is Data:
  HeadPolicy{fits_total: Bool, fits_available: Bool, expired: Bool}

# Carries the state for QueueReservation.
type QueueReservation is Type:
  QueueKeep{queue: RequestQueue.Queue}
  QueueDispatch{queue: RequestQueue.Queue}
  QueueReject{queue: RequestQueue.Queue}
  QueueExpire{queue: RequestQueue.Queue}

def tx.flight.start(flight: InFlight) -> DispatchStart:
  match flight:
    case ReservedRequest{reservation, request}:
      DispatchStarted{DispatchedRequest{reservation}, request}
    case flight: DispatchAlreadyStarted{flight}

def tx.flight.complete(
  flight: InFlight,
  response: Protocol.Response
) -> DispatchCompletion:
  match flight:
    case DispatchedRequest{reservation}:
      DispatchCompleted{reservation, response}
    case flight: DispatchCompletionRejected{flight, response}

def tx.flight.reserved(
  connection_id: U32,
  request_bytes: Nat,
  bound: BoundDecision,
  request: Protocol.Request
) -> InFlight:
  match bound:
    case Bounded{payload_limit, peak_bytes}:
      ReservedRequest{DispatchReservation{connection_id, request_bytes,
        payload_limit, peak_bytes}, request}
    case _:
      ReservedRequest{DispatchReservation{connection_id, request_bytes,
        0, 28n}, request}

def tx.frame.transfer(reservation: DispatchReservation) -> FrameReservation:
  match reservation:
    case DispatchReservation{connection_id, _, _, peak_bytes}:
      FrameReservation{connection_id, peak_bytes}

def tx.frame.control(connection_id: U32) -> FrameReservation:
  FrameReservation{connection_id, 0n}

def tx.frame.measure(reservation: FrameReservation)
  -> FrameReservation & Nat:
  match reservation:
    case FrameReservation{connection_id, +reserved_bytes}:
      (FrameReservation{connection_id, reserved_bytes}, reserved_bytes)

def slots.control.bytes(connections: Nat) -> Nat:
  Nat.mul(connections, 28n)

def slots.header.bytes(connections: Nat) -> Nat:
  Nat.mul(connections, 24n)

def tx.available(available: Bool) -> TxDecision:
  match available:
    case True{}: Reserve{}
    case False{}: WaitForCapacity{}

def tx.decide(fits_total: Bool, fits_available: Bool) -> TxDecision:
  match fits_total:
    case False{}: Reject{}
    case True{}: tx.available(fits_available)

def tx.request(+used: Nat, +required: Nat, +capacity: Nat) -> TxDecision:
  tx.decide(Nat.is_le(required, capacity),
    Nat.is_le(Nat.add(used, required), capacity))

def tx.reserve.result(
  +used: Nat,
  +required: Nat,
  decision: TxDecision
) -> TxReservation:
  match decision:
    case Reserve{}: TxReserved{Nat.add(used, required)}
    case WaitForCapacity{}: TxWaiting{used}
    case Reject{}: TxRejected{used}

def tx.reserve(+used: Nat, +required: Nat, +capacity: Nat) -> TxReservation:
  tx.reserve.result(used, required, tx.request(used, required, capacity))

def tx.get.peak(value_bytes: Nat) -> Nat:
  Nat.add(Nat.mul(2n, value_bytes), 28n)

def tx.capacity(response_bytes: U32) -> Nat:
  Nat.add(Nat.mul(2n, U32.to_nat(response_bytes)), 28n)

def tx.get.bound.peak(
  +value_bytes: Nat,
  peak_bytes: Nat,
  fits_capacity: Bool
) -> BoundDecision:
  match fits_capacity:
    case True{}: Bounded{U32.from_nat(value_bytes), peak_bytes}
    case False{}: TooLarge{}

def tx.get.bound.decided(
  fits_payload: Bool,
  +value_bytes: Nat,
  +capacity: Nat
) -> BoundDecision:
  match fits_payload:
    case False{}: TooLarge{}
    case True{}:
      tx.get.bound.peak(value_bytes,
        tx.get.peak(value_bytes),
        Nat.is_le(tx.get.peak(value_bytes), capacity))

def tx.get.bound(
  +value_bytes: U32,
  max_payload_bytes: U32,
  capacity: Nat
) -> BoundDecision:
  tx.get.bound.decided(U32.is_le(value_bytes, max_payload_bytes),
    U32.to_nat(value_bytes), capacity)

def tx.response.bound(+payload_bytes: U32) -> BoundDecision:
  Bounded{payload_bytes, tx.get.peak(U32.to_nat(payload_bytes))}

def tx.payload.bound.decided(
  +payload_bytes: Nat,
  fits: Bool
) -> BoundDecision:
  match fits:
    case False{}: TooLarge{}
    case True{}:
      Bounded{U32.from_nat(payload_bytes), tx.get.peak(payload_bytes)}

def tx.payload.bound(
  +payload_bytes: Nat,
  max_payload_bytes: U32
) -> BoundDecision:
  tx.payload.bound.decided(payload_bytes,
    Nat.is_le(payload_bytes, U32.to_nat(max_payload_bytes)))

def tx.nat.duplicate.step(pair: Nat & Nat) -> Nat & Nat:
  match pair:
    case (first, second): (Nat.add(1n, first), Nat.add(1n, second))

def tx.nat.duplicate(value: Nat) -> Nat & Nat:
  match value:
    case 0n: (0n, 0n)
    case 1n+rest: tx.nat.duplicate.step(tx.nat.duplicate(rest))

def tx.u32.duplicate.from.nat(copies: Nat & Nat) -> U32 & U32:
  match copies:
    case (first, second): (U32.from_nat(first), U32.from_nat(second))

def tx.u32.duplicate(value: U32) -> U32 & U32:
  tx.u32.duplicate.from.nat(tx.nat.duplicate(U32.to_nat(value)))

def tx.cursor.bound.payload(copies: Nat & Nat) -> BoundDecision:
  match copies:
    case (payload_bytes, peak_bytes):
      Bounded{U32.from_nat(payload_bytes), tx.get.peak(peak_bytes)}

def tx.cursor.bound.measured(
  +required_bytes: Nat,
  fits: Bool
) -> BoundDecision:
  match fits:
    case False{}: TooLarge{}
    case True{}:
      tx.cursor.bound.payload(tx.nat.duplicate(required_bytes))

def tx.cursor.bound.required(
  copies: Nat & Nat,
  response_copies: U32 & U32
) -> BoundDecision:
  match copies:
    case (check_bytes, required_bytes):
      match response_copies:
        case (response_for_check, _):
          tx.cursor.bound.measured(required_bytes,
            Nat.is_le(check_bytes, U32.to_nat(response_for_check)))

def tx.cursor.bound(+retained_bytes: Nat, response_bytes: U32) -> BoundDecision:
  tx.cursor.bound.required(tx.nat.duplicate(Nat.add(retained_bytes, 9n)),
    tx.u32.duplicate(response_bytes))

def tx.queue.eligible(decision: TxDecision) -> QueueDecision:
  match decision:
    case Reserve{}: DispatchHead{}
    case WaitForCapacity{}: KeepHead{}
    case Reject{}: RejectHead{}

def tx.cursor.admission(seen: Bool) -> CursorAdmissionDecision:
  match seen:
    case True{}: WaitForEarlierCursorNext{}
    case False{}: PrepareCursorNext{}

def tx.queue.decide(policy: HeadPolicy) -> QueueDecision:
  match policy:
    case HeadPolicy{fits_total, fits_available, expired}:
      match expired:
        case True{}: ExpireHead{}
        case False{}:
          tx.queue.eligible(tx.decide(fits_total, fits_available))

def tx.queue.reserved(
  queue: RequestQueue.Queue,
  decision: QueueDecision
) -> QueueReservation:
  match decision:
    case KeepHead{}: QueueKeep{queue}
    case DispatchHead{}: QueueDispatch{queue}
    case RejectHead{}: QueueReject{queue}
    case ExpireHead{}: QueueExpire{queue}

def tx.queue.reserve(
  queue: RequestQueue.Queue,
  policy: HeadPolicy
) -> QueueReservation:
  tx.queue.reserved(queue, tx.queue.decide(policy))

def tx.queue.decide.budget(
  +used: Nat,
  +required: Nat,
  +capacity: Nat,
  expired: Bool
) -> QueueDecision:
  match expired:
    case True{}: ExpireHead{}
    case False{}: tx.queue.eligible(tx.request(used, required, capacity))

def tx.queue.head.policy(
  head: Maybe<&2, RequestQueue.HeadMetadata>,
  +used: Nat,
  +capacity: Nat,
  now: Nat
) -> QueueDecision:
  match head:
    case None{}:
      tx.queue.decide.budget(used, 28n, capacity, False{})
    case Some{RequestQueue.HeadMetadata{_, _, deadline_ms, _, _,
        response_peak}}:
      tx.queue.decide.budget(used, response_peak, capacity,
        Nat.is_le(deadline_ms, now))

def tx.queue.reserve.peeked(
  result: RequestQueue.PeekResult,
  +used: Nat,
  +capacity: Nat,
  now: Nat
) -> QueueReservation:
  match result:
    case RequestQueue.PeekResult{queue, head}:
      tx.queue.reserved(queue, tx.queue.head.policy(head, used, capacity, now))

def rx.live(owns_credit: Bool) -> RxInterest:
  match owns_credit:
    case True{}: ReadEnabled{}
    case False{}: ReadPaused{}

def rx.interest(terminal: Bool, owns_credit: Bool) -> RxInterest:
  match terminal:
    case True{}: ClosePeer{}
    case False{}: rx.live(owns_credit)

def rx.frame.peak(payload_bytes: Nat) -> Nat:
  Nat.add(48n, Nat.mul(3n, payload_bytes))

def rx.frame.reservation(
  +used_bytes: Nat,
  +required_bytes: Nat,
  +_capacity_bytes: Nat,
  fits_total: Bool,
  fits_available: Bool
) -> RxReservationDecision:
  match fits_total:
    case False{}: RejectFrame{used_bytes}
    case True{}:
      match fits_available:
        case True{}: ReserveFrame{Nat.add(used_bytes, required_bytes)}
        case False{}: WaitForFrameCredit{used_bytes}

def rx.frame.reserve(
  +used_bytes: Nat,
  +required_bytes: Nat,
  +capacity_bytes: Nat
) -> RxReservationDecision:
  rx.frame.reservation(used_bytes, required_bytes, capacity_bytes,
    Nat.is_le(required_bytes, capacity_bytes),
    Nat.is_le(Nat.add(used_bytes, required_bytes), capacity_bytes))
