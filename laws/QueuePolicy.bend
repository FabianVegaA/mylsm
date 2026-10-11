import Base
import ../src/coordinator/QueuePolicy.bend as Policy

# Accepts a request that fills both configured limits exactly.
law exact_queue_capacity_is_accepted:
  {Policy.admit(3n, 12n, 4n, 4n, 16n) == Policy.Accepted{4n, 16n} : Policy.Decision}

# Rejects admission when all queue slots are occupied.
law count_saturation_is_rejected:
  {Policy.admit(4n, 12n, 1n, 4n, 16n) == Policy.QueueFull{} : Policy.Decision}

# Rejects a request that would exceed the queued-byte budget.
law byte_saturation_is_rejected:
  {Policy.admit(3n, 16n, 1n, 4n, 16n) == Policy.QueueFull{} : Policy.Decision}

# Separates one oversized request from queue saturation.
law oversized_request_is_distinguished:
  {Policy.admit(0n, 0n, 17n, 4n, 16n) == Policy.RequestTooLarge{} : Policy.Decision}

# Successful admission updates both occupancy counters.
law stateful_admission_records_the_new_occupancy:
  {Policy.admit.state(Policy.Occupancy{3n, 12n}, 4n, 4n, 16n) ==
    Policy.Enqueued{Policy.Occupancy{4n, 16n}} : Policy.Admission}

# Count saturation preserves the exact state and identifies queue pressure.
law count_saturation_preserves_state:
  {Policy.admit.state(Policy.Occupancy{4n, 12n}, 1n, 4n, 16n) ==
    Policy.Rejected{Policy.Occupancy{4n, 12n}, Policy.Saturated{}} : Policy.Admission}

# Byte saturation preserves the exact state and identifies queue pressure.
law byte_saturation_preserves_state:
  {Policy.admit.state(Policy.Occupancy{3n, 16n}, 1n, 4n, 16n) ==
    Policy.Rejected{Policy.Occupancy{3n, 16n}, Policy.Saturated{}} : Policy.Admission}

# An oversized request preserves occupancy and reports its distinct failure.
law oversized_request_preserves_state:
  {Policy.admit.state(Policy.Occupancy{0n, 0n}, 17n, 4n, 16n) ==
    Policy.Rejected{Policy.Occupancy{0n, 0n}, Policy.Oversized{}} : Policy.Admission}

# Both copies returned for every natural number equal the original value.
law nat_clone_pair_preserves_both_values:
  for value: Nat
  {Policy.nat.clone.pair(value) == (value, value) : Nat & Nat}
