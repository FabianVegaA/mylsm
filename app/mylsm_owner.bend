import Base
import ../src/ByteDurableDb.bend as ByteDb
import ../src/ByteMemTable.bend as ByteMemTable
import ../src/Console.bend as Console
import ../src/DbLock.bend as DbLock
import ../src/Fs.bend as Fs
import ../src/coordinator/EndpointPath.bend as EndpointPath
import ../src/coordinator/Owner.bend as Owner
import ../src/coordinator/UnixSocketIo.bend as UnixSocket
import ../src/scan/VisibleStats.bend as VisibleStats

# Closes the database handle before terminating owner startup or service.
def stop(handle: ByteDb.Handle, message: String) -> IO(Unit):
  do IO<Unit>:
    _closed : Result<&1, &1, ByteDb.Error, Unit> <- ByteDb.close(handle)
    IO.die(Unit, 1, message)

def path.clone.pair.go(path: String, left: String, right: String) -> String & String:
  match path:
    case SNil{}: (String.reverse(left), String.reverse(right))
    case SCon{+character, rest}:
      path.clone.pair.go(rest, SCon{character, left}, SCon{character, right})

def path.clone.pair(path: String) -> String & String:
  path.clone.pair.go(path, SNil{}, SNil{})

def start.listening(
  handle: ByteDb.Handle,
  endpoint: String,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (server, Done{Unit{}}):
      Owner.serve.loop(4294967295n,
        Owner.Serving{server, handle, endpoint, 1})
    case (server, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        stop(handle, "owner listen failed")

def start.permissions(
  handle: ByteDb.Handle,
  endpoint: String,
  server: File,
  result: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match result:
    case Done{Unit{}}:
      do IO<Unit>:
        listened : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.listen(server, 64)
        start.listening(handle, endpoint, listened)
    case Fail{_}:
      do IO<Unit>:
        _closed : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        stop(handle, "owner socket permissions could not be restricted")

def start.bound.paths(
  handle: ByteDb.Handle,
  server: File,
  paths: String & String
) -> IO(Unit):
  match paths:
    case (chmod_path, listener_path):
      do IO<Unit>:
        permissions : Result<&1, &1, U32 & String, Unit> <- Fs.chmod(chmod_path, 384)
        start.permissions(handle, listener_path, server, permissions)

def start.bound(
  handle: ByteDb.Handle,
  endpoint: String,
  result: File & Result<&1, &1, UnixSocket.Error, Unit>
) -> IO(Unit):
  match result:
    case (server, Done{Unit{}}):
      start.bound.paths(handle, server, path.clone.pair(endpoint))
    case (server, Fail{_}):
      do IO<Unit>:
        _closed : Unit <- File.close(server)
        _removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(endpoint)
        stop(handle, "owner socket bind failed")

def start.socket.bind(
  handle: ByteDb.Handle,
  server: File,
  paths: String & String
) -> IO(Unit):
  match paths:
    case (bind_path, retained_path):
      do IO<Unit>:
        bound : File & Result<&1, &1, UnixSocket.Error, Unit> <-
          UnixSocket.bind(server, bind_path)
        start.bound(handle, retained_path, bound)

def start.socket(
  handle: ByteDb.Handle,
  endpoint: String,
  result: Result<&1, &1, UnixSocket.Error, File>
) -> IO(Unit):
  match result:
    case Done{server}:
      start.socket.bind(handle, server, path.clone.pair(endpoint))
    case Fail{_}: stop(handle, "owner socket creation failed")

def endpoint.ready(
  handle: ByteDb.Handle,
  result: EndpointPath.Decision
) -> IO(Unit):
  match result:
    case EndpointPath.Endpoint{path}:
      do IO<Unit>:
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        start.socket(handle, path, created)
    case EndpointPath.PathTooLong{}:
      stop(handle, "owner socket path exceeds the platform limit")

def stale.removal.result(
  handle: ByteDb.Handle,
  endpoint: String,
  removed: Result<&1, &1, U32 & String, Unit>
) -> IO(Unit):
  match removed:
    case Fail{_}: stop(handle, "stale owner endpoint could not be removed")
    case Done{Unit{}}:
      do IO<Unit>:
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        start.socket(handle, endpoint, created)

def stale.removing(handle: ByteDb.Handle, paths: String & String) -> IO(Unit):
  match paths:
    case (remove_path, retained_path):
      do IO<Unit>:
        removed : Result<&1, &1, U32 & String, Unit> <- Fs.remove(remove_path)
        stale.removal.result(handle, retained_path, removed)

def stale.removed(
  handle: ByteDb.Handle,
  endpoint: String,
  exists: Result<&1, &1, U32 & String, Bool>
) -> IO(Unit):
  match exists:
    case Fail{_}: stop(handle, "owner endpoint inspection failed")
    case Done{False{}}:
      do IO<Unit>:
        created : Result<&1, &1, UnixSocket.Error, File> <- UnixSocket.create()
        start.socket(handle, endpoint, created)
    case Done{True{}}:
      stale.removing(handle, path.clone.pair(endpoint))

def owner.endpoint.exists(
  handle: ByteDb.Handle,
  paths: String & String
) -> IO(Unit):
  match paths:
    case (endpoint, inspect_path):
      do IO<Unit>:
        exists : Result<&1, &1, U32 & String, Bool> <- Fs.exists(inspect_path)
        stale.removed(handle, endpoint, exists)

def owner.endpoint(
  handle: ByteDb.Handle,
  result: EndpointPath.Decision
) -> IO(Unit):
  match result:
    case EndpointPath.Endpoint{path}:
      owner.endpoint.exists(handle, path.clone.pair(path))
    case EndpointPath.PathTooLong{}:
      stop(handle, "owner socket path exceeds the platform limit")

def owner.handle(
  handle: ByteDb.Handle,
  endpoint_path: String
) -> IO(Unit):
  owner.endpoint(handle, EndpointPath.for_canonical_path(endpoint_path))

def opened.canonical(
  paths: String & String,
  lock: DbLock.Lock,
  table: ByteMemTable.Table,
  state: ByteDb.HandleState,
  stats: VisibleStats.Stats
) -> IO(Unit):
  match paths:
    case (endpoint_path, handle_path):
      owner.handle(ByteDb.Handle{handle_path, lock, table, state, stats},
        endpoint_path)

# Publishes the canonical endpoint only after recovery has opened the database.
def opened(result: Result<&1, &1, ByteDb.Error, ByteDb.Handle>) -> IO(Unit):
  match result:
    case Done{handle}:
      match handle:
        case ByteDb.Handle{path, lock, table, state, stats}:
          opened.canonical(ByteDb.path.clone.pair(path), lock, table, state,
            stats)
    case Fail{_}: IO.die(Unit, 1, "owner failed to acquire and recover the database")

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, Console.get_env("MYLSM_DB_PATH"))
    handle : Result<&1, &1, ByteDb.Error, ByteDb.Handle> <-
      ByteDb.open_existing_wait(path, 5000, 25)
    opened(handle)
