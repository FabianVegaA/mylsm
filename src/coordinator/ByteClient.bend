import Base
import ./Client.bend as Client
import ./ClientPolicy.bend as Policy
import ./Protocol.bend as Protocol
import ./CursorCodec.bend as CursorCodec
import ./OwnerCursorCodec.bend as OwnerCursorCodec
import ./CursorOpenCodec.bend as CursorOpenCodec
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

# Releases an owner snapshot token after its final cursor has closed.
def snapshot.close(
  session: Client.Session,
  snapshot_id: U32
) -> IO(Client.Session & Result<&1, &1, Client.Error, Unit>):
  do IO<Client.Session & Result<&1, &1, Client.Error, Unit>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.call(session, 11, Protocol.snapshot.id.bytes(snapshot_id))
    return write.result(pair)

# Maps one pure open-response decision into a client result.
def snapshot.cursor.open.decision(
  decision: OwnerCursorCodec.OpenDecision
) -> Result<&1, &1, Client.Error, U32>:
  match decision:
    case OwnerCursorCodec.Opened{cursor_id}: Done{cursor_id}
    case OwnerCursorCodec.OpenRejected{status}:
      Fail{Client.OwnerRejected{status}}
    case OwnerCursorCodec.OpenMalformed{}:
      Fail{Client.MalformedResponse{}}

def snapshot.cursor.open.status(
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes
) -> Result<&1, &1, Client.Error, U32>:
  snapshot.cursor.open.decision(OwnerCursorCodec.open(status, payload))

def snapshot.cursor.open.response(
  result: Result<&1, &1, Client.Error, Protocol.Response>
) -> Result<&1, &1, Client.Error, U32>:
  match result:
    case Fail{error}: Fail{error}
    case Done{response}:
      match response:
        case Protocol.Response{_, _, _, status, payload}:
          snapshot.cursor.open.status(status, payload)

def snapshot.cursor.open.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Protocol.Response>
) -> Client.Session & Result<&1, &1, Client.Error, U32>:
  match pair:
    case (session, result): (session, snapshot.cursor.open.response(result))

def snapshot.cursor.open.request(
  session: Client.Session,
  payload: Bytes.Bytes
) -> IO(Client.Session & Result<&1, &1, Client.Error, U32>):
  do IO<Client.Session & Result<&1, &1, Client.Error, U32>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.call(session, 12, payload)
    return snapshot.cursor.open.result(pair)

# Opens an owner cursor over one half-open byte range.
def snapshot.cursor.open.range(
  session: Client.Session,
  snapshot_id: U32,
  lower: Maybe<&1, Bytes.Bytes>,
  upper: Maybe<&1, Bytes.Bytes>
) -> IO(Client.Session & Result<&1, &1, Client.Error, U32>):
  snapshot.cursor.open.request(session,
    CursorOpenCodec.encode.range(snapshot_id, lower, upper))

# Opens an owner cursor over one exact raw-byte prefix.
def snapshot.cursor.open.prefix(
  session: Client.Session,
  snapshot_id: U32,
  prefix: Bytes.Bytes
) -> IO(Client.Session & Result<&1, &1, Client.Error, U32>):
  snapshot.cursor.open.request(session,
    CursorOpenCodec.encode.prefix(snapshot_id, prefix))

# Opens a full-range owner cursor over a retained snapshot.
def snapshot.cursor.open(
  session: Client.Session,
  snapshot_id: U32
) -> IO(Client.Session & Result<&1, &1, Client.Error, U32>):
  snapshot.cursor.open.range(session, snapshot_id, None{}, None{})

# Maps one pure next-response decision into a client result.
def snapshot.cursor.next.decision(
  decision: OwnerCursorCodec.NextDecision
) -> Result<&1, &1, Client.Error, CursorCodec.Frame>:
  match decision:
    case OwnerCursorCodec.NextFrame{frame}: Done{frame}
    case OwnerCursorCodec.NextRejected{status}:
      Fail{Client.OwnerRejected{status}}
    case OwnerCursorCodec.NextMalformed{}:
      Fail{Client.MalformedResponse{}}

def snapshot.cursor.next.status(
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes
) -> Result<&1, &1, Client.Error, CursorCodec.Frame>:
  snapshot.cursor.next.decision(OwnerCursorCodec.next(status, payload))

def snapshot.cursor.next.response(
  result: Result<&1, &1, Client.Error, Protocol.Response>
) -> Result<&1, &1, Client.Error, CursorCodec.Frame>:
  match result:
    case Fail{error}: Fail{error}
    case Done{response}:
      match response:
        case Protocol.Response{_, _, _, status, payload}:
          snapshot.cursor.next.status(status, payload)

def snapshot.cursor.next.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Protocol.Response>
) -> Client.Session & Result<&1, &1, Client.Error, CursorCodec.Frame>:
  match pair:
    case (session, result): (session, snapshot.cursor.next.response(result))

# Reads one raw-byte item or the terminal marker from an owner cursor.
def snapshot.cursor.next(
  session: Client.Session,
  cursor_id: U32
) -> IO(Client.Session & Result<&1, &1, Client.Error, CursorCodec.Frame>):
  do IO<Client.Session & Result<&1, &1, Client.Error, CursorCodec.Frame>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.call(session, 13, Protocol.snapshot.id.bytes(cursor_id))
    return snapshot.cursor.next.result(pair)

# Releases one owner cursor token through the serialized session.
# Maps one pure close-response decision into a client result.
def snapshot.cursor.close.decision(
  decision: OwnerCursorCodec.CloseDecision
) -> Result<&1, &1, Client.Error, Unit>:
  match decision:
    case OwnerCursorCodec.CloseSucceeded{}: Done{Unit{}}
    case OwnerCursorCodec.CloseRejected{status}:
      Fail{Client.OwnerRejected{status}}
    case OwnerCursorCodec.CloseMalformed{}:
      Fail{Client.MalformedResponse{}}

# Decodes the owner close status and requires its exact empty success body.
def snapshot.cursor.close.status(
  status: Protocol.ResponseStatus,
  payload: Bytes.Bytes
) -> Result<&1, &1, Client.Error, Unit>:
  snapshot.cursor.close.decision(OwnerCursorCodec.close(status, payload))

# Maps transport or owner response errors into one close result.
def snapshot.cursor.close.response(
  result: Result<&1, &1, Client.Error, Protocol.Response>
) -> Result<&1, &1, Client.Error, Unit>:
  match result:
    case Fail{error}: Fail{error}
    case Done{response}:
      match response:
        case Protocol.Response{_, _, _, status, payload}:
          snapshot.cursor.close.status(status, payload)

# Preserves the live client session after one close request.
def snapshot.cursor.close.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Protocol.Response>
) -> Client.Session & Result<&1, &1, Client.Error, Unit>:
  match pair:
    case (session, result): (session, snapshot.cursor.close.response(result))

def snapshot.cursor.close(
  session: Client.Session,
  cursor_id: U32
) -> IO(Client.Session & Result<&1, &1, Client.Error, Unit>):
  do IO<Client.Session & Result<&1, &1, Client.Error, Unit>>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.call(session, 14, Protocol.snapshot.id.bytes(cursor_id))
    return snapshot.cursor.close.result(pair)
