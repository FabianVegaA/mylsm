import Base

# Says whether an open keeps its handle or rejects the requested options.
type Decision is Data:
  UseLocal{}
  UseRemote{}
  RejectOptions{}

# Picks the handle kind that a matching open keeps.
def matched(local: Bool) -> Decision:
  match local:
    case True{}: UseLocal{}
    case False{}: UseRemote{}

# Keeps the opened handle only when the requested options match the effective ones.
def choose(local: Bool, matches: Bool) -> Decision:
  match matches:
    case True{}: matched(local)
    case False{}: RejectOptions{}
