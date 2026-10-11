import Base
import ../src/DbLockPolicy.bend as DbLockPolicy
import ../src/DurableError.bend as DurableError

# Linux lock contention maps to Busy.
law linux_lock_contention_classification:
  {DbLockPolicy.classify_lock_error(11, "", "open_existing", "/db") == DurableError.Error{DurableError.Busy{}, "open_existing", "/db", 11, ""} : DurableError.Error}

# Darwin lock contention maps to Busy.
law darwin_lock_contention_classification:
  {DbLockPolicy.classify_lock_error(35, "", "open_existing", "/db") == DurableError.Error{DurableError.Busy{}, "open_existing", "/db", 35, ""} : DurableError.Error}

# Other lock errors retain their host details.
law other_lock_error_classification:
  {DbLockPolicy.classify_lock_error(13, "host failure", "open_existing", "/db") == DurableError.Error{DurableError.Io{}, "open_existing", "/db", 13, "host failure"} : DurableError.Error}

# A missing lock path maps to NotFound.
law missing_lock_path_classification:
  {DbLockPolicy.classify_lock_error(2, "missing path", "open_existing", "/db") == DurableError.Error{DurableError.NotFound{}, "open_existing", "/db", 2, "missing path"} : DurableError.Error}

# Darwin reports unsupported lock facilities as ENOTSUP.
law darwin_unsupported_lock_classification:
  {DbLockPolicy.classify_lock_error(45, "unsupported", "open_existing", "/db") ==
    DurableError.Error{DurableError.UnsupportedPlatform{}, "open_existing", "/db", 45, "unsupported"} : DurableError.Error}

# Linux reports unsupported lock facilities as EOPNOTSUPP.
law linux_unsupported_lock_classification:
  {DbLockPolicy.classify_lock_error(95, "unsupported", "open_existing", "/db") ==
    DurableError.Error{DurableError.UnsupportedPlatform{}, "open_existing", "/db", 95, "unsupported"} : DurableError.Error}


# A successful attempt terminates even if contention facts are also present.
law acquired_terminates_wait:
  {DbLockPolicy.wait_decision(True{}, True{}, 0n, 100n, 5n) ==
    DbLockPolicy.LockAcquired{} : DbLockPolicy.WaitDecision}

# A busy attempt times out once elapsed time reaches its deadline.
law busy_wait_times_out_at_deadline:
  {DbLockPolicy.wait_decision(False{}, True{}, 100n, 100n, 5n) ==
    DbLockPolicy.LockTimedOut{} : DbLockPolicy.WaitDecision}

# A retry sleep never extends beyond the remaining deadline.
law busy_wait_caps_backoff:
  {DbLockPolicy.wait_decision(False{}, True{}, 98n, 100n, 5n) ==
    DbLockPolicy.LockRetry{2n} : DbLockPolicy.WaitDecision}

# Non-contention host failures do not enter the retry loop.
law nonbusy_lock_error_is_fatal:
  {DbLockPolicy.wait_decision(False{}, False{}, 0n, 100n, 5n) ==
    DbLockPolicy.LockFatal{} : DbLockPolicy.WaitDecision}

# The documented maximum timeout and minimum backoff are accepted.
law wait_options_accept_boundary:
  {DbLockPolicy.wait_options_valid(60000, 1) == True{} : Bool}

# A zero backoff is rejected to guarantee progress toward the deadline.
law wait_options_reject_zero_backoff:
  {DbLockPolicy.wait_options_valid(100, 0) == False{} : Bool}

# A timeout beyond the finite public maximum is rejected.
law wait_options_reject_oversized_timeout:
  {DbLockPolicy.wait_options_valid(60001, 1) == False{} : Bool}
