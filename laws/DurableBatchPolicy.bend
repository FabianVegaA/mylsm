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

# Accepts a multi-record frame exactly at its supplied byte ceiling.
law multi_record_frame_accepts_its_byte_limit:
  for encoded_bytes: Nat
  for limit: Nat
  {Policy.validate_frame_bytes(2n, encoded_bytes, limit, limit) ==
    Bool.pick(Policy.Validation, Nat.is_le(encoded_bytes, limit),
      Policy.ValidBatch{}, Policy.BatchBytesExceeded{}) : Policy.Validation}

# Applies the single-record ceiling independently of the batch ceiling.
law single_record_frame_uses_its_own_limit:
  for encoded_bytes: Nat
  for batch_limit: Nat
  for single_limit: Nat
  {Policy.validate_frame_bytes(1n, encoded_bytes, batch_limit, single_limit) ==
    Bool.pick(Policy.Validation, Nat.is_le(encoded_bytes, single_limit),
      Policy.ValidBatch{}, Policy.BatchBytesExceeded{}) : Policy.Validation}

# The encoded Put size contains its fixed nine-byte prefix.
law put_record_size_includes_fixed_prefix:
  for key_bytes: Nat
  for value_bytes: Nat
  {Policy.put_record_bytes(key_bytes, value_bytes) ==
    Nat.add(9n, Nat.add(key_bytes, value_bytes)) : Nat}

# The encoded Delete size contains its fixed five-byte prefix.
law delete_record_size_includes_fixed_prefix:
  for key_bytes: Nat
  {Policy.delete_record_bytes(key_bytes) == Nat.add(5n, key_bytes) : Nat}
