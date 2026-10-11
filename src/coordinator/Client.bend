import Base
import ../ByteMemTable.bend as ByteMemTable
import ./ClientPolicy.bend as Policy
import ./Io.bend as Io
import ./Operation.bend as Operation
import ./Protocol.bend as Protocol
import ./UnixSocketIo.bend as UnixSocket
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Returns connection, transport, correlation, and retry-boundary outcomes.
type Error is Type:
  ConnectFailure{error: UnixSocket.Error}
  RetryRead{error: Io.Error}
  CommitUnknown{error: Io.Error}
  FrameTooLarge{}
  StaleOwner{}
  CorrelationMismatch{}
  RequestIdsExhausted{}

# Keeps one canonical endpoint, owner generation, and request sequence.
type Session is Type:
  Session{endpoint: String, generation: U32,
    requests: Policy.RequestSequence}

def u32.clone.pair.from(triple: U32 & U32 & U32) -> U32 & U32:
  match triple:
    case (first, (second, _)): (first, second)

def u32.clone.pair(value: U32) -> U32 & U32:
  u32.clone.pair.from(Protocol.u32.duplicate.triple(value))

def request.clone.payload(
  versions: U32 & U32,
  generations: U32 & U32,
  request_ids: U32 & U32,
  operations: U32 & U32,
  payloads: Bytes.Bytes & Bytes.Bytes
) -> Protocol.Request & Protocol.Request:
  match versions:
    case (version, version_copy):
      match generations:
        case (generation, generation_copy):
          match request_ids:
            case (request_id, request_id_copy):
              match operations:
                case (operation, operation_copy):
                  match payloads:
                    case (first, second):
                      (Protocol.Request{version, generation, request_id,
                        operation, first},
                        Protocol.Request{version_copy, generation_copy,
                          request_id_copy, operation_copy, second})

def request.clone.pair(
  request: Protocol.Request
) -> Protocol.Request & Protocol.Request:
  match request:
    case Protocol.Request{version, generation, request_id, operation, payload}:
      request.clone.payload(u32.clone.pair(version),
        u32.clone.pair(generation), u32.clone.pair(request_id),
        u32.clone.pair(operation), ByteMemTable.bytes.clone(payload))

def status.clone.pair(
  status: Protocol.ResponseStatus
) -> Protocol.ResponseStatus & Protocol.ResponseStatus:
  match status:
    case Protocol.Success{}: (Protocol.Success{}, Protocol.Success{})
    case Protocol.InvalidArgument{}:
      (Protocol.InvalidArgument{}, Protocol.InvalidArgument{})
    case Protocol.NotFound{}: (Protocol.NotFound{}, Protocol.NotFound{})
    case Protocol.Busy{}: (Protocol.Busy{}, Protocol.Busy{})
    case Protocol.Timeout{}: (Protocol.Timeout{}, Protocol.Timeout{})
    case Protocol.ResponseResourceLimit{}:
      (Protocol.ResponseResourceLimit{}, Protocol.ResponseResourceLimit{})
    case Protocol.Corruption{}: (Protocol.Corruption{}, Protocol.Corruption{})
    case Protocol.IoFailure{}: (Protocol.IoFailure{}, Protocol.IoFailure{})
    case Protocol.CommitUnknown{}:
      (Protocol.CommitUnknown{}, Protocol.CommitUnknown{})
    case Protocol.AlreadyExists{}:
      (Protocol.AlreadyExists{}, Protocol.AlreadyExists{})
    case Protocol.UnsupportedPlatform{}:
      (Protocol.UnsupportedPlatform{}, Protocol.UnsupportedPlatform{})
    case Protocol.InvalidUtf8{}: (Protocol.InvalidUtf8{}, Protocol.InvalidUtf8{})
    case Protocol.UnsupportedFormat{}:
      (Protocol.UnsupportedFormat{}, Protocol.UnsupportedFormat{})

def response.clone.payload(
  versions: U32 & U32,
  generations: U32 & U32,
  request_ids: U32 & U32,
  statuses: Protocol.ResponseStatus & Protocol.ResponseStatus,
  payloads: Bytes.Bytes & Bytes.Bytes
) -> Protocol.Response & Protocol.Response:
  match versions:
    case (version, version_copy):
      match generations:
        case (generation, generation_copy):
          match request_ids:
            case (request_id, request_id_copy):
              match statuses:
                case (status, status_copy):
                  match payloads:
                    case (first, second):
                      (Protocol.Response{version, generation, request_id,
                        status, first},
                        Protocol.Response{version_copy, generation_copy,
                          request_id_copy, status_copy, second})

def response.clone.pair(
  response: Protocol.Response
) -> Protocol.Response & Protocol.Response:
  match response:
    case Protocol.Response{version, generation, request_id, status, payload}:
      response.clone.payload(u32.clone.pair(version),
        u32.clone.pair(generation), u32.clone.pair(request_id),
        status.clone.pair(status),
        ByteMemTable.bytes.clone(payload))

def result.failure(error: Error) -> Result<&1, &1, Error, Protocol.Response>:
  Fail{error}

def result.response(
  response: Protocol.Response
) -> Result<&1, &1, Error, Protocol.Response>:
  Done{response}

def disconnect.error(mutation: Bool, error: Io.Error) -> Error:
  match mutation:
    case True{}: CommitUnknown{error}
    case False{}: RetryRead{error}

def response.validation.fields(
  response_fields: U32 & U32 & U32,
  request_fields: U32 & U32 & U32,
  generations: U32 & U32 & U32
) -> Policy.Decision:
  match response_fields:
    case (version, (response_generation, request_id)):
      match request_fields:
        case (request_version, (request_generation, expected_id)):
          match generations:
            case (response_generation_check,
                (request_generation_check, generation)):
              Policy.response.validate(
                U32.to_nat(generation),
                U32.is_eq(response_generation, response_generation_check) &&
                  U32.is_eq(request_generation, request_generation_check),
                U32.is_eq(version, request_version) &&
                  U32.is_eq(request_id, expected_id))

def response.validation.request(
  response: Protocol.Response,
  request: Protocol.Request,
  generations: U32 & U32 & U32
) -> Policy.Decision:
  match response:
    case Protocol.Response{version, response_generation, request_id, _, _}:
      match request:
        case Protocol.Request{request_version, request_generation,
            expected_id, _, _}:
          response.validation.fields((version,
            (response_generation, request_id)),
            (request_version, (request_generation, expected_id)), generations)

def response.validation(
  response: Protocol.Response,
  request: Protocol.Request,
  generation: U32
) -> Policy.Decision:
  response.validation.request(response, request,
    Protocol.u32.duplicate.triple(generation))

def response.checked.result(
  response: Protocol.Response,
  decision: Policy.Decision
) -> Result<&1, &1, Error, Protocol.Response>:
  match decision:
    case Policy.ClientConfirmed{_}: result.response(response)
    case Policy.ClientStaleOwner{}: result.failure(StaleOwner{})
    case Policy.ClientProtocolFailure{}: result.failure(CorrelationMismatch{})
    case _: result.failure(CorrelationMismatch{})

def response.checked.request_copy(
  retained: Protocol.Response,
  checked: Protocol.Response,
  generation: U32,
  requests: Protocol.Request & Protocol.Request
) -> Result<&1, &1, Error, Protocol.Response>:
  match requests:
    case (_, checked_request):
      response.checked.result(retained,
        response.validation(checked, checked_request, generation))

def response.checked.copies(
  responses: Protocol.Response & Protocol.Response,
  requests: Protocol.Request & Protocol.Request,
  generation: U32
) -> Result<&1, &1, Error, Protocol.Response>:
  match responses:
    case (retained, checked):
      response.checked.request_copy(retained, checked, generation, requests)

def response.checked(
  response: Protocol.Response,
  request: Protocol.Request,
  generation: U32
) -> Result<&1, &1, Error, Protocol.Response>:
  response.checked.copies(response.clone.pair(response),
    request.clone.pair(request), generation)

def response.read(
  pair: File & Result<&1, &1, Io.Error, Protocol.Response>,
  request: Protocol.Request,
  generation: U32,
  mutation: Bool
) -> IO(Result<&1, &1, Error, Protocol.Response>):
  match pair:
    case (client, Done{response}):
      do IO<Result<&1, &1, Error, Protocol.Response>>:
        _closed : Unit <- File.close(client)
        return response.checked(response, request, generation)
    case (client, Fail{error}):
      do IO<Result<&1, &1, Error, Protocol.Response>>:
        _closed : Unit <- File.close(client)
        return result.failure(disconnect.error(mutation, error))

def response.request(
  client: File,
  request: Protocol.Request,
  generation: U32,
  mutation: Bool
) -> IO(Result<&1, &1, Error, Protocol.Response>):
  do IO<Result<&1, &1, Error, Protocol.Response>>:
    response : File & Result<&1, &1, Io.Error, Protocol.Response> <-
      Io.read_response(client)
    response.read(response, request, generation, mutation)

# Sends a frame result into response reading or mutation uncertainty.
def written(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  request: Protocol.Request,
  generation: U32,
  mutation: Bool
) -> IO(Result<&1, &1, Error, Protocol.Response>):
  match pair:
    case (client, Done{Unit{}}):
      response.request(client, request, generation, mutation)
    case (client, Fail{(code, message)}):
      do IO<Result<&1, &1, Error, Protocol.Response>>:
        _closed : Unit <- File.close(client)
        return result.failure(disconnect.error(mutation,
          Io.host.error(code, message)))

def connected.requests(
  client: File,
  generation: U32,
  mutation: Bool,
  requests: Protocol.Request & Protocol.Request
) -> IO(Result<&1, &1, Error, Protocol.Response>):
  match requests:
    case (wire_request, retained_request):
      do IO<Result<&1, &1, Error, Protocol.Response>>:
        write_result : File & Result<&1, &1, U32 & String, Unit> <-
          Io.write_all(client, Protocol.encode(wire_request))
        written(write_result, retained_request, generation, mutation)

# Writes one request after the owner endpoint accepts the connection.
def connected(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>,
  request: Protocol.Request,
  generation: U32,
  mutation: Bool
) -> IO(Result<&1, &1, Error, Protocol.Response>):
  match pair:
    case (client, Done{Unit{}}):
      connected.requests(client, generation, mutation,
        request.clone.pair(request))
    case (client, Fail{error}):
      do IO<Result<&1, &1, Error, Protocol.Response>>:
        _closed : Unit <- File.close(client)
        return result.failure(ConnectFailure{error})

# Connects a new socket and classifies failures before dispatch.
def created(
  result: Result<&1, &1, UnixSocket.Error, File>,
  endpoint: String,
  request: Protocol.Request,
  generation: U32,
  mutation: Bool
) -> IO(Result<&1, &1, Error, Protocol.Response>):
  match result:
    case Done{client}:
      do IO<Result<&1, &1, Error, Protocol.Response>>:
        connection : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.connect(client, endpoint)
        connected(connection, request, generation, mutation)
    case Fail{error}:
      IO.pure(Result<&1, &1, Error, Protocol.Response>,
        result.failure(ConnectFailure{error}))

def call.admitted(
  endpoint: String,
  request: Protocol.Request,
  generation: U32,
  mutation: Bool,
  admitted: Bool
) -> IO(Result<&1, &1, Error, Protocol.Response>):
  match admitted:
    case False{}:
      IO.pure(Result<&1, &1, Error, Protocol.Response>,
        result.failure(FrameTooLarge{}))
    case True{}:
      do IO<Result<&1, &1, Error, Protocol.Response>>:
        client : Result<&1, &1, UnixSocket.Error, File> <-
          UnixSocket.create()
        created(client, endpoint, request, generation, mutation)

def call.request.size(
  endpoint: String,
  fields: U32 & U32 & U32 & U32 & U32,
  generation: U32,
  measured_payload: Bytes.Bytes & U32
) -> IO(Result<&1, &1, Error, Protocol.Response>):
  match fields:
    case (version, (request_generation, (request_id,
        (policy_operation, wire_operation)))):
      match measured_payload:
        case (payload, length):
          call.admitted(endpoint,
            Protocol.Request{version, request_generation, request_id,
              wire_operation, payload}, generation,
            Policy.operation.is_mutation(policy_operation),
            Policy.request.within_payload_limit(length))

# Sends one bounded owner request and never retries it implicitly.
def call(
  endpoint: String,
  request: Protocol.Request,
  generation: U32
) -> IO(Result<&1, &1, Error, Protocol.Response>):
  match request:
    case Protocol.Request{version, request_generation, request_id, operation,
        payload}:
      call.request.size(endpoint,
        (version, (request_generation, (request_id,
          u32.clone.pair(operation)))), generation, Bytes.length(payload))

def string.clone.pair.go(
  value: String,
  left: String,
  right: String
) -> String & String:
  match value:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      string.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

def string.clone.pair(value: String) -> String & String:
  string.clone.pair.go(value, SNil{}, SNil{})

# Starts one client session with its first request identifier.
def session.open(endpoint: String, generation: U32) -> Session:
  Session{endpoint, generation, Policy.RequestAvailable{1}}

def session.call.ready(
  endpoints: String & String,
  generations: U32 & U32 & U32,
  request_id: U32,
  operation: U32,
  next: Policy.RequestSequence,
  payload: Bytes.Bytes
) -> IO(Session & Result<&1, &1, Error, Protocol.Response>):
  match endpoints:
    case (call_endpoint, retained_endpoint):
      match generations:
        case (request_generation, (active_generation, retained_generation)):
          do IO<Session & Result<&1, &1, Error, Protocol.Response>>:
            response : Result<&1, &1, Error, Protocol.Response> <-
              call(call_endpoint,
                Protocol.Request{1, request_generation, request_id,
                  operation, payload}, active_generation)
            return (Session{retained_endpoint, retained_generation, next},
              response)

def session.call.decision(
  endpoint: String,
  generation: U32,
  operation: U32,
  payload: Bytes.Bytes,
  decision: Policy.RequestDecision
) -> IO(Session & Result<&1, &1, Error, Protocol.Response>):
  match decision:
    case Policy.RequestAssigned{id, next}:
      session.call.ready(string.clone.pair(endpoint),
        Protocol.u32.duplicate.triple(generation), id, operation, next, payload)
    case Policy.RequestIdsExhausted{}:
      IO.pure(Session & Result<&1, &1, Error, Protocol.Response>,
        (Session{endpoint, generation, Policy.RequestExhausted{}},
          Fail{RequestIdsExhausted{}}))

# Sends one operation with the next unique ID and retains the updated session.
def session.call(
  session: Session,
  operation: U32,
  payload: Bytes.Bytes
) -> IO(Session & Result<&1, &1, Error, Protocol.Response>):
  match session:
    case Session{endpoint, generation, requests}:
      session.call.decision(endpoint, generation, operation, payload,
        Policy.request_id.take(requests))

# Sends a byte get and retains the next request sequence.
def session.get(
  session: Session,
  key: Bytes.Bytes
) -> IO(Session & Result<&1, &1, Error, Protocol.Response>):
  session.call(session, 1, key)

# Sends a byte put and retains the next request sequence.
def session.put(
  session: Session,
  key: Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Session & Result<&1, &1, Error, Protocol.Response>):
  session.call(session, 2, Operation.encode.put(key, value))

# Sends a byte delete and retains the next request sequence.
def session.delete(
  session: Session,
  key: Bytes.Bytes
) -> IO(Session & Result<&1, &1, Error, Protocol.Response>):
  session.call(session, 3, key)

# Sends a flush operation and retains the next request sequence.
def session.flush(
  session: Session
) -> IO(Session & Result<&1, &1, Error, Protocol.Response>):
  session.call(session, 4, Bytes.new(0))

# Sends a compaction operation and retains the next request sequence.
def session.compact(
  session: Session
) -> IO(Session & Result<&1, &1, Error, Protocol.Response>):
  session.call(session, 5, Bytes.new(0))

# Sends a stats operation and retains the next request sequence.
def session.stats(
  session: Session
) -> IO(Session & Result<&1, &1, Error, Protocol.Response>):
  session.call(session, 6, Bytes.new(0))
