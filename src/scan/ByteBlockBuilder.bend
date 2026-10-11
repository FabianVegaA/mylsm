import Base

# Selects appending, rollover, or rejection for an exact byte-record size.
type Decision is Data:
  Append{used_bytes: Nat}
  StartNextBlock{record_bytes: Nat}
  RecordTooLarge{}

def nat.clone.pair(+value: Nat) -> Nat & Nat:
  (Nat.mul(1n, value), Nat.mul(1n, value))

def decide.rollover(record_bytes: Nat, current_empty: Bool) -> Decision:
  match current_empty:
    case True{}: RecordTooLarge{}
    case False{}: StartNextBlock{record_bytes}

# Chooses whether a record fits the current block without exceeding its cap.
def decide.current(
  used_bytes: Nat,
  record_bytes: Nat,
  fits_current: Bool
) -> Decision:
  match fits_current:
    case True{}: Append{Nat.add(used_bytes, record_bytes)}
    case False{}:
      decide.rollover(record_bytes, Nat.is_eq(used_bytes, 0n))

def decide.sized.limits(
  +used_bytes: Nat,
  +record_bytes: Nat,
  limits: Nat & Nat,
  record_fits: Bool
) -> Decision:
  match limits:
    case (current_cap, comparison_cap):
      match record_fits:
        case False{}: RecordTooLarge{}
        case True{}:
          decide.current(used_bytes, record_bytes,
            Nat.is_le(Nat.add(used_bytes, record_bytes), comparison_cap))

# Rejects a record above the block cap before considering current occupancy.
def decide.sized(
  used_bytes: Nat,
  record_bytes: Nat,
  max_bytes: Nat,
  record_fits: Bool
) -> Decision:
  decide.sized.limits(used_bytes, record_bytes, nat.clone.pair(max_bytes), record_fits)

def decide.with.max(
  used_bytes: Nat,
  +record_bytes: Nat,
  limits: Nat & Nat
) -> Decision:
  match limits:
    case (record_cap, block_cap):
      decide.sized(used_bytes, record_bytes, block_cap,
        Nat.is_le(record_bytes, record_cap))

# Admits, rolls over, or rejects one record using byte-exact limits.
def decide(used_bytes: Nat, record_bytes: Nat, max_bytes: Nat) -> Decision:
  decide.with.max(used_bytes, record_bytes, nat.clone.pair(max_bytes))
