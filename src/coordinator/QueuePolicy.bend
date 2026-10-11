import Base

# Separates an oversized single request from temporary queue saturation.
type Decision is Data:
  Accepted{count: Nat, bytes: Nat}
  QueueFull{}
  RequestTooLarge{}

def nat.clone.pair(+value: Nat) -> Nat & Nat:
  (value, value)

def admit.total.pair(checked: Nat, output: Nat, max_queue_bytes: Nat) -> Bool & Nat:
  (Nat.is_le(checked, max_queue_bytes), output)

def admit.decision(count: Nat, within_request_limit: Bool, within_count: Bool, pair: Bool & Nat) -> Decision:
  match within_request_limit:
    case False{}: RequestTooLarge{}
    case True{}:
      match within_count:
        case False{}: QueueFull{}
        case True{}:
          match pair:
            case (False{}, _): QueueFull{}
            case (True{}, bytes): Accepted{Nat.add(count, 1n), bytes}

def admit.inputs(
  count: Nat,
  queued_pair: Nat & Nat,
  request_pair: Nat & Nat,
  max_queue_bytes: Nat,
  within_request_limit: Bool,
  within_count: Bool
) -> Decision:
  match queued_pair:
    case (queued_check, queued_output):
      match request_pair:
        case (request_check, request_output):
          admit.decision(count, within_request_limit, within_count,
            admit.total.pair(Nat.add(queued_check, request_check),
              Nat.add(queued_output, request_output), max_queue_bytes))

def admit.counted.request.check(
  count: Nat,
  checked_count: Nat,
  queued_bytes: Nat,
  request_output: Nat,
  max_count: Nat,
  checked_limit: Nat,
  output_limit: Nat,
  request_check_pair: Nat & Nat
) -> Decision:
  match request_check_pair:
    case (request_check, request_size_check):
      admit.inputs(count, nat.clone.pair(queued_bytes), (request_check, request_output), output_limit,
        Nat.is_le(request_size_check, checked_limit), Nat.is_lt(checked_count, max_count))

def admit.counted.requested(
  count: Nat,
  checked_count: Nat,
  queued_bytes: Nat,
  request_pair: Nat & Nat,
  max_count: Nat,
  limits: Nat & Nat
) -> Decision:
  match request_pair:
    case (request_check, request_output):
      match limits:
        case (checked_limit, output_limit):
          admit.counted.request.check(count, checked_count, queued_bytes, request_output,
            max_count, checked_limit, output_limit, nat.clone.pair(request_check))

def admit.counted.limits(
  pair: Nat & Nat,
  queued_bytes: Nat,
  request_bytes: Nat,
  max_count: Nat,
  limits: Nat & Nat
) -> Decision:
  match pair:
    case (count, checked_count):
      admit.counted.requested(count, checked_count, queued_bytes,
        nat.clone.pair(request_bytes), max_count, limits)

def admit.counted(
  pair: Nat & Nat,
  queued_bytes: Nat,
  request_bytes: Nat,
  max_count: Nat,
  max_queue_bytes: Nat
) -> Decision:
  admit.counted.limits(pair, queued_bytes, request_bytes, max_count, nat.clone.pair(max_queue_bytes))

# Computes bounded queue admission from the request size and current occupancy.
def admit(
  count: Nat,
  queued_bytes: Nat,
  request_bytes: Nat,
  max_count: Nat,
  max_queue_bytes: Nat
) -> Decision:
  admit.counted(nat.clone.pair(count), queued_bytes, request_bytes, max_count, max_queue_bytes)
