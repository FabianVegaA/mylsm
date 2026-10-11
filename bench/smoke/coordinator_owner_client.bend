import Base
import ../../src/Console.bend as Console
import ../../src/coordinator/Client.bend as Client
import ../../src/coordinator/ByteClient.bend as ByteClient
import ../../src/coordinator/StatsCodec.bend as StatsCodec
import ../../src/coordinator/CursorCodec.bend as CursorCodec
import ../../src/coordinator/Io.bend as ClientIo
import ../../src/coordinator/Protocol.bend as Protocol
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket
import ../../src/ByteWal.bend as ByteWal
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Converts a parsed hexadecimal fixture into its exact request bytes.
def bytes.from_hex.result(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Decodes a hexadecimal fixture into the exact request bytes.
def bytes.from_hex(value: String) -> Bytes.Bytes:
  bytes.from_hex.result(Bytes.from_hex(value))

# Duplicates one numeric token for a wire request and its later assertion.
def token.duplicate.pair(ids: U32 & U32 & U32) -> U32 & U32:
  match ids:
    case (wire_id, (retained_id, _)): (wire_id, retained_id)

def token.duplicate(value: U32) -> U32 & U32:
  token.duplicate.pair(Protocol.u32.duplicate.triple(value))

# Extracts the equality result while preserving both compared byte buffers.
def bytes.equal(comparison: Bytes.Bytes & Bytes.Bytes & Bool) -> Bool:
  match comparison:
    case (_, (_, equal)): equal

# Stops the client after a transport or response assertion fails.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def owner.rejection.status(status: Protocol.ResponseStatus) -> IO(Unit):
  match status:
    case Protocol.InvalidArgument{}:
      IO.print("OWNER_CLIENT_ERROR_STATUS_PASSED")
    case _: fail("owner returned an unexpected typed failure status")

def owner.read.error(error: ClientIo.Error) -> IO(Unit):
  match error:
    case ClientIo.UnsupportedPlatform{}: fail("owner response socket unsupported")
    case ClientIo.Host{code, _}:
      fail("owner response read host error " ++ Nat.show(U32.to_nat(code)))
    case ClientIo.Truncated{}: fail("owner returned a truncated response")
    case ClientIo.Malformed{}: fail("owner response frame was malformed")
    case ClientIo.UnknownOperation{}: fail("owner response used an unknown operation")
    case ClientIo.FrameTooLarge{}: fail("owner response exceeded its frame limit")
    case ClientIo.MalformedResponse{}: fail("owner response payload was malformed")
    case ClientIo.UnexpectedResponse{}: fail("owner response tag was unexpected")
    case ClientIo.UnknownResponseStatus{}: fail("owner response status code was unknown")

def owner.rejection.checked(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match pair:
    case (_, Done{Unit{}}): fail("owner accepted malformed put arguments")
    case (_, Fail{Client.OwnerRejected{status}}): owner.rejection.status(status)
    case (_, Fail{Client.MalformedResponse{}}):
      fail("owner returned a malformed write response")
    case (_, Fail{Client.CorrelationMismatch{}}):
      fail("owner response correlation did not match")
    case (_, Fail{Client.StaleOwner{}}):
      fail("owner response generation was stale")
    case (_, Fail{Client.ConnectFailure{_}}):
      fail("owner status test could not connect")
    case (_, Fail{Client.RetryRead{error}}): owner.read.error(error)
    case (_, Fail{Client.CommitUnknown{_}}):
      fail("owner classified non-mutation as uncertain")
    case (_, Fail{Client.FrameTooLarge{}}):
      fail("owner status test request exceeded its frame limit")
    case (_, Fail{Client.RequestIdsExhausted{}}):
      fail("owner status test exhausted request identifiers")

def owner.rejection(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    response : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
    Client.session.call(session, 2, Bytes.new(0))
    owner.rejection.checked(ByteClient.write.result(response))

def get.missing.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): fail("coordinator client missing-key read failed")
    case (session, Done{None{}}): owner.rejection(session)
    case (_, Done{Some{_}}): fail("coordinator client found an absent key")

def get.missing(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>> <-
      ByteClient.get(session, bytes.from_hex("0102"))
    get.missing.result(pair)

# Confirms snapshot closure and continues with an unrelated missing-key read.
def snapshot.close.result(
  session: Client.Session,
  result: Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}: get.missing(session)
    case Fail{_}: fail("owner failed to close snapshot after cursor close")

# Preserves the client session while validating snapshot closure.
def snapshot.close.result.pair(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match pair:
    case (session, result): snapshot.close.result(session, result)

def snapshot.cursor.close.checked(
  session: Client.Session,
  snapshot_id: U32,
  result: Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        snapshot_result : Client.Session &
          Result<&1, &1, Client.Error, Unit> <-
            ByteClient.snapshot.close(session, snapshot_id)
        snapshot.close.result.pair(snapshot_result)
    case Fail{_}: fail("owner rejected explicit cursor close")

# Continues close assertions with the session returned by the owner.
def snapshot.cursor.close.pair(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>,
  snapshot_id: U32
) -> IO(Unit):
  match pair:
    case (session, result):
      snapshot.cursor.close.checked(session, snapshot_id, result)

def snapshot.cursor.close(
  session: Client.Session,
  snapshot_id: U32,
  cursor_id: U32
) -> IO(Unit):
  do IO<Unit>:
    closed : Client.Session & Result<&1, &1, Client.Error, Unit> <-
      ByteClient.snapshot.cursor.close(session, cursor_id)
    snapshot.cursor.close.pair(closed, snapshot_id)

def snapshot.close.busy.result(
  session: Client.Session,
  snapshot_id: U32,
  cursor_id: U32,
  result: Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{Client.OwnerRejected{Protocol.Busy{}}}:
      snapshot.cursor.close(session, snapshot_id, cursor_id)
    case _: fail("owner did not keep a snapshot busy while its cursor lived")

# Continues the Busy assertion with the live owner session.
def snapshot.close.busy.pair(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>,
  snapshot_id: U32,
  cursor_id: U32
) -> IO(Unit):
  match pair:
    case (session, outcome):
      snapshot.close.busy.result(session, snapshot_id, cursor_id, outcome)

def snapshot.close.busy.copied(
  session: Client.Session,
  snapshot_ids: U32 & U32,
  cursor_id: U32
) -> IO(Unit):
  match snapshot_ids:
    case (wire_snapshot, retained_snapshot):
      do IO<Unit>:
        result : Client.Session &
          Result<&1, &1, Client.Error, Unit> <-
            ByteClient.snapshot.close(session, wire_snapshot)
        snapshot.close.busy.pair(result, retained_snapshot, cursor_id)

def snapshot.close.busy(
  session: Client.Session,
  snapshot_id: U32,
  cursor_id: U32
) -> IO(Unit):
  snapshot.close.busy.copied(session, token.duplicate(snapshot_id), cursor_id)

# Requires both cursor key and value to match the raw binary fixture.
def snapshot.cursor.item.key.checked(
  comparison: Bytes.Bytes & Bytes.Bytes & Bool,
  value: Bytes.Bytes
) -> Bool:
  Bool.and(bytes.equal(comparison),
    bytes.equal(Bytes.eq(value, bytes.from_hex("80ff00"))))

# Compares one cursor item against the exact binary fixture.
def snapshot.cursor.item.matches(
  key: Bytes.Bytes,
  value: Bytes.Bytes
) -> Bool:
  snapshot.cursor.item.key.checked(Bytes.eq(key, bytes.from_hex("00ff")),
    value)

def snapshot.cursor.item.checked(
  session: Client.Session,
  snapshot_id: U32,
  cursor_id: U32,
  matches: Bool
) -> IO(Unit):
  match matches:
    case True{}: snapshot.close.busy(session, snapshot_id, cursor_id)
    case False{}: fail("owner cursor changed the first raw-byte item")

def snapshot.cursor.next.result(
  session: Client.Session,
  snapshot_id: U32,
  cursor_id: U32,
  result: Result<&1, &1, Client.Error, CursorCodec.Frame>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("owner cursor next request failed")
    case Done{CursorCodec.CursorItem{key, value}}:
      snapshot.cursor.item.checked(session, snapshot_id, cursor_id,
        snapshot.cursor.item.matches(key, value))
    case Done{CursorCodec.CursorEnd{}}:
      fail("owner cursor ended before returning its first item")

# Continues frame assertions with the session returned by the owner.
def snapshot.cursor.next.pair(
  pair: Client.Session & Result<&1, &1, Client.Error, CursorCodec.Frame>,
  snapshot_id: U32,
  cursor_id: U32
) -> IO(Unit):
  match pair:
    case (session, result):
      snapshot.cursor.next.result(session, snapshot_id, cursor_id, result)

# Keeps the owner cursor ID for the wire request and subsequent assertion.
def snapshot.cursor.next.copied(
  session: Client.Session,
  snapshot_id: U32,
  cursor_ids: U32 & U32
) -> IO(Unit):
  match cursor_ids:
    case (wire_id, retained_id):
      do IO<Unit>:
        next : Client.Session & Result<&1, &1, Client.Error,
          CursorCodec.Frame> <- ByteClient.snapshot.cursor.next(session,
            wire_id)
        snapshot.cursor.next.pair(next, snapshot_id, retained_id)

def snapshot.cursor.open.result(
  session: Client.Session,
  snapshot_id: U32,
  result: Result<&1, &1, Client.Error, U32>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("owner cursor open request failed")
    case Done{cursor_id}:
      snapshot.cursor.next.copied(session, snapshot_id,
        token.duplicate(cursor_id))

# Continues cursor checks with the session returned by the owner.
def snapshot.cursor.open.pair(
  pair: Client.Session & Result<&1, &1, Client.Error, U32>,
  snapshot_id: U32
) -> IO(Unit):
  match pair:
    case (session, result):
      snapshot.cursor.open.result(session, snapshot_id, result)

# Keeps the snapshot ID for validating the response after the wire call.
def snapshot.cursor.open.copied(
  session: Client.Session,
  snapshot_ids: U32 & U32
) -> IO(Unit):
  match snapshot_ids:
    case (wire_id, retained_id):
      do IO<Unit>:
        opened : Client.Session & Result<&1, &1, Client.Error, U32> <-
          ByteClient.snapshot.cursor.open(session, wire_id)
        snapshot.cursor.open.pair(opened, retained_id)

def snapshot.cursor.open(
  session: Client.Session,
  snapshot_id: U32
) -> IO(Unit):
  snapshot.cursor.open.copied(session, token.duplicate(snapshot_id))

# Compares a snapshot value before exercising the owner's cursor lifecycle.
def snapshot.get.value.checked(
  session: Client.Session,
  snapshot_id: U32,
  comparison: Bytes.Bytes & Bytes.Bytes & Bool
) -> IO(Unit):
  match comparison:
    case (_, (_, equal)):
      match equal:
        case True{}: snapshot.cursor.open(session, snapshot_id)
        case False{}: fail("snapshot read changed the raw binary value")

# Confirms an owner snapshot read before checking its cursor lifecycle.
def snapshot.get.result(
  session: Client.Session,
  snapshot_id: U32,
  result: Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("coordinator snapshot read failed")
    case Done{None{}}: fail("snapshot did not contain its key")
    case Done{Some{value}}:
      snapshot.get.value.checked(session, snapshot_id,
        Bytes.eq(value, bytes.from_hex("80ff00")))

# Continues a snapshot value assertion with its owner-issued token.
def snapshot.get.pair(
  pair: Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>,
  snapshot_id: U32
) -> IO(Unit):
  match pair:
    case (session, result):
      snapshot.get.result(session, snapshot_id, result)

# Reads one owner snapshot while preserving its ID for cursor creation.
def snapshot.open.checked.id.copied(
  session: Client.Session,
  snapshot_ids: U32 & U32
) -> IO(Unit):
  match snapshot_ids:
    case (wire_id, retained_id):
      do IO<Unit>:
        result : Client.Session & Result<&1, &1, Client.Error,
          Maybe<&1, Bytes.Bytes>> <- ByteClient.snapshot.get(session,
            wire_id, bytes.from_hex("00ff"))
        snapshot.get.pair(result, retained_id)

# Rejects zero IDs and reads the owner-held snapshot for a valid token.
def snapshot.open.checked.id.value(
  session: Client.Session,
  snapshot_id: U32,
  is_zero: Bool
) -> IO(Unit):
  match is_zero:
    case True{}: fail("owner allocated snapshot identifier zero")
    case False{}:
      snapshot.open.checked.id.copied(session,
        token.duplicate(snapshot_id))

# Reads the fixture key after the owner allocated a nonzero snapshot ID.
def snapshot.open.checked.id(
  session: Client.Session,
  ids: U32 & U32 & U32
) -> IO(Unit):
  match ids:
    case (check_id, (snapshot_id, _)):
      snapshot.open.checked.id.value(session, snapshot_id,
        U32.is_eq(check_id, 0))

# Continues after an owner token was allocated with a nonzero ID.
def snapshot.open.checked(
  pair: Client.Session & Result<&1, &1, Client.Error, U32>
) -> IO(Unit):
  match pair:
    case (session, Done{snapshot_id}):
      snapshot.open.checked.id(session,
        Protocol.u32.duplicate.triple(snapshot_id))
    case (_, Fail{_}): fail("coordinator client snapshot open failed")

# Opens and checks one owner-managed snapshot through the wire protocol.
def snapshot.open(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    opened : Client.Session & Result<&1, &1, Client.Error, U32> <-
      ByteClient.snapshot.open(session)
    snapshot.open.checked(opened)

def stats.checked(session: Client.Session, counters_match: Bool) -> IO(Unit):
  match counters_match:
    case True{}: snapshot.open(session)
    case False{}: fail("coordinator client stats returned wrong counters")

def stats.result(
  pair: Client.Session & Result<&1, &1, Client.Error, StatsCodec.Stats>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): fail("coordinator client stats failed")
    case (session, Done{StatsCodec.ByteStats{entries, payload_bytes}}):
      stats.checked(session,
        Nat.is_eq(entries, 3n) && Nat.is_eq(payload_bytes, 13n))

def stats.request(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error,
      StatsCodec.Stats> <-
      ByteClient.stats(session)
    stats.result(pair)

def batch.second.value.equal(
  pair: Client.Session & (Bytes.Bytes & Bytes.Bytes & Bool)
) -> IO(Unit):
  match pair:
    case (session, (_, (_, equal))):
      match equal:
        case True{}: stats.request(session)
        case False{}: fail("coordinator batch omitted its second mutation")

def batch.second.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): fail("coordinator second batch read failed")
    case (session, Done{Some{value}}):
      batch.second.value.equal((session,
        Bytes.eq(value, bytes.from_hex("ccdd"))))
    case (_, Done{None{}}): fail("coordinator batch omitted its second key")

def batch.second.get(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>> <-
      ByteClient.get(session, bytes.from_hex("0104"))
    batch.second.result(pair)

def batch.first.value.equal(
  pair: Client.Session & (Bytes.Bytes & Bytes.Bytes & Bool)
) -> IO(Unit):
  match pair:
    case (session, (_, (_, equal))):
      match equal:
        case True{}: batch.second.get(session)
        case False{}: fail("coordinator batch changed its first mutation")

def batch.first.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): fail("coordinator first batch read failed")
    case (session, Done{Some{value}}):
      batch.first.value.equal((session,
        Bytes.eq(value, bytes.from_hex("aabb"))))
    case (_, Done{None{}}): fail("coordinator batch omitted its first key")

def batch.read(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>> <-
      ByteClient.get(session, bytes.from_hex("0103"))
    batch.first.result(pair)

def batch.written(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): fail("coordinator byte batch failed")
    case (session, Done{Unit{}}): batch.read(session)

def batch.write(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Unit> <-
      ByteClient.write_batch(session,
        Con{ByteWal.Put{bytes.from_hex("0103"), bytes.from_hex("aabb")},
          Con{ByteWal.Put{bytes.from_hex("0104"), bytes.from_hex("ccdd")}, Nil{}}})
    batch.written(pair)

def get.response.value.equal(
  pair: Client.Session & (Bytes.Bytes & Bytes.Bytes & Bool)
) -> IO(Unit):
  match pair:
    case (session, (_, (_, equal))):
      match equal:
        case True{}: batch.write(session)
        case False{}: fail("coordinator client read changed bytes")

# Confirms that a byte get returns the exact non-UTF-8 value through IPC.
def get.response(
  session: Client.Session,
  result: Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("coordinator client get failed")
    case Done{Some{value}}:
      get.response.value.equal((session,
        Bytes.eq(value, bytes.from_hex("80ff00"))))
    case Done{None{}}: fail("coordinator owner did not find the byte key")

def get.request.confirmed(
  pair: Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  match pair:
    case (session, result): get.response(session, result)

# Sends one read request through the public coordinator client transport.
def get.request.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>>
) -> IO(Unit):
  get.request.confirmed(pair)

def get.request(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Maybe<&1, Bytes.Bytes>> <-
      ByteClient.get(session, bytes.from_hex("00ff"))
    get.request.result(pair)

def put.compacted(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): fail("coordinator client compaction failed")
    case (session, Done{Unit{}}): get.request(session)

def put.compact(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Unit> <-
      ByteClient.compact(session)
    put.compacted(pair)

def put.flushed(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match pair:
    case (_, Fail{_}): fail("coordinator client flush failed")
    case (session, Done{Unit{}}): put.compact(session)

def put.flush(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Unit> <-
      ByteClient.flush(session)
    put.flushed(pair)

def put.response(
  session: Client.Session,
  result: Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("coordinator client put failed")
    case Done{Unit{}}: put.flush(session)

def put.request.confirmed(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  match pair:
    case (session, result): put.response(session, result)

# Sends a binary mutation through the public coordinator client transport.
def put.request.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Unit>
) -> IO(Unit):
  put.request.confirmed(pair)

def put.request(endpoint: String) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Unit> <-
      ByteClient.put(Client.session.open(endpoint, 1),
        bytes.from_hex("00ff"), bytes.from_hex("80ff00"))
    put.request.result(pair)

def endpoint.clone.pair.go(
  endpoint: String,
  left: String,
  right: String
) -> String & String:
  match endpoint:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      endpoint.clone.pair.go(rest, SCon{character, left},
        SCon{character, right})

def endpoint.clone.pair(endpoint: String) -> String & String:
  endpoint.clone.pair.go(endpoint, SNil{}, SNil{})

def disconnect.connected(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match pair:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        _closed : Unit <- File.close(client)
        IO.print("OWNER_CLIENT_DISCONNECTED")
    case (client, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(client)
        fail("coordinator disconnect fixture could not connect")

def disconnect.created(
  pair: Result<&1, &1, UnixSocket.Error, File> & String
) -> IO(Unit):
  match pair:
    case (Done{client}, endpoint):
      do IO<Unit>:
        connected : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.connect(client, endpoint)
        disconnect.connected(connected)
    case (Fail{_}, _): fail("coordinator disconnect fixture could not create socket")

def disconnect.endpoint(paths: String & String) -> IO(Unit):
  match paths:
    case (endpoint, retained_endpoint):
      do IO<Unit>:
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        _disconnected : Unit <- disconnect.created((created, endpoint))
        put.request(retained_endpoint)

# Exercises a serialized binary put and read through independent IPC calls.
def main() -> IO(Unit):
  do IO<Unit>:
    endpoint : String <- IO.try(String, Console.get_env("MYLSM_OWNER_ENDPOINT"))
    disconnect.endpoint(endpoint.clone.pair(endpoint))
