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

# Verifies interrupted read is retryable.
law interrupted_read_is_retryable:
  {Policy.read.disposition(4) == Policy.ReadInterrupted{} : Policy.ReadDisposition}

# Verifies linux would block read is waiting.
law linux_would_block_read_is_waiting:
  {Policy.read.disposition(11) == Policy.ReadWouldBlock{} : Policy.ReadDisposition}

# Verifies macos would block read is waiting.
law macos_would_block_read_is_waiting:
  {Policy.read.disposition(35) == Policy.ReadWouldBlock{} : Policy.ReadDisposition}

# Verifies terminal read error is not waiting.
law terminal_read_error_is_not_waiting:
  {Policy.read.disposition(32) == Policy.ReadFailure{} : Policy.ReadDisposition}

# Verifies interrupted write is retryable.
law interrupted_write_is_retryable:
  {Policy.write.disposition(4) == Policy.WriteInterrupted{} : Policy.WriteDisposition}

# Verifies linux would block write preserves progress.
law linux_would_block_write_preserves_progress:
  {Policy.write.disposition(11) == Policy.WriteWouldBlock{} : Policy.WriteDisposition}

# Verifies macos would block write preserves progress.
law macos_would_block_write_preserves_progress:
  {Policy.write.disposition(35) == Policy.WriteWouldBlock{} : Policy.WriteDisposition}

# Verifies terminal write error is not waiting.
law terminal_write_error_is_not_waiting:
  {Policy.write.disposition(32) == Policy.WriteFailure{} : Policy.WriteDisposition}
