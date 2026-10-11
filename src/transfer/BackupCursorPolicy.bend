import Base
import ../coordinator/QueuePolicy.bend as QueuePolicy

# Reports whether one item is buffered, completes a block, or exceeds bounds.
type AppendDecision is Data:
  CursorBuffer{seen: Nat, pending: Nat}
  CursorBlockReady{seen: Nat, pending: Nat}
  CursorRejected{}

# Reports footer readiness, a final partial block, or an invalid end count.
type FinishDecision is Data:
  CursorFooter{}
  CursorFinalBlock{pending: Nat}
  CursorFinishRejected{}

def block.index.next(index: Nat) -> Nat:
  Nat.add(index, 1n)

# Selects buffering, a full block, or rejection after the count check.
def append.capacity(seen: Nat, pending: Nat) -> AppendDecision:
  match pending:
    case 0n: CursorBuffer{Nat.add(seen, 1n), 1n}
    case 1n+rest:
      match rest:
        case 14n: CursorBlockReady{Nat.add(seen, 1n), 16n}
        case 15n+more: CursorRejected{}
        case _: CursorBuffer{Nat.add(seen, 1n), Nat.add(pending, 1n)}

def append.checked(
  seen: Nat,
  pending: Nat,
  within_expected_count: Bool
) -> AppendDecision:
  match within_expected_count:
    case True{}: append.capacity(seen, pending)
    case False{}: CursorRejected{}

def append.copies(
  seen: Nat & Nat,
  pending: Nat,
  expected: Nat
) -> AppendDecision:
  match seen:
    case (output, checked):
      append.checked(output, pending, Nat.is_lt(checked, expected))

# Adds one cursor item without exceeding the declared total or block capacity.
def append(seen: Nat, pending: Nat, expected: Nat) -> AppendDecision:
  append.copies(QueuePolicy.nat.clone.pair(seen), pending, expected)

def finish.buffer(pending: Nat) -> FinishDecision:
  match pending:
    case 0n: CursorFooter{}
    case 1n+rest: CursorFinalBlock{pending}

def finish.pending(pending: Nat, count_matches: Bool) -> FinishDecision:
  match count_matches:
    case False{}: CursorFinishRejected{}
    case True{}: finish.buffer(pending)

# Emits a partial final block only after the cursor returned its exact count.
def finish(seen: Nat, expected: Nat, pending: Nat) -> FinishDecision:
  finish.pending(pending, Nat.is_eq(seen, expected))
