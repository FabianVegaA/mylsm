import Base
import ../../src/Console.bend as Console
import ../../src/Fs.bend as Fs
import ../../src/Keys.bend as Keys
import ../../src/coordinator/EndpointPath.bend as EndpointPath
import ../../src/coordinator/Io.bend as Io
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Stops the fixture after closing the descriptors available at this stage.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

# Returns two independently owned endpoint path values.
def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

# Closes the listener and removes its endpoint after the stream is consumed.
def finish.removed(
  removed: Result<&1, &1, U32 & String, Unit>,
  passed: Bool
) -> IO(Unit):
  match removed:
    case Fail{_}: fail("large socket endpoint cleanup failed")
    case Done{Unit{}}:
      match passed:
        case True{}: IO.print("UNIX_SOCKET_LARGE_WRITE_SERVER_PASSED")
        case False{}: fail("large socket payload differed after transfer")

def finish.result(
  server: File,
  connection: File,
  endpoint: String,
  result: Result<&1, &1, U32 & String, Io.ExactResult>
) -> IO(Unit):
  match result:
    case Done{Io.ExactResult{bytes, complete}}:
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        _server : Unit <- File.close(server)
        removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        finish.removed(removed,
          complete && Keys.Bytes.eq(bytes, Bytes.new(70000)))
    case Fail{_}:
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        _server : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        fail("large socket receive failed")

def read.result(
  server: File,
  endpoint: String,
  result: File & Result<&1, &1, U32 & String, Io.ExactResult>
) -> IO(Unit):
  match result:
    case (connection, outcome):
      finish.result(server, connection, endpoint, outcome)

# Reads the complete 70 KiB payload while the other process writes chunks.
def read.payload(
  server: File,
  connection: File,
  endpoint: String
) -> IO(Unit):
  do IO<Unit>:
    result : File & Result<&1, &1, U32 & String, Io.ExactResult> <-
      Io.exact.start(connection, 70000n)
    read.result(server, endpoint, result)

def listening.accepted(
  endpoint: String,
  pair: File & Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match pair:
    case (server, Done{connection}):
      read.payload(server, connection, endpoint)
    case (server, Fail{_}):
      do IO<Unit>:
        _server : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        fail("large socket accept failed")

# Accepts the client after publishing the endpoint as ready.
def listening(
  endpoint: String,
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match pair:
    case (server, Done{Unit{}}):
      do IO<Unit>:
        accepted : File & Result<&1, &1, UnixSocket.Error, File> <-
          UnixSocket.accept(server)
        listening.accepted(endpoint, accepted)
    case (server, Fail{_}):
      do IO<Unit>:
        _server : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        fail("large socket listen failed")

def endpoint.bound.result(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>,
  endpoint: String
) -> IO(Unit):
  match pair:
    case (listener, Done{Unit{}}):
      do IO<Unit>:
        listening_result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.listen(listener, 4)
        listening(endpoint, listening_result)
    case (listener, Fail{_}):
      do IO<Unit>:
        _server : Unit <- File.close(listener)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        fail("large socket bind failed")

# Binds and listens on the validated local endpoint.
def endpoint.bound(
  paths: String & String,
  server: File
) -> IO(Unit):
  match paths:
    case (bind_path, retained_path):
      do IO<Unit>:
        bound : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.bind(server, bind_path)
        endpoint.bound.result(bound, retained_path)

def endpoint.created(
  endpoint: String,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match result:
    case Done{server}:
      endpoint.bound(path.clone.pair(endpoint), server)
    case Fail{_}: fail("large socket creation failed")

# Creates the server descriptor only for an admitted endpoint path.
def endpoint.ready(decision: EndpointPath.Decision) -> IO(Unit):
  match decision:
    case EndpointPath.PathTooLong{}: fail("large socket endpoint path exceeds its limit")
    case EndpointPath.Endpoint{endpoint}:
      do IO<Unit>:
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        endpoint.created(endpoint, created)

# Opens the local server for one cross-process large transfer.
def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    endpoint.ready(EndpointPath.for_canonical_path(path))
