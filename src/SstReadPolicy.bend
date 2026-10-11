import Base
import ./coordinator/QueuePolicy.bend as QueuePolicy

# Classifies a single SST size against format and caller byte limits.
type Decision is Data:
  TooSmall{}
  WithinBudget{}
  OverBudget{}

# Carries the next aggregate byte total only when admission succeeds.
type TotalDecision is Data:
  TotalAdmitted{next_total: Nat}
  TotalRejected{}

# Accepts a table only when its size is within the configured file budget.
def within_budget(size: Nat, max_bytes: Nat) -> Bool:
  Nat.is_le(size, max_bytes)

def classify.copies(pair: Nat & Nat, max_bytes: Nat) -> Decision:
  match pair:
    case (minimum_check, budget_check):
      Bool.pick(Decision, Nat.is_le(60n, minimum_check),
        Bool.pick(Decision, within_budget(budget_check, max_bytes),
          WithinBudget{}, OverBudget{}), TooSmall{})

# Separates undersized corruption from a valid but oversized table.
def classify(size: Nat, max_bytes: Nat) -> Decision:
  classify.copies(QueuePolicy.nat.clone.pair(size), max_bytes)

def total.copies(
  totals: Nat & Nat,
  sizes: Nat & Nat,
  max_bytes: Nat
) -> TotalDecision:
  match totals:
    case (checked_total, next_total):
      match sizes:
        case (checked_size, next_size):
          Bool.pick(TotalDecision,
            Nat.is_le(Nat.add(checked_total, checked_size), max_bytes),
            TotalAdmitted{Nat.add(next_total, next_size)}, TotalRejected{})

# Checks a file against the remaining aggregate budget before decoding.
def total_decision(total: Nat, size: Nat, max_bytes: Nat) -> TotalDecision:
  total.copies(QueuePolicy.nat.clone.pair(total),
    QueuePolicy.nat.clone.pair(size), max_bytes)
