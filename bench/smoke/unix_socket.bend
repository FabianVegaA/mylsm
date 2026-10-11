import Base
import ../../src/Console.bend as Console
import ../../src/Keys.bend as Keys
import ../../src/coordinator/EndpointPath.bend as EndpointPath
import ../../src/coordinator/Io.bend as CoordinatorIo
import ../../src/coordinator/Protocol.bend as Protocol
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket
import bend-kit-bytes@0.3.2.0/bytes.bend as Bytes

# Builds two independently owned path values for separate host operations.
def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

# Clones a path before passing it to independent host operations.
def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

def bytes.parsed(value: Maybe<&1, Bytes.Bytes>) -> Bytes.Bytes:
  match value:
    case Some{bytes}: bytes
    case None{}: Bytes.new(0)

def request.payload() -> Bytes.Bytes:
  bytes.parsed(Bytes.from_hex("00ff61"))

def request.header.slice(pair: Bytes.Bytes & Bytes.Bytes) -> Bytes.Bytes:
  match pair:
    case (_, header): header

def request.header() -> Bytes.Bytes:
  request.header.slice(Bytes.slice(Protocol.encode(Protocol.Request{
    1, 9, 78, 1, request.payload()}), 0, 24))

# Stops the fixture after releasing every socket it owns.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def socket.failure(action: String, error: UnixSocket.Error) -> IO(Unit):
  match error:
    case UnixSocket.UnsupportedPlatform{}:
      fail(action ++ " is unsupported on this platform")
    case UnixSocket.Host{code, _}:
      fail(action ++ " failed with host code " ++ Nat.show(U32.to_nat(code)))

# Reports completion after all socket descriptors are closed.
def removed() -> IO(Unit):
  IO.print("UNIX_SOCKET_PASSED")

# Closes all three descriptors and removes the endpoint.
def closed(sockets: File & File & File) -> IO(Unit):
  match sockets:
    case (server, (client, accepted)):
      do IO<Unit>:
        _accepted : Unit <- File.close(accepted)
        _client : Unit <- File.close(client)
        _server : Unit <- File.close(server)
        removed()

def payload.read.result(
  pair: File & Result<&1, &1, CoordinatorIo.Error, Protocol.Request>,
  server: File
) -> IO(Unit):
  match pair:
    case (connection, Fail{CoordinatorIo.Truncated{}}):
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        _server : Unit <- File.close(server)
        removed()
    case (connection, Fail{CoordinatorIo.Malformed{}}):
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        _server : Unit <- File.close(server)
        fail("partial payload was rejected as a malformed frame")
    case (connection, Fail{CoordinatorIo.Host{code, _}}):
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        _server : Unit <- File.close(server)
        fail("partial payload read failed with host code " ++ Nat.show(U32.to_nat(code)))
    case (connection, _):
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        _server : Unit <- File.close(server)
        fail("partial payload did not return a truncated-frame error")

def payload.accepted(
  pair: File & Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match pair:
    case (server, Done{connection}):
      do IO<Unit>:
        request : File & Result<&1, &1, CoordinatorIo.Error, Protocol.Request> <-
          CoordinatorIo.read_request(connection)
        payload.read.result(request, server)
    case (server, Fail{error}):
      do IO<Unit>:
        _server : Unit <- File.close(server)
        socket.failure("accept after payload disconnect", error)

def payload.client.sent(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  server: File
) -> IO(Unit):
  match pair:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        _client : Unit <- File.close(client)
        accepted : File & Result<&1, &1, UnixSocket.Error, File> <-
          UnixSocket.accept(server)
        payload.accepted(accepted)
    case (client, Fail{_}):
      do IO<Unit>:
        _client : Unit <- File.close(client)
        _server : Unit <- File.close(server)
        fail("partial payload header could not be written")

def payload.client.connected(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>,
  server: File
) -> IO(Unit):
  match pair:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        sent : File & Result<&1, &1, U32 & String, Unit> <-
          CoordinatorIo.write_all(client, request.header())
        payload.client.sent(sent, server)
    case (client, Fail{error}):
      do IO<Unit>:
        _client : Unit <- File.close(client)
        _server : Unit <- File.close(server)
        socket.failure("connect before payload disconnect", error)

def payload.client.created(
  path: String,
  server: File,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match result:
    case Done{client}:
      do IO<Unit>:
        connected : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.connect(client, path)
        payload.client.connected(connected, server)
    case Fail{error}:
      do IO<Unit>:
        _server : Unit <- File.close(server)
        socket.failure("create client before payload disconnect", error)

def truncated.read.result(
  pair: File & Result<&1, &1, CoordinatorIo.Error, Protocol.Request>,
  server: File,
  path: String
) -> IO(Unit):
  match pair:
    case (connection, Fail{CoordinatorIo.Truncated{}}):
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        payload.client.created(path, server, created)
    case (connection, _):
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        _server : Unit <- File.close(server)
        fail("partial request did not return a truncated-frame error")

def truncated.accepted(
  path: String,
  pair: File & Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match pair:
    case (server, Done{connection}):
      do IO<Unit>:
        request : File & Result<&1, &1, CoordinatorIo.Error, Protocol.Request> <-
          CoordinatorIo.read_request(connection)
        truncated.read.result(request, server, path)
    case (server, Fail{error}):
      do IO<Unit>:
        _server : Unit <- File.close(server)
        socket.failure("accept after client disconnect", error)

def truncated.client.sent(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  server: File,
  path: String
) -> IO(Unit):
  match pair:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        _client : Unit <- File.close(client)
        accepted : File & Result<&1, &1, UnixSocket.Error, File> <-
          UnixSocket.accept(server)
        truncated.accepted(path, accepted)
    case (client, Fail{_}):
      do IO<Unit>:
        _client : Unit <- File.close(client)
        _server : Unit <- File.close(server)
        fail("partial request header could not be written")

def truncated.client.connected(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>,
  server: File,
  path: String
) -> IO(Unit):
  match pair:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        sent : File & Result<&1, &1, U32 & String, Unit> <-
          CoordinatorIo.write_all(client, Bytes.new(8))
        truncated.client.sent(sent, server, path)
    case (client, Fail{error}):
      do IO<Unit>:
        _client : Unit <- File.close(client)
        _server : Unit <- File.close(server)
        socket.failure("connect before client disconnect", error)

def truncated.client.created(
  paths: String & String,
  server: File,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match paths:
    case (connect_path, retained_path):
      match result:
        case Done{client}:
          do IO<Unit>:
            connected : File & Result<&1, &1, UnixSocket.Error, Unit> <-
              UnixSocket.connect(client, connect_path)
            truncated.client.connected(connected, server, retained_path)
        case Fail{error}:
          do IO<Unit>:
            _server : Unit <- File.close(server)
            socket.failure("create client before disconnect", error)

def response.closed.result(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  server: File,
  path: String
) -> IO(Unit):
  match pair:
    case (connection, Fail{_}):
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        truncated.client.created(path.clone.pair(path), server, created)
    case (connection, Done{Unit{}}):
      do IO<Unit>:
        _connection : Unit <- File.close(connection)
        _server : Unit <- File.close(server)
        fail("response write succeeded after its client disconnected")

def request.checked(
  valid: Bool,
  sockets: File & File,
  connection: File,
  path: String
) -> IO(Unit):
  match valid:
    case True{}:
      match sockets:
        case (server, client):
          do IO<Unit>:
            _client : Unit <- File.close(client)
            response : File & Result<&1, &1, U32 & String, Unit> <-
              CoordinatorIo.write_all(connection, Protocol.encode_response(
                Protocol.Response{1, 9, 77, Protocol.Success{}, Bytes.new(262144)}))
            response.closed.result(response, server, path)
    case False{}:
      match sockets:
        case (server, client):
          do IO<Unit>:
            _connection : Unit <- File.close(connection)
            _client : Unit <- File.close(client)
            _server : Unit <- File.close(server)
            fail("socket request frame did not match its encoded request")

def request.result(
  pair: File & Result<&1, &1, CoordinatorIo.Error, Protocol.Request>,
  sockets: File & File,
  path: String
) -> IO(Unit):
  match pair:
    case (connection, Done{Protocol.Request{_, _, request_id, operation, payload}}):
      request.checked(U32.is_eq(request_id, 77) && U32.is_eq(operation, 1) &&
        Keys.Bytes.eq(payload, request.payload()),
        sockets, connection, path)
    case (connection, Fail{_}):
      match sockets:
        case (server, client):
          do IO<Unit>:
            _connection : Unit <- File.close(connection)
            _client : Unit <- File.close(client)
            _server : Unit <- File.close(server)
            fail("socket request frame could not be read")

# Verifies a client frame on the accepted server-side connection.
def accepted(
  client: File,
  path: String,
  pair: File & Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match pair:
    case (server, Done{connection}):
      do IO<Unit>:
        request : File & Result<&1, &1, CoordinatorIo.Error, Protocol.Request> <-
          CoordinatorIo.read_request(connection)
        request.result(request, (server, client), path)
    case (server, Fail{_}):
      do IO<Unit>:
        _client : Unit <- File.close(client)
        _server : Unit <- File.close(server)
        fail("local socket accept failed")

# Connects the client before waiting for the queued server connection.
def connected.sent(
  pair: File & Result<&1, &1, U32 & String, Unit>,
  server: File,
  path: String
) -> IO(Unit):
  match pair:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, File> <-
          UnixSocket.accept(server)
        accepted(client, path, result)
    case (client, Fail{_}):
      do IO<Unit>:
        _client : Unit <- File.close(client)
        _server : Unit <- File.close(server)
        fail("local socket request write failed")

# Creates and connects the local client descriptor.
def connected(
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>,
  server: File,
  path: String
) -> IO(Unit):
  match pair:
    case (client, Done{Unit{}}):
      do IO<Unit>:
        sent : File & Result<&1, &1, U32 & String, Unit> <-
          CoordinatorIo.write_all(client, Protocol.encode(Protocol.Request{
            1, 9, 77, 1, request.payload()}))
        connected.sent(sent, server, path)
    case (client, Fail{_}):
      do IO<Unit>:
        _client : Unit <- File.close(client)
        _server : Unit <- File.close(server)
        fail("local socket connect failed")

def client.created.path(
  paths: String & String,
  server: File,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match paths:
    case (connect_path, retained_path):
      match result:
        case Done{client}:
          do IO<Unit>:
            connected_result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
              UnixSocket.connect(client, connect_path)
            connected(connected_result, server, retained_path)
        case Fail{_}:
          do IO<Unit>:
            _server : Unit <- File.close(server)
            fail("local client socket creation failed")

# Creates and connects the local client descriptor.
def client.created(
  path: String,
  server: File,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  client.created.path(path.clone.pair(path), server, result)

# Starts listening before opening the client connection.
def listening(
  path: String,
  pair: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match pair:
    case (server, Done{Unit{}}):
      do IO<Unit>:
        client_result : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        client.created(path, server, client_result)
    case (server, Fail{_}):
      do IO<Unit>:
        _server : Unit <- File.close(server)
        fail("local socket listen failed")

# Binds one socket descriptor before starting its listener.
def bound(path: String, pair: File & Result<&1, &1, UnixSocket.Error, Unit>) -> IO(Unit):
  match pair:
    case (server, Done{Unit{}}):
      do IO<Unit>:
        result : File & Result<&1, &1, UnixSocket.Error, Unit> <- UnixSocket.listen(server, 16)
        listening(path, result)
    case (server, Fail{error}):
      do IO<Unit>:
        _server : Unit <- File.close(server)
        socket.failure("local socket bind", error)

# Creates and binds one local server endpoint.
def server.created.paths(
  paths: String & String,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match paths:
    case (bind_path, retained_path):
      match result:
        case Done{server}:
          do IO<Unit>:
            bind_result : File & Result<&1, &1, UnixSocket.Error, Unit> <-
              UnixSocket.bind(server, bind_path)
            bound(retained_path, bind_result)
        case Fail{_}:
          fail("local server socket creation failed")

# Creates and binds one local server endpoint.
def server.created(path: String, result: Result<&1, &1, UnixSocket.Error, File>) -> IO(Unit):
  server.created.paths(path.clone.pair(path), result)

# Validates the endpoint path before entering the host socket boundary.
def endpoint.checked(
  decision: EndpointPath.Decision
) -> IO(Unit):
  match decision:
    case EndpointPath.PathTooLong{}:
      fail("canonical database path exceeds the local socket limit")
    case EndpointPath.Endpoint{path}:
      do IO<Unit>:
        result : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        server.created(path, result)

def main() -> IO(Unit):
  do IO<Unit>:
    canonical : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    endpoint.checked(EndpointPath.for_canonical_path(canonical))
