import Base
import ../src/scan/ScanWorkPolicy.bend as Policy

# Captures one final source read after exhausting both input sources.
law budget_covers_one_transition_per_source_record_and_terminal_read:
  {Policy.budget(3n, 2n) == 6n : Nat}

# Keeps the empty scan's terminal read in the computed budget.
law empty_sources_still_allow_terminal_read:
  {Policy.budget(0n, 0n) == 1n : Nat}

# Covers three state transitions per source observation and finalization.
law writer_budget_covers_source_and_output_transitions:
  {Policy.writer_transitions(3n, 2n) == 26n : Nat}
