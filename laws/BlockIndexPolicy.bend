import Base
import ../src/scan/BlockIndexPolicy.bend as Policy

# Accepts the maximum number of entries in one resident page.
law accepts_the_page_budget_boundary:
  {Policy.accepts(Policy.max_blocks()) == True{} : Bool}

# Rejects one block beyond the fixed metadata bound.
law rejects_one_entry_over_the_page_budget:
  {Policy.accepts(Nat.add(Policy.max_blocks(), 1n)) == False{} : Bool}

# One page's encoded metadata fits the configured byte budget.
law retained_page_metadata_fits_the_budget:
  {Nat.is_le(Policy.resident_metadata_bytes(Policy.max_bytes()),
    Policy.resident_budget()) == True{} : Bool}

# The next block would exceed the fixed metadata budget.
law next_page_entry_exceeds_the_budget:
  {Nat.is_lt(Policy.resident_budget(),
    Policy.resident_metadata_bytes(Nat.add(Policy.max_bytes(), 1n))) == True{} : Bool}

# The first logical index page stops at the resident entry boundary.
law large_index_first_page_is_bounded:
  {Policy.page(0n, Nat.add(Policy.max_entries(), 1n)) ==
    Policy.Page{0n, Policy.max_entries()} : Policy.PageDecision}

# The next page starts exactly after the previous page without overlap.
law large_index_second_page_covers_remainder:
  {Policy.page(Policy.max_entries(), Nat.add(Policy.max_entries(), 1n)) ==
    Policy.Page{Policy.max_entries(), 1n} : Policy.PageDecision}

# Positions at or beyond the index end are terminal.
law page_at_index_end_is_terminal:
  {Policy.page(4n, 4n) == Policy.Page{4n, 0n} : Policy.PageDecision}

# A position beyond the end of the index yields an empty page.
law page_below_index_end_is_empty:
  {Policy.page(8n, 4n) == Policy.Page{8n, 0n} : Policy.PageDecision}

# A read consumes no more than the resident page size.
law read_chunk_is_bounded:
  {Policy.read_bytes.limit(16n, 21n) == 16n : Nat}

# A final short read consumes the exact remaining index bytes.
law read_chunk_finishes_the_remainder:
  {Policy.read_bytes.limit(16n, 7n) == 7n : Nat}

# Accepts the first and last block ordinals in a nonempty index.
law contains_first_block:
  {Policy.contains(3n, 0n) == True{} : Bool}

# Accepts the final ordinal before the block count.
law contains_last_block:
  {Policy.contains(3n, 2n) == True{} : Bool}

# Rejects an ordinal at the block count because indexes are zero based.
law rejects_block_ordinal_at_count:
  {Policy.contains(3n, 3n) == False{} : Bool}

# Accepts a block range ending exactly at the serialized index.
law accepts_block_ending_at_index:
  {Policy.entry_valid(20n, 40n, 60n) == True{} : Bool}

# Rejects a block range that reaches into the serialized index.
law rejects_block_crossing_index:
  {Policy.entry_valid(20n, 41n, 60n) == False{} : Bool}

# Rejects a block offset that precedes the fixed SST header.
law rejects_block_before_header:
  {Policy.entry_valid(19n, 1n, 60n) == False{} : Bool}
