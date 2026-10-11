import Base
import ./Client.bend as Client
import ./ClientPolicy.bend as Policy
import ./Protocol.bend as Protocol
import ./StatsCodec.bend as StatsCodec
import ../ByteWal.bend as ByteWal
import ../Wal.bend as Wal
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

# Flushes the owner's durable WAL state through the serialized session.
def flush(
  session: Client.Session
) -> IO(Client.Session & Result<&1, &1, Client.Error, Unit>):
  do IO<Client.Session & Result<&1, &1, Client.Error, Unit>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.flush(session)
    return write.result(pair)

# Compacts the owner's durable state through the serialized session.
def compact(
  session: Client.Session
) -> IO(Client.Session & Result<&1, &1, Client.Error, Unit>):
  do IO<Client.Session & Result<&1, &1, Client.Error, Unit>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.compact(session)
    return write.result(pair)

def write_batch.encoded(
  session: Client.Session,
  encoded: Result<&1, &1, Wal.Error, Bytes.Bytes>
) -> IO(Client.Session & Result<&1, &1, Client.Error, Unit>):
  match encoded:
    case Fail{_}:
      IO.pure(Client.Session & Result<&1, &1, Client.Error, Unit>,
        (session, Fail{Client.FrameTooLarge{}}))
    case Done{payload}:
      do IO<Client.Session & Result<&1, &1, Client.Error, Unit>>:
        pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
          Client.session.call(session, 8, payload)
        return write.result(pair)

# Commits raw byte mutations as one owner-side atomic batch.
def write_batch(
  session: Client.Session,
  mutations: List<&1, ByteWal.Mutation>
) -> IO(Client.Session & Result<&1, &1, Client.Error, Unit>):
  write_batch.encoded(session, ByteWal.encode(ByteWal.Batch{mutations}))

def stats.payload(
  decision: StatsCodec.Decision
) -> Result<&1, &1, Client.Error, StatsCodec.Stats>:
  match decision:
    case StatsCodec.Parsed{stats}: Done{stats}
    case StatsCodec.Malformed{}: Fail{Client.MalformedResponse{}}

def stats.status(
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes
) -> Result<&1, &1, Client.Error, StatsCodec.Stats>:
  match status:
    case Protocol.Success{}: stats.payload(StatsCodec.parse(payload))
    case _: Fail{Client.OwnerRejected{status}}

def stats.response(
  response: Protocol.Response
) -> Result<&1, &1, Client.Error, StatsCodec.Stats>:
  match response:
    case Protocol.Response{_, _, _, status, payload}:
      stats.status(status, payload)

def stats.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Protocol.Response>
) -> Client.Session & Result<&1, &1, Client.Error, StatsCodec.Stats>:
  match pair:
    case (session, Fail{error}): (session, Fail{error})
    case (session, Done{response}): (session, stats.response(response))

# Reads owner entry and payload counters from a typed statistics response.
def stats(
  session: Client.Session
) -> IO(Client.Session & Result<&1, &1, Client.Error, StatsCodec.Stats>):
  do IO<Client.Session & Result<&1, &1, Client.Error, StatsCodec.Stats>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.stats(session)
    return stats.result(pair)

def snapshot.open.parsed(
  parsed: Maybe<&2, U32>
) -> Result<&1, &1, Client.Error, U32>:
  match parsed:
    case Some{snapshot_id}: Done{snapshot_id}
    case None{}: Fail{Client.MalformedResponse{}}

def snapshot.open.status(
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes
) -> Result<&1, &1, Client.Error, U32>:
  match status:
    case Protocol.Success{}:
      snapshot.open.parsed(Protocol.snapshot.id.read(payload))
    case _: Fail{Client.OwnerRejected{status}}

def snapshot.open.response(
  result: Result<&1, &1, Client.Error, Protocol.Response>
) -> Result<&1, &1, Client.Error, U32>:
  match result:
    case Fail{error}: Fail{error}
    case Done{response}:
      match response:
        case Protocol.Response{_, _, _, status, payload}:
          snapshot.open.status(status, payload)

def snapshot.open.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Protocol.Response>
) -> Client.Session & Result<&1, &1, Client.Error, U32>:
  match pair:
    case (session, result): (session, snapshot.open.response(result))

# Requests a retained snapshot from the serialized owner and returns its ID.
def snapshot.open(
  session: Client.Session
) -> IO(Client.Session & Result<&1, &1, Client.Error, U32>):
  do IO<Client.Session & Result<&1, &1, Client.Error, U32>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.call(session, 9, Bytes.new(0))
    return snapshot.open.result(pair)

# Prefixes a byte key with its fixed-width snapshot token.
def snapshot.get.payload(snapshot_id: U32, key: Bytes.Bytes) -> Bytes.Bytes:
  Bytes.concat([Protocol.snapshot.id.bytes(snapshot_id), key])

# Reads one key through a retained owner snapshot without changing its token.
def snapshot.get(
  session: Client.Session,
  snapshot_id: U32,
  key: Bytes.Bytes
) -> IO(Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>):
  do IO<Client.Session & Result<&1, &1, Client.Error,
      Maybe<&1, Bytes.Bytes>>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.call(session, 10, snapshot.get.payload(snapshot_id, key))
    return get.result(pair)
