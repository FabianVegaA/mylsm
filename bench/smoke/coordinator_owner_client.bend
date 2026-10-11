import Base
import ../../src/Console.bend as Console
import ../../src/coordinator/Client.bend as Client
import ../../src/coordinator/Protocol.bend as Protocol
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Converts a parsed hexadecimal fixture into its exact request bytes.
def bytes.from_hex.result(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

# Decodes a hexadecimal fixture into the exact request bytes.
def bytes.from_hex(value: String) -> Bytes.Bytes:
  bytes.from_hex.result(Bytes.from_hex(value))

# Stops the client after a transport or response assertion fails.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def get.response.value.equal(
  pair: Bytes.Bytes & Bytes.Bytes & Bool
) -> IO(Unit):
  match pair:
    case (_, (_, equal)):
      match equal:
        case True{}: IO.print("OWNER_CLIENT_SOCKET_PASSED")
        case False{}: fail("coordinator client read changed bytes")

# Confirms that a byte get returns the exact non-UTF-8 value through IPC.
def get.response(
  result: Result<&1, &1, Client.Error, Protocol.Response>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("coordinator client get failed")
    case Done{response}:
      match response:
        case Protocol.Response{_, _, _, status, payload}:
          match status:
            case Protocol.Success{}:
              get.response.value.equal(Bytes.eq(payload,
                bytes.from_hex("80ff00")))
            case _: fail("coordinator owner did not find the byte key")

# Sends one read request through the public coordinator client transport.
def get.request.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Protocol.Response>
) -> IO(Unit):
  match pair:
    case (_, result): get.response(result)

def get.request(session: Client.Session) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.get(session, bytes.from_hex("00ff"))
    get.request.result(pair)

def put.response.session.empty(
  session: Client.Session,
  is_empty: Bool
) -> IO(Unit):
  match is_empty:
    case True{}: get.request(session)
    case False{}: fail("coordinator put response carried data")

# Checks that the owner acknowledged the byte put with an empty payload.
def put.response.session.length(
  session: Client.Session,
  measured: Bytes.Bytes & U32
) -> IO(Unit):
  match measured:
    case (_, length): put.response.session.empty(session, U32.is_eq(length, 0))

def put.response(
  session: Client.Session,
  result: Result<&1, &1, Client.Error, Protocol.Response>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("coordinator client put failed")
    case Done{response}:
      match response:
        case Protocol.Response{_, _, _, status, payload}:
          match status:
            case Protocol.Success{}:
              put.response.session.length(session, Bytes.length(payload))
            case _: fail("coordinator owner rejected the byte put")

# Sends a binary mutation through the public coordinator client transport.
def put.request.result(
  pair: Client.Session & Result<&1, &1, Client.Error, Protocol.Response>
) -> IO(Unit):
  match pair:
    case (session, result): put.response(session, result)

def put.request(endpoint: String) -> IO(Unit):
  do IO<Unit>:
    pair : Client.Session & Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.session.put(Client.session.open(endpoint, 1),
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
