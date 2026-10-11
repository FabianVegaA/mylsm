import Base

# Names the visibility boundary reached before a durability failure.
type Phase is Data:
  BeforeRename{}
  AfterRename{}

# Distinguishes a definite failure from an uncertain published result.
type Failure is Data:
  KnownFailure{}
  CommitUnknown{}

# Classifies whether a publication failure leaves destination visibility uncertain.
def failure(phase: Phase) -> Failure:
  match phase:
    case BeforeRename{}: KnownFailure{}
    case AfterRename{}: CommitUnknown{}
