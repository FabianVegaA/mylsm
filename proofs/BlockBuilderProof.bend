import Base
import ../laws/BlockBuilder.bend as Laws

# Witnesses exact block-capacity admission.
def Laws.exact_block_capacity_is_accepted():
  {==}

# Witnesses rollover when a populated block lacks room.
def Laws.full_block_requests_rollover():
  {==}

# Witnesses rejection of a record too large for an empty block.
def Laws.oversized_record_is_rejected():
  {==}
