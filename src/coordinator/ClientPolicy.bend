import Base
import ./QueuePolicy.bend as QueuePolicy
import ./Protocol.bend as Protocol

# Represents whether one request is ready, dispatched, complete, or stale.
type State is Data:
  ClientReady{generation: Nat}
  RequestDispatched{generation: Nat, mutation: Bool}
  RequestCompleted{generation: Nat}

# Separates confirmation, safe retry, stale-owner, and uncertain-write outcomes.
type Decision is Data:
  ClientDispatch{state: State}
  ClientConfirmed{state: State}
  ClientRetryRead{}
  ClientRetryBeforeDispatch{}
  ClientCommitUnknown{}
  ClientStaleOwner{}
  ClientProtocolFailure{}
  ClientReject{}

# Tracks request identifiers without allowing U32 wraparound reuse.
type RequestSequence is Data:
  RequestAvailable{id: U32}
  RequestExhausted{}

# Assigns one identifier and returns the next sequence state.
type RequestDecision is Type:
  RequestAssigned{id: U32, next: RequestSequence}
  RequestIdsExhausted{}

def response.generation.result(
  generation: Nat,
  generation_matches: Bool
) -> Decision:
  match generation_matches:
    case True{}: ClientConfirmed{RequestCompleted{generation}}
    case False{}: ClientStaleOwner{}

def response.generation.checked(
  generations: Nat & Nat,
  current_generation: Nat
) -> Decision:
  match generations:
    case (generation, checked_generation):
      response.generation.result(generation,
        Nat.is_eq(checked_generation, current_generation))

def response.generation(
  generation: Nat,
  current_generation: Nat
) -> Decision:
  response.generation.checked(QueuePolicy.nat.clone.pair(generation),
    current_generation)

def response.validate(
  generation: Nat,
  generation_matches: Bool,
  correlation_matches: Bool
) -> Decision:
  match generation_matches:
    case False{}: ClientStaleOwner{}
    case True{}:
      match correlation_matches:
        case True{}: ClientConfirmed{RequestCompleted{generation}}
        case False{}: ClientProtocolFailure{}

def disconnect.dispatched(mutation: Bool) -> Decision:
  match mutation:
    case True{}: ClientCommitUnknown{}
    case False{}: ClientRetryRead{}

# Identifies request tags that can change durable database state.
def operation.is_mutation(operation: U32) -> Bool:
  match operation:
    case 2: True{}
    case 3: True{}
    case 4: True{}
    case 5: True{}
    case _: False{}

# Enforces the encoded IPC payload ceiling before client socket allocation.
def request.within_payload_limit(payload_bytes: U32) -> Bool:
  Protocol.payload.admitted(payload_bytes)

def request_id.take.available(
  ids: U32 & U32,
  is_final: Bool
) -> RequestDecision:
  match ids:
    case (id, next_id):
      match is_final:
        case True{}: RequestAssigned{id, RequestExhausted{}}
        case False{}: RequestAssigned{id, RequestAvailable{(next_id + 1 : U32)}}

def request_id.take.ready(
  copies: U32 & U32 & U32
) -> RequestDecision:
  match copies:
    case (final_check, (id, next_id)):
      request_id.take.available((id, next_id),
        U32.is_eq(final_check, 4294967295))

# Assigns each request ID once and makes exhaustion terminal.
def request_id.take(sequence: RequestSequence) -> RequestDecision:
  match sequence:
    case RequestAvailable{id}:
      request_id.take.ready(Protocol.u32.duplicate.triple(id))
    case RequestExhausted{}: RequestIdsExhausted{}

# Marks a ready request as dispatched exactly once.
def dispatch(state: State, mutation: Bool) -> Decision:
  match state:
    case ClientReady{generation}:
      ClientDispatch{RequestDispatched{generation, mutation}}
    case _: ClientReject{}

# Resolves a response only when it belongs to the current owner generation.
def response(state: State, current_generation: Nat) -> Decision:
  match state:
    case RequestDispatched{generation, _}:
      response.generation(generation, current_generation)
    case _: ClientReject{}

# Classifies a disconnected request without retrying a dispatched mutation.
def disconnect(state: State) -> Decision:
  match state:
    case ClientReady{_}: ClientRetryBeforeDispatch{}
    case RequestDispatched{_, mutation}:
      disconnect.dispatched(mutation)
    case _: ClientReject{}
