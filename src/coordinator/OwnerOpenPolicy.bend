import Base

# Carries the state for Decision.
type Decision is Data:
  UseLocal{}
  UseRemote{}
  RejectOptions{}

# Handles remote.
def remote(matches: Bool) -> Decision:
  match matches:
    case True{}: UseRemote{}
    case False{}: RejectOptions{}

# Handles choose.
def choose(local: Bool, matches: Bool) -> Decision:
  match local:
    case True{}: UseLocal{}
    case False{}: remote(matches)
