import Base

# Stores exact visible record and payload totals.
type Stats is Data:
  Stats{entries: Nat, payload_bytes: Nat}

# Reports a deterministic aggregate after one logical key mutation.
type Decision is Data:
  Applied{stats: Stats}

# Adds a previously absent live key and its encoded payload.
def added(current: Stats, key_bytes: Nat, value_bytes: Nat) -> Decision:
  match current:
    case Stats{entries, payload_bytes}:
      Applied{Stats{Nat.add(entries, 1n),
        Nat.add(payload_bytes, Nat.add(key_bytes, value_bytes))}}

# Preserves totals when a mutation leaves a key absent.
def unchanged(current: Stats) -> Decision:
  Applied{current}

# Removes one visible key, its key bytes, and its old value bytes.
def removed(current: Stats, key_bytes: Nat, value_bytes: Nat) -> Decision:
  match current:
    case Stats{entries, payload_bytes}:
      Applied{Stats{Nat.sub(entries, 1n),
        Nat.sub(payload_bytes, Nat.add(key_bytes, value_bytes))}}

# Replaces a value without changing the visible key count.
def replaced(current: Stats, old_bytes: Nat, new_bytes: Nat) -> Decision:
  match current:
    case Stats{entries, payload_bytes}:
      Applied{Stats{entries, Nat.add(Nat.sub(payload_bytes, old_bytes), new_bytes)}}

# Applies the visible effect of one key's before and after states.
def apply(
  current: Stats,
  key_bytes: Nat,
  before: Maybe<&1, Nat>,
  after: Maybe<&1, Nat>
) -> Decision:
  match before:
    case None{}:
      match after:
        case None{}: unchanged(current)
        case Some{new_bytes}: added(current, key_bytes, new_bytes)
    case Some{old_bytes}:
      match after:
        case None{}: removed(current, key_bytes, old_bytes)
        case Some{new_bytes}: replaced(current, old_bytes, new_bytes)

# Projects aggregate totals from a successful mutation decision.
def result(decision: Decision) -> Stats:
  match decision:
    case Applied{stats}: stats

def clone.nat(+value: Nat) -> Nat & Nat:
  (Nat.mul(1n, value), Nat.mul(1n, value))

def clone.fields(
  entries: Nat & Nat,
  payload_bytes: Nat & Nat
) -> Stats & Stats:
  match entries:
    case (entries_left, entries_right):
      match payload_bytes:
        case (payload_left, payload_right):
          (Stats{entries_left, payload_left}, Stats{entries_right, payload_right})

# Rebuilds independent copies of the exact aggregate totals.
def clone(+stats: Stats) -> Stats & Stats:
  match stats:
    case Stats{+entries, +payload_bytes}:
      clone.fields(clone.nat(entries), clone.nat(payload_bytes))
