import Base
import ../src/scan/ByteBlockBuilder.bend as Builder

# Admits a record that exactly fills an empty block.
law exact_block_capacity_is_admitted:
  {Builder.decide(0n, 16n, 16n) == Builder.Append{16n} : Builder.Decision}

# Requests a fresh block when a fitting record exceeds remaining capacity.
law byte_block_requests_rollover:
  {Builder.decide(12n, 5n, 16n) == Builder.StartNextBlock{5n} : Builder.Decision}

# Rejects a record that cannot fit even in an empty block.
law byte_block_rejects_oversized_record:
  {Builder.decide(0n, 17n, 16n) == Builder.RecordTooLarge{} : Builder.Decision}

# Preserves the existing block occupancy when a new block is needed.
law rollover_does_not_add_to_old_block:
  {Builder.decide(15n, 4n, 16n) == Builder.StartNextBlock{4n} : Builder.Decision}

# Rejects a record above the hard cap whatever the block occupancy.
law target_rejects_oversized_record_for_any_occupancy:
  for used: Nat
  for record: Nat
  for starts_block: Bool
  {Builder.decide.target.sized(used, record, False{}, starts_block) ==
    Builder.RecordTooLarge{} : Builder.Decision}

# Admits any fitting record into an empty block, even above the target size.
law target_empty_block_admits_fitting_record:
  for record: Nat
  {Builder.decide.target.sized(0n, record, True{}, True{}) ==
    Builder.Append{record} : Builder.Decision}

# Appends a record while the block stays within its target size.
law target_block_fills_up_to_target:
  {Builder.decide.target(10n, 6n, 16n, 64n) == Builder.Append{16n} : Builder.Decision}

# Starts a new block once a record would pass the target size.
law target_block_rolls_over_past_target:
  {Builder.decide.target(12n, 5n, 16n, 64n) ==
    Builder.StartNextBlock{5n} : Builder.Decision}

# Keeps a record larger than the target alone in a fresh block.
law target_large_record_starts_its_own_block:
  {Builder.decide.target(8n, 40n, 16n, 64n) ==
    Builder.StartNextBlock{40n} : Builder.Decision}

# Admits a record larger than the target into an empty block.
law target_large_record_fills_empty_block:
  {Builder.decide.target(0n, 40n, 16n, 64n) == Builder.Append{40n} : Builder.Decision}

# Rejects a record above the hard cap even in an empty block.
law target_rejects_record_above_cap:
  {Builder.decide.target(0n, 65n, 16n, 64n) == Builder.RecordTooLarge{} : Builder.Decision}
