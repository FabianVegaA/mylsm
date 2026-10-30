import Base

# Carries the state for PollInterest.
type PollInterest is Type:
  PollInterest{connection_id: U32, socket: File, events: U32}

# Carries the state for ReadyEvent.
type ReadyEvent is Data:
  ReadyEvent{connection_id: U32, flags: U32}
