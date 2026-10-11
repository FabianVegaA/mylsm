import Base
import ../src/scan/BlockIndexFormatPolicy.bend as Policy

# A three-block index includes its header, fixed records, and separator bytes.
law index_size_counts_fixed_records_and_keys:
  {Policy.index_bytes(3n, 11n) == 67n : Nat}

# The footer length locates the index immediately after the block data.
law footer_length_locates_index:
  {Policy.index_offset(2048n, 67n) == 1937n : Nat}

# A well-formed index cannot overlap the fixed SST header.
law index_interval_accepts_data_boundary:
  {Policy.interval_valid(2048n, 1984n) == True{} : Bool}

# An oversized footer/index interval is rejected before positional reads.
law index_interval_rejects_underflow:
  {Policy.interval_valid(2048n, 1985n) == False{} : Bool}

# Empty keys are valid zero-length separators at the region boundary.
law empty_separator_at_end_is_valid:
  {Policy.separator_valid(11n, 0n, 11n) == True{} : Bool}

# Separator metadata cannot address bytes beyond its packed region.
law separator_past_region_is_invalid:
  {Policy.separator_valid(10n, 2n, 11n) == False{} : Bool}
