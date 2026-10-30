import Base
import ../src/coordinator/CleanupPolicy.bend as Policy

# Verifies current file never releases cleanup reservation.
law current_file_never_releases_cleanup_reservation:
  for succeeded: Bool
  {Policy.unlink.decide(True{}, succeeded) == Policy.PreserveLive{} :
    Policy.CleanupDecision}

# Verifies failed unlink remains pending.
law failed_unlink_remains_pending:
  {Policy.unlink.decide(False{}, False{}) == Policy.KeepPending{} :
    Policy.CleanupDecision}

# Verifies successful unlink releases pending reservation.
law successful_unlink_releases_pending_reservation:
  {Policy.unlink.decide(False{}, True{}) == Policy.ReleaseReservation{} :
    Policy.CleanupDecision}
