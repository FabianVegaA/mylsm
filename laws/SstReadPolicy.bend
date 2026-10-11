import Base
import ../src/SstReadPolicy.bend as Policy

# Rejects an SST one byte above its configured budget.
law over_budget_is_rejected:
  {Policy.within_budget(65n, 64n) == False{} : Bool}

# Accepts an SST exactly at its configured budget.
law exact_budget_is_accepted:
  {Policy.within_budget(64n, 64n) == True{} : Bool}

# Accepts an empty file budget only for an empty file.
law zero_budget_accepts_empty:
  {Policy.within_budget(0n, 0n) == True{} : Bool}

# Classifies a size below the valid SST envelope separately from budget excess.
law classifies_too_small:
  {Policy.classify(59n, 64n) == Policy.TooSmall{} : Policy.Decision}

# Classifies a valid-size file above the budget as a resource limit.
law classifies_over_budget:
  {Policy.classify(65n, 64n) == Policy.OverBudget{} : Policy.Decision}

# Admits another file only when the combined retained bytes fit the limit.
law aggregate_budget_accepts_boundary:
  {Policy.total_decision(32n, 32n, 64n) ==
    Policy.TotalAdmitted{64n} : Policy.TotalDecision}

# Rejects an aggregate that exceeds the limit even when each file fits alone.
law aggregate_budget_rejects:
  {Policy.total_decision(40n, 25n, 64n) ==
    Policy.TotalRejected{} : Policy.TotalDecision}
