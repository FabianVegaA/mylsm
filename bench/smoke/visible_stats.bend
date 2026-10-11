import Base
import ../../src/scan/VisibleStats.bend as VisibleStats

# Checks the count and byte totals after a value replacement.
def stats.valid(stats: VisibleStats.Stats) -> Bool:
  match stats:
    case VisibleStats.Stats{entries, payload_bytes}:
      Nat.is_eq(entries, 2n) && Nat.is_eq(payload_bytes, 20n)

# Reports whether the aggregate replacement oracle matched.
def verified.stats(valid: Bool) -> IO(Unit):
  match valid:
    case True{}: IO.print("VISIBLE_STATS_POLICY_PASSED")
    case False{}: IO.die(Unit, 1, "replacement changed the visible entry count")

# Runs one replacement against a fixed aggregate witness.
def verified(decision: VisibleStats.Decision) -> IO(Unit):
  match decision:
    case VisibleStats.Applied{stats}:
      verified.stats(stats.valid(stats))

def main() -> IO(Unit):
  verified(VisibleStats.apply(VisibleStats.Stats{2n, 17n}, 3n,
    Some{5n}, Some{8n}))
