import Base
import ../../src/Console.bend as Console
import ../../src/coordinator/Client.bend as Client
import ../../src/coordinator/Operation.bend as Operation
import ../../src/coordinator/Protocol.bend as Protocol
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
def get.request(endpoint: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, Client.Error, Protocol.Response> <-
      Client.call(endpoint,
        Protocol.Request{1, 1, 42, 1, bytes.from_hex("00ff")}, 1)
    get.response(result)

def put.response.empty(
  endpoint: String,
  is_empty: Bool
) -> IO(Unit):
  match is_empty:
    case True{}: get.request(endpoint)
    case False{}: fail("coordinator put response carried data")

def put.response.length(
  endpoint: String,
  measured: Bytes.Bytes & U32
) -> IO(Unit):
  match measured:
    case (_, length): put.response.empty(endpoint, U32.is_eq(length, 0))

# Checks that the owner acknowledged the byte put with an empty payload.
def put.response(
  endpoint: String,
  result: Result<&1, &1, Client.Error, Protocol.Response>
) -> IO(Unit):
  match result:
    case Fail{_}: fail("coordinator client put failed")
    case Done{response}:
      match response:
        case Protocol.Response{_, _, _, status, payload}:
          match status:
            case Protocol.Success{}:
              put.response.length(endpoint, Bytes.length(payload))
            case _: fail("coordinator owner rejected the byte put")

# Sends a binary mutation through the public coordinator client transport.
def put.request(paths: String & String) -> IO(Unit):
  match paths:
    case (put_endpoint, get_endpoint):
      do IO<Unit>:
        result : Result<&1, &1, Client.Error, Protocol.Response> <-
          Client.call(put_endpoint,
            Protocol.Request{1, 1, 41, 2,
              Operation.encode.put(bytes.from_hex("00ff"),
                bytes.from_hex("80ff00"))}, 1)
        put.response(get_endpoint, result)

# Makes two independently owned endpoint paths for sequential requests.
def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

# Returns the endpoint pair used for put followed by get.
def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

# Exercises a serialized binary put and read through independent IPC calls.
def main() -> IO(Unit):
  do IO<Unit>:
    endpoint : String <- IO.try(String, Console.get_env("MYLSM_OWNER_ENDPOINT"))
    put.request(path.clone.pair(endpoint))
