import Base
import ../src/ReadAtPolicy.bend as Policy

# A single byte at the final addressable offset is valid.
law final_byte_is_valid:
  {Policy.range_valid(16n, 15n, 1n) == True{} : Bool}

# An interval that crosses the address-space limit is rejected.
law range_past_limit_is_rejected:
  {Policy.range_valid(16n, 15n, 2n) == False{} : Bool}

# A zero-length interval at the limit is valid.
law empty_range_at_limit_is_valid:
  {Policy.range_valid(16n, 16n, 0n) == True{} : Bool}

# The full modeled address space is valid when it starts at zero.
law full_address_space_is_valid:
  {Policy.range_valid(16n, 0n, 16n) == True{} : Bool}
