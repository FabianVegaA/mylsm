import Base
import ../../src/coordinator/UnixSocketIo.bend as UnixSocket

# Fails if an unsupported runtime does not return its raw platform code.
def verify(result: Result<&1, &1, UnixSocket.Error, File>) -> IO(Unit):
  match result:
    case Done{socket}:
      do IO<Unit>:
        _closed : Unit <- File.close(socket)
        IO.die(Unit, 1, "unsupported runtime unexpectedly created a socket")
    case Fail{UnixSocket.UnsupportedPlatform{}}:
      IO.print("UNIX_SOCKET_UNSUPPORTED_PASSED")
    case Fail{_}: IO.die(Unit, 1, "unsupported runtime returned the wrong host code")

# Runs the paired JavaScript effect and checks its unsupported-platform code.
def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
    verify(result)
