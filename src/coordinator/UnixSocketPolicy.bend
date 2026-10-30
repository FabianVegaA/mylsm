import Base

# Distinguishes supported socket errors from missing host capabilities.
type Classification is Data:
  UnsupportedPlatform{}
  Transient{code: U32}
  Host{code: U32}

# Carries the state for PollStatus.
type PollStatus is Data:
  Readable{}
  ReadableFailed{}
  Idle{}
  Failed{}

# Carries the state for PollFailureAction.
type PollFailureAction is Data:
  Retry{}
  Stop{}

def event.applies(connection_id: U32, event_id: U32) -> Bool:
  U32.is_eq(connection_id, event_id)

# Classifies platform-specific errno values without performing host IO.
def classify_code(code: U32) -> Classification:
  match code:
    case 45: UnsupportedPlatform{}
    case 78: UnsupportedPlatform{}
    case 95: UnsupportedPlatform{}
    case 38: UnsupportedPlatform{}
    case 4: Transient{4}
    case 11: Transient{11}
    case 35: Transient{35}
    case _: Host{code}

def poll.failure.action(classification: Classification) -> PollFailureAction:
  match classification:
    case Transient{_}: Retry{}
    case _: Stop{}

def poll.failure(code: U32) -> PollFailureAction:
  poll.failure.action(classify_code(code))

def poll.failed(flags: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(flags, 56), 0))

def poll.readable(flags: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(flags, 1), 0))

def poll.status.readable(readable: Bool, failed: Bool) -> PollStatus:
  match readable:
    case True{}:
      match failed:
        case True{}: ReadableFailed{}
        case False{}: Readable{}
    case False{}:
      match failed:
        case True{}: Failed{}
        case False{}: Idle{}

# Handles poll status.
def poll_status(+flags: U32) -> PollStatus:
  poll.status.readable(poll.readable(flags), poll.failed(flags))
