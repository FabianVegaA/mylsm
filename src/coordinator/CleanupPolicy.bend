import Base

# Carries the state for CleanupDecision.
type CleanupDecision is Data:
  KeepPending{}
  ReleaseReservation{}
  PreserveLive{}

def unlink.finished(succeeded: Bool) -> CleanupDecision:
  match succeeded:
    case True{}: ReleaseReservation{}
    case False{}: KeepPending{}

def unlink.decide(is_live: Bool, succeeded: Bool) -> CleanupDecision:
  match is_live:
    case True{}: PreserveLive{}
    case False{}: unlink.finished(succeeded)
