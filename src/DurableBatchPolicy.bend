import Base

# Returns the count-limit decision for a mutation batch.
type Validation is Data:
  ValidBatch{}
  EmptyBatch{}
  BatchCountExceeded{}

# Returns the maximum number of mutations in a batch.
def max_batch_count() -> Nat:
  256n

# Checks whether a batch count is within the allowed range.
def within_batch_count(count: Nat) -> Bool:
  Nat.is_le(count, max_batch_count())

# Rejects empty and oversized batches before writing.
def validate_count(count: Nat) -> Validation:
  match count:
    case 0n:
      EmptyBatch{}
    case count:
      Bool.pick(Validation, within_batch_count(count), ValidBatch{}, BatchCountExceeded{})
