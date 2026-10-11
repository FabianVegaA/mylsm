import Base
import ../src/scan/BlockBuilder.bend as Builder

# Admits an exact-capacity block without exceeding its budget.
law exact_block_capacity_is_accepted:
  {Builder.decide(16n, False{}, True{}) == Builder.Append{16n} : Builder.Decision}

# Rolls a nonempty block before retrying a record that does not fit.
law full_block_requests_rollover:
  {Builder.decide(17n, False{}, False{}) == Builder.StartNextBlock{} : Builder.Decision}

# Rejects a record that cannot fit in an empty block.
law oversized_record_is_rejected:
  {Builder.decide(17n, True{}, False{}) == Builder.RecordTooLarge{} : Builder.Decision}
