import Base
import ./Protocol.bend as Protocol

# Says whether an encoded response fits its byte budget.
type Outcome is Data:
  Fits{}
  Overflows{}

# Carries the reply status and whether the payload is kept.
type Bounded is Data:
  Bounded{status: Protocol.ResponseStatus, keep_payload: Bool}

# Turns the budget check into an outcome.
def outcome(fits: Bool) -> Outcome:
  match fits:
    case True{}: Fits{}
    case False{}: Overflows{}

def overflow.status(mutation: Bool) -> Protocol.ResponseStatus:
  match mutation:
    case True{}: Protocol.CommitUnknown{}
    case False{}: Protocol.ResponseResourceLimit{}

# Chooses the reply status and payload for a response and its budget outcome.
def bound(
  mutation: Bool,
  status: Protocol.ResponseStatus,
  outcome: Outcome
) -> Bounded:
  match outcome:
    case Fits{}: Bounded{status, True{}}
    case Overflows{}: Bounded{overflow.status(mutation), False{}}
