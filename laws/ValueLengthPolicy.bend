import Base
import ../src/ValueLengthPolicy.bend as Policy
import ../src/scan/VisibleStats.bend as VisibleStats

# Verifies metadata lookup preserves base statistics.
law metadata_lookup_preserves_base_statistics:
  for base_stats: VisibleStats.Stats
  for outcome: Policy.Outcome
  {Policy.after_lookup(base_stats, outcome) == base_stats : VisibleStats.Stats}
