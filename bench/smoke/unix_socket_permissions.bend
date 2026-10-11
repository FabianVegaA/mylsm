import Base
import ../../src/Console.bend as Console
import ../../src/coordinator/EndpointPath.bend as EndpointPath
import ../../src/coordinator/Protocol.bend as Protocol
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket

# Stops the permission fixture after an unexpected socket result.
def fail(message: String) -> IO(Unit):
  IO.die(Unit, 1, message)

def permission.result(correct: Bool) -> IO(Unit):
  match correct:
    case True{}: IO.print("UNIX_SOCKET_PERMISSION_PASSED")
    case False{}: fail("socket bind returned the wrong permission error")

def permission.code(copies: U32 & U32 & U32) -> Bool:
  match copies:
    case (denied, (restricted, _)):
      U32.is_eq(denied, 13) || U32.is_eq(restricted, 1)

# Checks that bind reports denial for a non-writable endpoint directory.
def result(pair: File & Result<&1, &1, UnixSocket.Error, Unit>) -> IO(Unit):
  match pair:
    case (server, Fail{UnixSocket.Host{code, _}}):
      do IO<Unit>:
        _server : Unit <- File.close(server)
        permission.result(permission.code(Protocol.u32.duplicate.triple(code)))
    case (server, Fail{_}):
      do IO<Unit>:
        _server : Unit <- File.close(server)
        fail("socket bind did not preserve the permission failure")
    case (server, Done{Unit{}}):
      do IO<Unit>:
        _server : Unit <- File.close(server)
        fail("socket bind succeeded in a read-only directory")

# Creates the socket descriptor before attempting the denied bind.
def created(
  path: String,
  created_result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match created_result:
    case Done{server}:
      do IO<Unit>:
        bound : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.bind(server, path)
        result(bound)
    case Fail{_}: fail("socket creation failed before permission check")

# Resolves the bounded endpoint path used by the permission fixture.
def endpoint(decision: EndpointPath.Decision) -> IO(Unit):
  match decision:
    case EndpointPath.Endpoint{path}:
      do IO<Unit>:
        server : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        created(path, server)
    case EndpointPath.PathTooLong{}: fail("test directory path exceeded socket limit")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    endpoint(EndpointPath.for_canonical_path(path))
