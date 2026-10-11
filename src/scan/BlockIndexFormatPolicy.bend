import Base

# Describes the fixed-width section sizes of the separator index layout.
def header_bytes() -> Nat:
  8n

# Returns the fixed offset/length metadata width for one data block.
def entry_bytes() -> Nat:
  16n

# Returns the extended footer width including its root digest.
def footer_bytes() -> Nat:
  44n

# Returns the earliest valid position after the fixed SST header.
def minimum_data_offset() -> Nat:
  20n

def nat.clone.pair(+value: Nat) -> Nat & Nat:
  (Nat.mul(1n, value), Nat.mul(1n, value))

# Computes index bytes from fixed records and the packed separator region.
def index_bytes(block_count: Nat, separator_bytes: Nat) -> Nat:
  Nat.add(Nat.add(header_bytes(), Nat.mul(block_count, entry_bytes())),
    separator_bytes)

# Locates the index from the index length retained in the extended footer.
def index_offset(file_size: Nat, index_length: Nat) -> Nat:
  Nat.sub(file_size, Nat.add(footer_bytes(), index_length))

# Checks the index/footer interval without overflowing its containing file.
def interval_valid.copies(
  sizes: Nat & Nat,
  indices: Nat & Nat
) -> Bool:
  match sizes:
    case (measured_size, checked_size):
      match indices:
        case (measured_length, checked_length):
          Nat.is_le(Nat.add(footer_bytes(), measured_length), measured_size) &&
            Nat.is_le(minimum_data_offset(),
              index_offset(checked_size, checked_length))

# Checks the index/footer interval without underflow or header overlap.
def interval_valid(file_size: Nat, index_length: Nat) -> Bool:
  interval_valid.copies(nat.clone.pair(file_size),
    nat.clone.pair(index_length))

# Checks one separator slice against the packed separator region.
def separator_valid(offset: Nat, length: Nat, region_length: Nat) -> Bool:
  Nat.is_le(Nat.add(offset, length), region_length)
