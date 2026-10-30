import Base
import ../src/coordinator/UnixSocketPolicy.bend as Policy

# Classifies Darwin's unsupported-socket error code explicitly.
law darwin_unsupported_code:
  {Policy.classify_code(45) == Policy.UnsupportedPlatform{} : Policy.Classification}

# Classifies Darwin's alternate unsupported-socket error code explicitly.
law darwin_alt_unsupported_code:
  {Policy.classify_code(78) == Policy.UnsupportedPlatform{} : Policy.Classification}

# Classifies Linux's unsupported-socket error code explicitly.
law linux_unsupported_code:
  {Policy.classify_code(95) == Policy.UnsupportedPlatform{} : Policy.Classification}

# Classifies the shared POSIX unavailable-operation code explicitly.
law posix_unavailable_code:
  {Policy.classify_code(38) == Policy.UnsupportedPlatform{} : Policy.Classification}

# Verifies interrupted syscall is transient.
law interrupted_syscall_is_transient:
  {Policy.classify_code(4) == Policy.Transient{4} : Policy.Classification}

# Verifies linux would block is transient.
law linux_would_block_is_transient:
  {Policy.classify_code(11) == Policy.Transient{11} : Policy.Classification}

# Verifies darwin would block is transient.
law darwin_would_block_is_transient:
  {Policy.classify_code(35) == Policy.Transient{35} : Policy.Classification}

# Leaves ordinary socket errors outside the unsupported category.
law preserves_ordinary_code:
  {Policy.classify_code(13) == Policy.Host{13} : Policy.Classification}

# Verifies readable poll event is ready.
law readable_poll_event_is_ready:
  {Policy.poll_status(1) == Policy.Readable{} : Policy.PollStatus}

# Verifies empty poll event is idle.
law empty_poll_event_is_idle:
  {Policy.poll_status(0) == Policy.Idle{} : Policy.PollStatus}

# Verifies terminal poll event is failed.
law terminal_poll_event_is_failed:
  {Policy.poll_status(8) == Policy.Failed{} : Policy.PollStatus}

# Verifies readiness cannot apply to a different connection.
law readiness_cannot_apply_to_a_different_connection:
  {Policy.event.applies(7, 8) == False{} : Bool}

# Verifies interrupted poll is retryable.
law interrupted_poll_is_retryable:
  {Policy.poll.failure(4) == Policy.Retry{} : Policy.PollFailureAction}

# Verifies would block poll is retryable.
law would_block_poll_is_retryable:
  {Policy.poll.failure(11) == Policy.Retry{} : Policy.PollFailureAction}

# Verifies permanent poll error stops the reactor.
law permanent_poll_error_stops_the_reactor:
  {Policy.poll.failure(5) == Policy.Stop{} : Policy.PollFailureAction}

# Verifies buffered data remains readable with hangup.
law buffered_data_remains_readable_with_hangup:
  {Policy.poll_status(17) == Policy.ReadableFailed{} : Policy.PollStatus}
