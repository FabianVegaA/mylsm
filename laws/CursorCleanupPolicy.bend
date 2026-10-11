import Base
import ../src/scan/CursorCleanupPolicy.bend as Policy

# Cleanup succeeds only when both owned resources close successfully.
law owned_cursor_cleanup_success:
  {Policy.combine(&2, U32, Done{Unit{}}, Done{Unit{}}) == Done{Unit{}} : Result<&2, &1, U32, Unit>}

# A cursor-close error remains the primary result for every snapshot-close error.
law owned_cursor_cleanup_preserves_first_failure:
  for first: U32
  for second: U32
  {Policy.combine(&2, U32, Fail{first}, Fail{second}) == Fail{first} : Result<&2, &1, U32, Unit>}

# A failed snapshot release remains visible after successful cursor cleanup.
law owned_cursor_cleanup_reports_snapshot_failure:
  for error: U32
  {Policy.combine(&2, U32, Done{Unit{}}, Fail{error}) == Fail{error} : Result<&2, &1, U32, Unit>}
