import Base
import ../src/DurableBatchPolicy.bend as Policy

# Empty mutation batches are rejected.
law empty_batch_is_rejected:
  {Policy.validate_count(0n) == Policy.EmptyBatch{} : Policy.Validation}

# A one-mutation batch is valid.
law exactly_one_mutation_is_allowed:
  {Policy.validate_count(1n) == Policy.ValidBatch{} : Policy.Validation}

# A batch at the count limit is valid.
law batch_count_cap_is_allowed:
  {Policy.validate_count(256n) == Policy.ValidBatch{} : Policy.Validation}

# A batch above the count limit is rejected.
law batch_count_over_cap_is_rejected:
  {Policy.validate_count(257n) == Policy.BatchCountExceeded{} : Policy.Validation}
