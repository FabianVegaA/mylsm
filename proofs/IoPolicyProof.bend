import Base
import ../laws/IoPolicy.bend as Laws

def Laws.zero_write_has_zero_chunk():
  {==}

def Laws.short_write_keeps_the_remaining_length():
  {==}

def Laws.oversized_write_chunk_is_capped():
  {==}

def Laws.interrupted_read_is_retryable():
  {==}

def Laws.linux_would_block_read_is_waiting():
  {==}

def Laws.macos_would_block_read_is_waiting():
  {==}

def Laws.terminal_read_error_is_not_waiting():
  {==}

def Laws.interrupted_write_is_retryable():
  {==}

def Laws.linux_would_block_write_preserves_progress():
  {==}

def Laws.macos_would_block_write_preserves_progress():
  {==}

def Laws.terminal_write_error_is_not_waiting():
  {==}
