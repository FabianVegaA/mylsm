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
