import Base
import ../src/scan/Utf8CursorPolicy.bend as Policy

# Text decoding errors remain distinguishable from reader errors.
law text_failure_keeps_text_class:
  {Policy.classify(Policy.TextDecodeFailure{}) == Policy.TextFailure{} : Policy.FailureClass}

# Reader failures remain wrapped storage failures.
law reader_failure_keeps_storage_class:
  {Policy.classify(Policy.ReaderFailure{}) == Policy.StorageFailure{} : Policy.FailureClass}

# Resource exhaustion remains a resource-limit error.
law resource_failure_keeps_limit_class:
  {Policy.classify(Policy.ResourceFailure{}) == Policy.ResourceLimitFailure{} : Policy.FailureClass}

# Invalid bounds remain argument errors.
law argument_failure_keeps_argument_class:
  {Policy.classify(Policy.ArgumentFailure{}) == Policy.InvalidArgumentFailure{} : Policy.FailureClass}

# The terminal cursor can retain its category while reporting it.
law terminal_failure_can_be_retained:
  {Policy.duplicate(Policy.ReaderFailure{}) ==
    (Policy.ReaderFailure{}, Policy.ReaderFailure{}) : Policy.Failure & Policy.Failure}
