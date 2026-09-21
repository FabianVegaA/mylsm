import Base
import ../src/CrashPoint.bend as CrashPoint

# The open unset theorem and closed equality fixtures keep activation policy in
# proven Bend code. Marker emission and SIGSTOP remain outside this proof scope.
law crash_point_unset_disabled_for_any_requested:
  for requested: String
  {CrashPoint.enabled("", requested) == False{} : Bool}


law crash_point_mismatch_disabled:
  {CrashPoint.enabled("wal.appended", "wal.synced") == False{} : Bool}

law crash_point_exact_enabled:
  {CrashPoint.enabled("wal.synced", "wal.synced") == True{} : Bool}
