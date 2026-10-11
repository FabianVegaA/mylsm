import Base
import ../coordinator/QueuePolicy.bend as QueuePolicy

# Describes one bounded page in a serialized block index.
type PageDecision is Data:
  Page{first: Nat, count: Nat}

# Returns the fixed bound for all resident serialized-index buffers.
def resident_budget() -> Nat:
  65536n

# Counts the input buffer, positional-read assembly, and two hash inputs.
def buffer_copies() -> Nat:
  4n

# Bounds one serialized-index read so its live copies fit the resident budget.
def max_bytes() -> Nat:
  Nat.div(resident_budget(), buffer_copies())

# Computes the number of entries that fit beside one page header.
def max_entries() -> Nat:
  Nat.div(Nat.sub(max_bytes(), 8n), 8n)

# Returns the maximum entries that fit in a page-sized index span.
def max_blocks() -> Nat:
  max_entries()

# Counts all bounded resident copies of one serialized-index read.
def resident_metadata_bytes(page_bytes: Nat) -> Nat:
  Nat.mul(buffer_copies(), page_bytes)

# Accepts one page only when it fits the resident budget.
def accepts(entries: Nat) -> Bool:
  Nat.is_le(entries, max_blocks())

# Bounds one positional index read without restricting the total index size.
def read_bytes.limit(limit: Nat, remaining: Nat) -> Nat:
  Nat.min(limit, remaining)

# Applies the resident page limit to one positional index read.
def read_bytes(remaining: Nat) -> Nat:
  read_bytes.limit(max_bytes(), remaining)

# Accepts a block ordinal only when a serialized index contains that block.
def contains(block_count: Nat, index: Nat) -> Bool:
  Nat.is_lt(index, block_count)

# Combines independent offset copies to validate the complete block interval.
def entry_valid.copies(
  offsets: Nat & Nat,
  data_length: Nat,
  index_offset: Nat
) -> Bool:
  match offsets:
    case (start, for_end):
      Nat.is_le(20n, start) &&
        Nat.is_le(Nat.add(for_end, data_length), index_offset)

# Accepts a block range only when it stays between the header and index.
def entry_valid(data_offset: Nat, data_length: Nat, index_offset: Nat) -> Bool:
  entry_valid.copies(QueuePolicy.nat.clone.pair(data_offset), data_length,
    index_offset)

def page.parts(firsts: Nat & Nat, entries: Nat) -> PageDecision:
  match firsts:
    case (first, for_remaining):
      Page{first, Nat.min(max_entries(), Nat.sub(entries, for_remaining))}

# Selects a fixed-budget index page; a zero count marks the terminal position.
def page(first: Nat, entries: Nat) -> PageDecision:
  page.parts(QueuePolicy.nat.clone.pair(first), entries)
