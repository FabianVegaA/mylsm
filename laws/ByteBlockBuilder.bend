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
