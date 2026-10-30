import Base
import ../laws/UnixSocketPolicy.bend as Laws

def Laws.darwin_unsupported_code():
  {==}

def Laws.darwin_alt_unsupported_code():
  {==}

def Laws.linux_unsupported_code():
  {==}

def Laws.posix_unavailable_code():
  {==}

def Laws.interrupted_syscall_is_transient():
  {==}

def Laws.linux_would_block_is_transient():
  {==}

def Laws.darwin_would_block_is_transient():
  {==}

def Laws.preserves_ordinary_code():
  {==}

def Laws.readable_poll_event_is_ready():
  {==}

def Laws.empty_poll_event_is_idle():
  {==}

def Laws.terminal_poll_event_is_failed():
  {==}

def Laws.readiness_cannot_apply_to_a_different_connection():
  {==}

def Laws.interrupted_poll_is_retryable():
  {==}

def Laws.would_block_poll_is_retryable():
  {==}

def Laws.permanent_poll_error_stops_the_reactor():
  {==}

def Laws.buffered_data_remains_readable_with_hangup():
  {==}
