import Base
import ../src/coordinator/IoPolicy.bend as Policy

# A zero-length transfer requests no host write bytes.
law zero_write_has_zero_chunk:
  {Policy.write_chunk(0) == 0 : U32}

# A short write leaves exactly the unwritten suffix for the next step.
law short_write_keeps_the_remaining_length:
  {Policy.write_chunk(4096) == 4096 : U32}

# Large socket writes stay within the configured per-call bound.
law oversized_write_chunk_is_capped:
  {Policy.write_chunk(70000) == 65536 : U32}
