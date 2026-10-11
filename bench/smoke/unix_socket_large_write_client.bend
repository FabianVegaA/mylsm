import Base
import ../../src/Console.bend as Console
import ../../src/coordinator/EndpointPath.bend as EndpointPath
import ../../src/coordinator/Io.bend as Io
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

# Returns independent path values for endpoint selection and validation.
def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

# Stops the client after closing its socket descriptor.
def fail(client: File, message: String) -> IO(Unit):
  do IO<Unit>:
    _closed : Unit <- File.close(client)
    IO.die(Unit, 1, message)

# Reports the result only after closing the client descriptor.
def written(
  pair: File & Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match pair:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        _closed : Unit <- File.close(client)
        IO.print("UNIX_SOCKET_LARGE_WRITE_CLIENT_PASSED")
    case (client, Fail{_}): fail(client, "large socket write failed")

# Writes the full payload while the server process reads it incrementally.
def connected(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match pair:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        result : File & Result<&1, &1, U32 & String, Unit> <-
          Io.write_all(client, Bytes.new(70000))
        written(result)
    case (client, Fail{_}): fail(client, "large socket connect failed")

# Connects to the server endpoint selected from the database path.
def endpoint.created(
  paths: String & String,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match paths:
    case (endpoint, _):
      match result:
        case Done{client}:
          do IO<Unit>:
            connection : File & Result<&1, &1, UnixSocket.Error, Unit> <-
              UnixSocket.connect(client, endpoint)
            connected(connection)
        case Fail{_}: IO.die(Unit, 1, "large socket client creation failed")

def endpoint.ready(decision: EndpointPath.Decision) -> IO(Unit):
  match decision:
    case EndpointPath.PathTooLong{}:
      IO.die(Unit, 1, "large socket endpoint path exceeds its limit")
    case EndpointPath.Endpoint{endpoint}:
      do IO<Unit>:
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        endpoint.created(path.clone.pair(endpoint), created)

# Opens the local client for one cross-process large transfer.
def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    endpoint.ready(EndpointPath.for_canonical_path(path))
