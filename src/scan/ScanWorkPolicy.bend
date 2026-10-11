import Base
import ../coordinator/QueuePolicy.bend as QueuePolicy

# Bounds source reads by the base, delta, and one terminal observation.
def budget(base_records: Nat, delta_records: Nat) -> Nat:
  Nat.add(Nat.add(base_records, delta_records), 1n)

# Reserves writer transitions for every source read plus fixed finalization.
def writer_transitions(base_records: Nat, delta_records: Nat) -> Nat:
  Nat.add(Nat.mul(3n, budget(base_records, delta_records)), 8n)

def nat.clone.pair(value: Nat) -> Nat & Nat:
  QueuePolicy.nat.clone.pair(value)
