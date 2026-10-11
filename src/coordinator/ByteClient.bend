import Base
import ./Client.bend as Client
import ./ClientPolicy.bend as Policy
import ./Protocol.bend as Protocol
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def result.failure(
  error: Client.Error
) -> Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>:
  Fail{error}

def result.value(
  value: Maybe<&1, Bytes.Bytes>
) -> Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>:
  Done{value}

def get.outcome(
  outcome: Policy.GetStatus,
  payload: Bytes.Bytes
) -> Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>:
  match outcome:
    case Policy.GetValueStatus{}: result.value(Some{payload})
    case Policy.GetMissingStatus{}: result.value(None{})
    case Policy.GetFailureStatus{status}:
      result.failure(Client.OwnerRejected{status})

def get.status(
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes
) -> Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>:
  get.outcome(Policy.response.get.status(status), payload)

def get.response(
  result: Result<&1, &1, Client.Error, Protocol.Response>
) -> Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>:
  match result:
    case Fail{error}: result.failure(error)
    case Done{response}:
      match response:
        case Protocol.Response{_, _, _, status, payload}:
          get.status(status, payload)

def get.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Protocol.Response>
) -> Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>:
  match pair:
    case (session, result): (session, get.response(result))

# Reads one raw key and maps owner NotFound to an absent value.
def get(
  session: Client.Session,
  key: Bytes.Bytes
) -> IO(Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>):
  do IO<Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.get(session, key)
    return get.result(pair)

def write.payload(
  is_empty: Bool
) -> Result<&1, &1, Client.Error, Unit>:
  match is_empty:
    case True{}: Done{Unit{}}
    case False{}: Fail{Client.MalformedResponse{}}

def write.status(
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes & U32
) -> Result<&1, &1, Client.Error, Unit>:
  match status:
    case Protocol.Success{}:
      match payload:
        case (_, length): write.payload(U32.is_eq(length, 0))
    case _: Fail{Client.OwnerRejected{status}}

def write.response(
  result: Result<&1, &1, Client.Error, Protocol.Response>
) -> Result<&1, &1, Client.Error, Unit>:
  match result:
    case Fail{error}: Fail{error}
    case Done{response}:
      match response:
        case Protocol.Response{_, _, _, status, payload}:
          write.status(status, Bytes.length(payload))

def write.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Protocol.Response>
) -> Client.Session & Result<&1, &1, Client.Error, Unit>:
  match pair:
    case (session, result): (session, write.response(result))

# Writes one raw key/value pair through the serialized owner session.
def put(
  session: Client.Session,
  key: Bytes.Bytes,
  value: Bytes.Bytes
) -> IO(Client.Session & Result<&1, &1, Client.Error, Unit>):
  do IO<Client.Session & Result<&1, &1, Client.Error, Unit>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.put(session, key, value)
    return write.result(pair)

# Deletes one raw key through the serialized owner session.
def delete(
  session: Client.Session,
  key: Bytes.Bytes
) -> IO(Client.Session & Result<&1, &1, Client.Error, Unit>):
  do IO<Client.Session & Result<&1, &1, Client.Error, Unit>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.delete(session, key)
    return write.result(pair)
