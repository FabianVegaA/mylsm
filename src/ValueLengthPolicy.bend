import Base
import ./scan/VisibleStats.bend as VisibleStats

# Carries the state for Outcome.
type Outcome is Data:
  ValueFound{}
  ValueMissing{}
  LookupFailed{}

# Handles after lookup.
def after_lookup(
  base_stats: VisibleStats.Stats,
  outcome: Outcome
) -> VisibleStats.Stats:
  match outcome:
    case ValueFound{}: base_stats
    case ValueMissing{}: base_stats
    case LookupFailed{}: base_stats
